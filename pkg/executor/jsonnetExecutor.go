package executor

import (
	"crossform.io/pkg/logger"
	"encoding/json"
	"fmt"
	"github.com/crossplane/crossplane-runtime/pkg/errors"
	fnv1beta1 "github.com/crossplane/function-sdk-go/proto/v1beta1"
	"github.com/crossplane/function-sdk-go/resource"
	"github.com/crossplane/function-sdk-go/resource/composed"
	"github.com/google/go-jsonnet"
	"github.com/rs/zerolog"
	"os"
	"strings"
)

type JsonnetExecutor struct {
	log  zerolog.Logger
	cmd  *ExecCommand
	path string
}

func NewJsonnetExecutor(cmd *ExecCommand, path string) *JsonnetExecutor {
	return &JsonnetExecutor{
		log: logger.GetLogger("jsonnetExecutor").With().
			Str("url", cmd.RepositoryUrl).
			Str("revision", cmd.RepositoryRevision).
			Str("directory", cmd.Path).
			Logger(),
		cmd:  cmd,
		path: path,
	}
}

func (e *JsonnetExecutor) marshal() (string, string, string, string, error) {
	temp := make(map[string]interface{})
	for k, v := range e.cmd.Observed {
		temp[strings.TrimPrefix(string(k), e.cmd.ModuleName+".")] = v.Resource.Object
	}
	j, err := json.Marshal(temp)
	if err != nil {
		return "", "", "", "", errors.Wrap(err, "Unable marshal observed resource list")
	}
	observedJson := string(j)

	temp = make(map[string]interface{})
	for k, v := range e.cmd.Requested {
		for _, vv := range v {
			temp[strings.TrimPrefix(k, e.cmd.ModuleName+".")] = vv.Resource.Object
		}
	}
	j, err = json.Marshal(temp)
	if err != nil {
		return "", "", "", "", errors.Wrap(err, "Unable marshal requested resource list")
	}
	requestedJson := string(j)

	xrJson, err := json.Marshal(e.cmd.XR.Resource.Object)
	if err != nil {
		return "", "", "", "", errors.Wrap(err, "Unable marshal XR resource")
	}

	e.log.Debug().Msg("Marshal resources success")

	return observedJson, requestedJson, string(xrJson), e.cmd.Context, nil
}

func (e *JsonnetExecutor) makeRequestResult(
	requestResult map[string]*fnv1beta1.ResourceSelector,
	request map[string]*crossform,
) error {
	for k, v := range request {
		_, exist := requestResult[k]
		if exist {
			err := errors.Errorf("duplicated id=%s detected, execution fatal", k)
			e.log.Error().Err(err).Str("id", k).Msg("duplicated id detected, execution fatal")
			return err
		}
		requestResult[k] = &fnv1beta1.ResourceSelector{
			ApiVersion: v.Request.ApiVersion,
			Kind:       v.Request.Kind,
		}
		if v.Request.Labels == nil {
			requestResult[k].Match = &fnv1beta1.ResourceSelector_MatchName{
				MatchName: v.Request.Name,
			}
		} else {
			requestResult[k].Match = &fnv1beta1.ResourceSelector_MatchLabels{
				MatchLabels: &fnv1beta1.MatchLabels{
					Labels: v.Request.Labels,
				},
			}
		}
	}
	return nil
}

