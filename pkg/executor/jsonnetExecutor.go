package executor

import (
	"crossform.io/pkg/logger"
	"encoding/json"
	"fmt"
	"github.com/crossplane/crossplane-runtime/pkg/errors"
	"github.com/crossplane/function-sdk-go/resource"
	"github.com/google/go-jsonnet"
	"github.com/rs/zerolog"
	"github.com/rs/zerolog/log"
	"github.com/santhosh-tekuri/jsonschema/v5"
	"golang.org/x/exp/maps"
	"os"
	"path/filepath"
	"strings"
)

type jsonnetExecutor struct {
	log      zerolog.Logger
	path     string
	vm       *jsonnet.VM
	metadata map[string]*metadata
	fields   map[string][]string
}

func newJsonnetExecutor(path, observed, requested, xr, context string) (genericExecutor, error) {
	e := jsonnetExecutor{
		path: path,
		log: logger.GetLogger("JsonnetExecutor").With().
			Str("directory", path).
			Logger(),
		metadata: make(map[string]*metadata),
		fields:   make(map[string][]string),
	}
	files, err := filepath.Glob(e.path + "/*.jsonnet")
	if err != nil {
		return nil, err
	}
	if len(files) == 0 {
		return nil, nil
	}

	vm := jsonnet.MakeVM()
	vm.ExtCode("observed", observed)
	vm.ExtCode("requested", requested)
	vm.ExtCode("xr", xr)
	vm.ExtCode("context", context)
	lib, err := os.ReadFile("lib.jsonnet")
	if err != nil {
		return nil, err
	}
	vm.ExtCode("crossform", string(lib))
	e.vm = vm

	e.log.Debug().Msg("getting fields")
	for _, file := range files {
		fields, err := e.getFields(file)
		if err != nil {
			return nil, err
		}
		for _, field := range fields {
			if _, exist := e.fields[file]; !exist {
				e.fields[file] = make([]string, 0)
			}
			e.fields[file] = append(e.fields[file], field)
		}
	}

	for file, fields := range e.fields {
		for _, field := range fields {
			p := e.getFieldPath(file, field)
			m, err := e.getMetadata(file, field)
			if err != nil {
				return nil, err
			}
			e.metadata[p] = m
		}
	}

	return &e, nil
}

func (e *jsonnetExecutor) getFields(file string) ([]string, error) {
	fileImport := fmt.Sprintf("local m = import '%s';", file)
	jsonStr, err := e.vm.EvaluateAnonymousSnippet("example1.jsonnet", fmt.Sprintf("%s std.objectFields(m)", fileImport))
	if err != nil {
		log.Error().Err(err).Msg("unable to get main object fields")
		return nil, err
	}
	fields := make([]string, 0)
	err = json.Unmarshal([]byte(jsonStr), &fields)
	if err != nil {
		log.Error().Err(err).Msg("unable to unmarshal main object fields")
		return nil, err
	}
	return fields, nil
}

func (e *jsonnetExecutor) GetFileNames() []string {
	return maps.Keys(e.fields)
}
func (e *jsonnetExecutor) getFieldPath(fileName, field string) string {
	return fmt.Sprintf("%s/%s", fileName, field)
}
func (e *jsonnetExecutor) GetFields(fileName string) []string {
	return e.fields[fileName]
}

func (e *jsonnetExecutor) getMetadata(
	file string,
	field string,
) (*metadata, error) {
	fileImport := fmt.Sprintf("local m = import '%s';", file)
	var metadata metadata
	getMetadata := fmt.Sprintf("%s m['%s'].crossform.metadata", fileImport, field)
	jsonStr, err := e.vm.EvaluateAnonymousSnippet("example1.jsonnet", getMetadata)
	if err != nil {
		log.Error().Err(err).Str("field", field).Str("json", jsonStr).Msg("unable to get crossform metadata")
		return nil, errors.Wrapf(err, "unable to get crossform metadata. file=%s field=%s", file, field)
	}
	err = json.Unmarshal([]byte(jsonStr), &metadata)
	if err != nil {
		log.Error().Err(err).Str("field", field).Str("json", jsonStr).Msg("unable to unmarshal crossform metadata")
		return nil, errors.Wrapf(err, "unable to unmarshal crossform metadata. file=%s field=%s", file, field)
	}
	return &metadata, nil
}

