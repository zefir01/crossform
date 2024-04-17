package executor

import (
	"crossform.io/pkg/logger"
	"cuelang.org/go/cue"
	"cuelang.org/go/cue/cuecontext"
	cueErrors "cuelang.org/go/cue/errors"
	"cuelang.org/go/cue/load"
	"encoding/json"
	"fmt"
	"github.com/crossplane/function-sdk-go/resource"
	"github.com/pkg/errors"
	"github.com/rs/zerolog"
	"golang.org/x/exp/maps"
	"os"
	"path/filepath"
	"strings"
)

type cueExecutor struct {
	ctx       *cue.Context
	instances map[string]*cue.Value
	path      string
	log       zerolog.Logger
	metadata  map[string]*metadata
	fields    map[string][]string
}

func newCueExecutor(path, observed, requested, xr, context string) (genericExecutor, error) {
	e := &cueExecutor{
		ctx:  cuecontext.New(),
		path: path,
		log: logger.GetLogger("cueExecutor").With().
			Str("directory", path).
			Logger(),
		instances: make(map[string]*cue.Value),
		metadata:  make(map[string]*metadata),
		fields:    make(map[string][]string),
	}
	config := &load.Config{
		//Stdin:      strings.NewReader(""),
		Dir:        path,
		ModuleRoot: path,
		//Package:    "test",
		//Overlay: map[string]load.Source{
		//	"/home/user/GolandProjects/cue-test/crossform.cue": load.FromString(val),
		//},
		Tags: []string{},
	}
	files, err := filepath.Glob(e.path + "/*.cue")
	if err != nil {
		return nil, err
	}
	if len(files) == 0 {
		return nil, nil
	}
	for i, v := range files {
		files[i] = strings.TrimPrefix(v, e.path+"/")
	}
	builds := load.Instances(files, config)
	if len(builds) < 1 {
		return nil, errors.New("cannot load instances")
	} else if err := builds[0].Err; err != nil {
		e.log.Error().Err(err).Msg("cannot load instances")
		return nil, err
	}

	l, err := os.ReadFile("lib.cue")
	if err != nil {
		return nil, err
	}
	imports := `
_observed:%s
_requested:%s
_xr:%s
_context:%s
` + string(l)
	lib := fmt.Sprintf(imports, observed, requested, xr, context)
	//lib := fmt.Sprintf(imports, "{}", "{}", "{}", "{}")
	if builds[0].PkgName != "" {
		lib = fmt.Sprintf("package %s\n%s", builds[0].PkgName, lib)
	}
	libValue := e.ctx.CompileString(lib)
	if err := libValue.Err(); err != nil {
		return nil, err
	}

	for i := range files {
		instance := e.ctx.BuildInstance(builds[i], cue.Scope(libValue))
		if err := instance.Err(); err != nil {
			msg := cueErrors.Details(instance.Err(), nil)
			return nil, errors.WithMessage(err, msg)
		}
		e.instances[files[i]] = &instance
	}

	for _, f := range files {
		fields, err := e.getFields(f)
		if err != nil {
			return nil, err
		}
		if _, exist := e.fields[f]; !exist {
			e.fields[f] = make([]string, 0)
		}
		for _, field := range fields {
			e.fields[f] = append(e.fields[f], field)
		}
	}

	for file, fields := range e.fields {
		for _, field := range fields {
			m, err := e.getMetadataObject(file, field)
			if err != nil {
				return nil, err
			}
			e.metadata[e.getFieldPath(file, field)] = m
		}
	}

	return e, nil
}

func (e *cueExecutor) getFieldPath(fileName, field string) string {
	return fmt.Sprintf("%s/%s", fileName, field)
}

func (e *cueExecutor) GetFileNames() []string {
	return maps.Keys(e.fields)
}

func (e *cueExecutor) GetFields(fileName string) []string {
	return e.fields[fileName]
}

func (e *cueExecutor) getFields(fileName string) ([]string, error) {
	fields := make([]string, 0)
	var defaultOptions = []cue.Option{
		cue.Attributes(true),
		cue.Concrete(false),
		cue.Definitions(false),
		cue.DisallowCycles(false),
		cue.Docs(false),
		cue.Hidden(false),
		cue.Optional(false),
		// The following are not set
		// nor do they have a bool arg
		// cue.Final(),
		// cue.Raw(),
		// cue.Schema(),
	}
	iter, err := e.instances[fileName].Fields(defaultOptions...)
	if err != nil {
		e.log.Error().Err(err).Str("fileName", fileName).Msg("unable to get get fields")
		return nil, errors.Wrapf(err, "unable to get get fields. file=%s", fileName)
	}
	for iter.Next() {
		fields = append(fields, iter.Selector().String())
	}
	return fields, nil
}