func (e *JsonnetExecutor) Exec() (*ExecResult, error) {
	e.log.Debug().Msg("start jsonnet execution")

	observed, requested, xr, context, err := e.marshal()
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
	e.log.Debug().Msg("jsonnet VM created")

	desiredResult := make(map[resource.Name]*resource.DesiredComposed)
	requestResult := make(map[string]*fnv1beta1.ResourceSelector)
	errorsResult := make(map[string]error)
	rep := "\n"

	files, err := os.ReadDir(e.path + "/" + e.cmd.Path)
	if err != nil {
		return nil, errors.Wrap(err, "Path not found")
	}
	for _, v := range files {
		if v.IsDir() || !v.Type().IsRegular() {
			continue
		}
		if !strings.HasSuffix(v.Name(), ".jsonnet") {
			continue
		}
		filename := e.path + "/" + e.cmd.Path + "/" + v.Name()

		_, request, errs, err := e.execFile(observed, requested, xr, context, vm, filename, false)
		if err != nil {
			return nil, errors.Wrap(err, "Jsonnet execution fatal error")
		}
		insufficientRequestedResources := false
		for k, _ := range request {
			_, ok := e.cmd.Requested[k]
			if !ok {
				insufficientRequestedResources = true
			}
		}
		if insufficientRequestedResources {
			for k, v := range e.cmd.Observed {
				desiredResult[k] = &resource.DesiredComposed{Resource: v.Resource}
			}
			err = e.makeRequestResult(requestResult, request)
			if err != nil {
				return nil, err
			}
			return &ExecResult{
				Desired: desiredResult,
				Errors:  errorsResult,
				Request: requestResult,
				Report:  "insufficient requested resources",
			}, nil
		}

		desired, request, errs, err := e.execFile(observed, requested, xr, context, vm, filename, true)
		if err != nil {
			return nil, errors.Wrap(err, "Jsonnet execution fatal error")
		}

		for k, v := range desired {
			j, err := v.Resource.MarshalJSON()
			if err != nil {
				e.log.Error().Str("id", k).Msg("Unable marshal desired resource")
				return nil, err
			}
			e.log.Debug().Str("id", k).Str("json", string(j)).Msg("desired resource OK")
			_, exist := desiredResult[resource.Name(k)]
			if exist {
				err = errors.Errorf("duplicated id=%s detected, execution fatal", k)
				e.log.Error().Err(err).Str("id", k).Msg("duplicated id detected, execution fatal")
				return nil, err
			}
			desiredResult[resource.Name(k)] = v
			rep = rep + "Resource " + k + " OK\n"
		}
		for k, v := range errs {
			errorsResult[k] = v
			rep = fmt.Sprintf("%sResource %s ERROR\n", rep, k)
			val, ok := e.cmd.Observed[resource.Name(k)]
			if !ok {
				e.log.Debug().Str("id", k).Err(v).Msg("desired resource previous state not found, skipping")
				continue
			}
			_, exist := desiredResult[resource.Name(k)]
			if exist {
				err = errors.Errorf("duplicated id=%s detected, execution fatal", k)
				e.log.Error().Err(err).Str("id", k).Msg("duplicated id detected, execution fatal")
				return nil, err
			}
			desiredResult[resource.Name(k)] = &resource.DesiredComposed{Resource: val.Resource}
		}

		err = e.makeRequestResult(requestResult, request)
		if err != nil {
			return nil, err
		}
	}
	return &ExecResult{
		Desired: desiredResult,
		Errors:  errorsResult,
		Request: requestResult,
		Report:  rep,
	}, nil
}