func (e *jsonnetExecutor) GetMetadataObject(fileName, field string) *metadata {
	return e.metadata[e.getFieldPath(fileName, field)]
}

func (e *jsonnetExecutor) GetCrossformObject(file, field string) (*crossform, error) {
	var crossform crossform
	fileImport := fmt.Sprintf("local m = import '%s';", file)
	getCrossform := fmt.Sprintf("%s m['%s'].crossform", fileImport, field)
	jsonStr, err := e.vm.EvaluateAnonymousSnippet("example1.jsonnet", getCrossform)
	if err != nil {
		log.Warn().Err(err).Str("field", field).Str("json", jsonStr).Msg("unable to get crossform object")
		return nil, err
	}
	err = json.Unmarshal([]byte(jsonStr), &crossform)
	if err != nil {
		log.Error().Err(err).Str("field", field).Str("json", jsonStr).Msg("unable to unmarshal crossform object")
		return nil, err
	}
	return &crossform, nil
}

func (e *jsonnetExecutor) ValidateInputs(inputs map[string]*crossform, input map[string]interface{}) error {
	schema := make(map[string]interface{})
	schema["type"] = "object"
	schema["required"] = make([]string, 0)
	schema["properties"] = make(map[string]interface{})
	properties := schema["properties"].(map[string]interface{})

	for k, v := range inputs {
		if v.Schema == nil {
			continue
		}
		properties[k] = v.Schema
		if _, exist := v.Schema["default"]; !exist {
			schema["required"] = append(schema["required"].([]string), k)
		}
	}
	compiler := jsonschema.NewCompiler()
	j, err := json.Marshal(schema)
	if err != nil {
		return err
	}

	e.log.Warn().Str("schema", string(j)).Msg("Module schema")

	if err := compiler.AddResource("https://crossform.io/inputs", strings.NewReader(string(j))); err != nil {
		return err
	}
	sch, err := compiler.Compile("https://crossform.io/inputs")
	if err != nil {
		return err
	}
	if err = sch.Validate(input); err != nil {
		return err
	}
	return nil
}

func (e *jsonnetExecutor) GetResource(file, field string) (map[string]interface{}, bool, resource.Ready, error) {
	crossform, err := e.GetCrossformObject(file, field)
	if err != nil {
		return nil, false, resource.ReadyUnspecified, err
	}
	if crossform.Deferred {
		return nil, true, resource.ReadyUnspecified, nil
	}

	fileImport := fmt.Sprintf("local m = import '%s';", file)
	exec := fmt.Sprintf("%s m['%s']", fileImport, field)
	log.Debug().Str("id", crossform.Metadata.Id).Str("jsonnetCode", exec).Msg("evaluating resource")
	jsonStr, err := e.vm.EvaluateAnonymousSnippet("example1.jsonnet", exec)
	if err != nil {
		e.log.Warn().Err(err).Str("field", field).Str("id", crossform.Metadata.Id).Str("jsonnetCode", exec).Msg("error evaluating resource")
		return nil, false, resource.ReadyUnspecified, err
	}

	var obj map[string]interface{}
	err = json.Unmarshal([]byte(jsonStr), &obj)
	if err != nil {
		log.Error().Err(err).Str("id", crossform.Metadata.Id).Str("json", jsonStr).Msg("unable to unmarshal resource")
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

	log.Debug().Str("id", crossform.Metadata.Id).Str("json", jsonStr).Msg("resource evaluating success")

	return obj, false, ready, nil
}