func (e *cueExecutor) getCrossformValue(val cue.Value) (*cue.Value, error) {
	var options = []cue.Option{
		cue.Attributes(false),
		cue.Concrete(false),
		cue.Definitions(false),
		cue.DisallowCycles(false),
		cue.Docs(false),
		cue.Hidden(true),
		cue.Optional(false),
		// The following are not set
		// nor do they have a bool arg
		// cue.Final(),
		// cue.Raw(),
		// cue.Schema(),
	}
	iter, err := val.Fields(options...)
	if err != nil {
		return nil, err
	}
	for iter.Next() {
		if iter.Selector().String() == "_crossform" {
			v := iter.Value()
			return &v, nil
		}
	}
	return nil, errors.New("unable to find _crossform field")
}

func (e *cueExecutor) getMetadataObject(fileName, field string) (*metadata, error) {
	tt := e.instances[fileName].LookupPath(cue.ParsePath(field))
	cf, err := e.getCrossformValue(tt)
	if err != nil {
		e.log.Warn().Err(err).Str("field", field).Msg("unable to get crossform value")
		return nil, errors.Wrapf(err, "unable to get crossform value. file=%s field=%s", fileName, field)
	}
	meta := cf.LookupPath(cue.ParsePath("metadata"))
	if err != nil {
		e.log.Error().Err(err).Str("field", field).Msg("unable to get crossform metadata")
		return nil, errors.Wrapf(err, "unable to get crossform metadata. file=%s field=%s", fileName, field)
	}
	j, err := meta.MarshalJSON()
	if err != nil {
		e.log.Error().Err(err).Str("field", field).Msg("unable to get crossform metadata")
		return nil, errors.Wrapf(err, "unable to get crossform metadata. file=%s field=%s", fileName, field)
	}
	m := metadata{}
	err = json.Unmarshal(j, &m)
	if err != nil {
		e.log.Error().Err(err).Str("field", field).Str("json", string(j)).Msg("unable to unmarshal crossform metadata")
		return nil, errors.Wrapf(err, "unable to unmarshal crossform metadata. file=%s field=%s", fileName, field)
	}
	return &m, nil
}

func (e *cueExecutor) GetMetadataObject(fileName, field string) *metadata {
	return e.metadata[e.getFieldPath(fileName, field)]
}

func (e *cueExecutor) GetCrossformObject(fileName, field string) (*crossform, error) {
	tt := e.instances[fileName].LookupPath(cue.ParsePath(field))
	v, err := e.getCrossformValue(tt)
	if err != nil {
		e.log.Warn().Err(err).Str("field", field).Msg("unable to get crossform value")
		return nil, errors.Wrapf(err, "unable to get crossform value. file=%s field=%s", fileName, field)
	}
	j, err := v.MarshalJSON()
	if err != nil {
		e.log.Warn().Err(err).Str("field", field).Msg("unable to get crossform object")
		return nil, errors.Wrapf(err, "unable to unmarshal crossform object. file=%s field=%s", fileName, field)
	}
	cf := crossform{}
	err = json.Unmarshal(j, &cf)
	if err != nil {
		e.log.Error().Err(err).Str("field", field).Msg("unable to unmarshal crossform object")
		return nil, errors.Wrapf(err, "unable to unmarshal crossform object. file=%s field=%s", fileName, field)
	}
	return &cf, nil
}

func (e *cueExecutor) ValidateInputs(_ map[string]*crossform, _ map[string]interface{}) error {
	return nil
}

func (e *cueExecutor) GetResource(file, field string) (map[string]interface{}, bool, resource.Ready, error) {
	crossform, err := e.GetCrossformObject(file, field)
	if err != nil {
		return nil, false, resource.ReadyUnspecified, err
	}
	if crossform.Deferred {
		return nil, true, resource.ReadyUnspecified, nil
	}

	v := e.instances[file].LookupPath(cue.ParsePath(field))
	j, err := v.MarshalJSON()
	if err != nil {
		e.log.Warn().Err(err).Str("field", field).Msg("unable to get crossform object")
		return nil, false, resource.ReadyUnspecified, errors.Wrapf(err, "unable to unmarshal crossform object. file=%s field=%s", file, field)
	}

	var obj map[string]interface{}
	err = json.Unmarshal(j, &obj)
	if err != nil {
		e.log.Error().Err(err).Str("id", crossform.Metadata.Id).Str("json", string(j)).Msg("unable to unmarshal resource")
		return nil, false, resource.ReadyUnspecified, err
	}

	ready := resource.ReadyUnspecified
	if crossform.Ready.Valid {
		if crossform.Ready.Bool {
			ready = resource.ReadyTrue
		} else {
			ready = resource.ReadyFalse
		}
	}

	e.log.Debug().Str("id", crossform.Metadata.Id).Str("json", string(j)).Msg("resource evaluating success")

	return obj, false, ready, nil
}