func (e *JsonnetExecutor) getResource(
	fileImport string,
	name string,
	crossform crossform,
	vm *jsonnet.VM,
	log zerolog.Logger,
) (*resource.DesiredComposed, error) {
	exec := fmt.Sprintf("%s m['%s']", fileImport, name)
	log.Debug().Str("id", crossform.Metadata.Id).Str("jsonnetCode", exec).Msg("evaluating resource")
	jsonStr, err := vm.EvaluateAnonymousSnippet("example1.jsonnet", exec)
	if err != nil {
		e.log.Warn().Err(err).Str("field", name).Str("id", crossform.Metadata.Id).Str("jsonnetCode", exec).Msg("error evaluating resource")
		return nil, err
	}

	var obj map[string]interface{}
	err = json.Unmarshal([]byte(jsonStr), &obj)
	if err != nil {
		log.Error().Err(err).Str("id", crossform.Metadata.Id).Str("json", jsonStr).Msg("unable to unmarshal resource")
		return nil, err
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

	var t composed.Unstructured
	t.Unstructured.Object = obj
	return &resource.DesiredComposed{Resource: &t, Ready: ready}, nil
}

func (e *JsonnetExecutor) getMetadata(
	fileImport string,
	name string,
	filename string,
	vm *jsonnet.VM,
	log zerolog.Logger,
) (*metadata, error) {
	var metadata metadata
	getMetadata := fmt.Sprintf("%s m['%s'].crossform.metadata", fileImport, name)
	jsonStr, err := vm.EvaluateAnonymousSnippet("example1.jsonnet", getMetadata)
	if err != nil {
		log.Error().Err(err).Str("field", name).Str("json", jsonStr).Msg("unable to get crossform metadata")
		return nil, errors.Wrapf(err, "unable to get crossform metadata. file=%s field=%s", filename, name)
	}
	err = json.Unmarshal([]byte(jsonStr), &metadata)
	if err != nil {
		log.Error().Err(err).Str("field", name).Str("json", jsonStr).Msg("unable to unmarshal crossform metadata")
		return nil, errors.Wrapf(err, "unable to unmarshal crossform metadata. file=%s field=%s", filename, name)
	}
	return &metadata, nil
}

func (e *JsonnetExecutor) execFile(
	observed,
	requested,
	xr string,
	context string,
	vm *jsonnet.VM,
	filename string,
	evaluate bool,
) (
	map[string]*resource.DesiredComposed,
	map[string]*crossform,
	map[string]error,
	error,
) {
	e.log.Debug().Str("observed", observed).
		Str("requested", requested).
		Str("xr", xr).
		Str("context", context).
		Str("file", filename).
		Msg("begin jsonnet execution")
	log := e.log.With().Str("file", filename).Logger()

	fileImport := fmt.Sprintf("local m = import '%s';", filename)

	e.log.Debug().Msg("getting output object fields")
	jsonStr, err := vm.EvaluateAnonymousSnippet("example1.jsonnet", fmt.Sprintf("%s std.objectFields(m)", fileImport))
	if err != nil {
		log.Error().Err(err).Msg("unable to get output object fields")
		return nil, nil, nil, err
	}
	names := make([]string, 0)
	err = json.Unmarshal([]byte(jsonStr), &names)
	if err != nil {
		log.Error().Err(err).Msg("unable to unmarshal output object fields")
		return nil, nil, nil, err
	}

	result := make(map[string]*resource.DesiredComposed)
	errs := make(map[string]error)
	request := make(map[string]*crossform)

	for _, name := range names {
		log := log.With().Str("file", filename).Str("field", name).Logger()

		metadata, err := e.getMetadata(fileImport, name, filename, vm, log)
		if err != nil {
			log.Error().Err(err).Str("field", name).Str("json", jsonStr).Msg("unable to get crossform metadata")
			return nil, nil, nil, err
		}

		var crossform crossform
		getCrossform := fmt.Sprintf("%s m['%s'].crossform", fileImport, name)
		jsonStr, err = vm.EvaluateAnonymousSnippet("example1.jsonnet", getCrossform)
		if err != nil {
			log.Warn().Err(err).Str("field", name).Str("json", jsonStr).Msg("unable to get crossform object")
			continue
		}
		err = json.Unmarshal([]byte(jsonStr), &crossform)
		if err != nil {
			switch metadata.Type {
			case "resource":
				if evaluate {
					errs[metadata.Id] = err
					log.Error().Err(err).Str("field", name).Str("json", jsonStr).Msg("unable to unmarshal crossform object")
				}
			case "request":
				log.Warn().Err(err).Str("field", name).Str("json", jsonStr).Msg("unable to unmarshal crossform object")
			}
			continue
		}

		switch metadata.Type {
		case "resource":
			if evaluate {
				res, err := e.getResource(fileImport, name, crossform, vm, log)
				if err == nil {
					result[crossform.Metadata.Id] = res
				} else {
					errs[crossform.Metadata.Id] = err
					log.Error().Str("id", crossform.Metadata.Id).Msg("unable to unmarshal resource")
					continue
				}
				log.Debug().Str("id", crossform.Metadata.Id).Msg("resource unmarshal success")
			}
		case "request":
			request[crossform.Metadata.Id] = &crossform
			log.Debug().Str("id", crossform.Metadata.Id).Msg("request unmarshal success")
		}
	}

	return result, request, errs, nil
}
