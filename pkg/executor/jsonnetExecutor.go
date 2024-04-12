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
	"github.com/santhosh-tekuri/jsonschema/v5"
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
		temp[string(k)] = v.Resource.Object
	}
	j, err := json.Marshal(temp)
	if err != nil {
		return "", "", "", "", errors.Wrap(err, "Unable marshal observed resource list")
	}
	observedJson := string(j)

	temp = make(map[string]interface{})
	for k, v := range e.cmd.Requested {
		for _, vv := range v {
			temp[k] = vv.Resource.Object
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

func (e *JsonnetExecutor) validate(inputs map[string]*crossform, input map[string]interface{}) error {
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

	result := NewExecResult()

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

		desired, desiredErrors, resourcesDeferred, request, requestsErrs, outputs, outputsErrs, inputs, inputsErrs, err :=
			e.execFile(observed, requested, xr, context, vm, filename, false)
		if err != nil {
			return nil, errors.Wrap(err, "Jsonnet execution fatal error")
		}

		xrSpec := e.cmd.XR.Resource.Object["spec"]
		xrInputs := xrSpec.(map[string]interface{})["inputs"]
		if err := e.validate(inputs, xrInputs.(map[string]interface{})); err != nil {
			e.log.Error().Err(err).Msg("Inputs schema validation error")
			result.InputsValidationError = err
		}

		for k, v := range inputsErrs {
			result.InputsErrors[k] = v
		}
		for k := range inputs {
			result.Inputs[k] = k
		}

		insufficientRequestedResources := false
		for k := range request {
			_, ok := e.cmd.Requested[k]
			if !ok {
				insufficientRequestedResources = true
			}
		}
		if insufficientRequestedResources {
			//for k, v := range e.cmd.Observed {
			//	result.Desired[k] = &resource.DesiredComposed{Resource: v.Resource}
			//}
			err := e.makeRequestResult(result.Request, request)
			if err != nil {
				return nil, err
			}
			return result, nil
		}

		desired, desiredErrors, resourcesDeferred, request, requestsErrs, outputs, outputsErrs, inputs, inputsErrs, err =
			e.execFile(observed, requested, xr, context, vm, filename, true)
		if err != nil {
			return nil, errors.Wrap(err, "Jsonnet execution fatal error")
		}
		result.Deferred = resourcesDeferred

		err = e.makeRequestResult(result.Request, request)
		if err != nil {
			return nil, err
		}
		for k, v := range requestsErrs {
			_, exist := result.RequestErrors[k]
			if exist {
				return nil, errors.Errorf("request duplicate id=%s detected", k)
			}
			result.RequestErrors[k] = v
		}

		for k, v := range desired {
			j, err := v.Resource.MarshalJSON()
			if err != nil {
				e.log.Error().Str("id", k).Msg("Unable marshal desired resource")
				return nil, err
			}
			e.log.Debug().Str("id", k).Str("json", string(j)).Msg("desired resource OK")
			_, exist := result.Desired[resource.Name(k)]
			if exist {
				err = errors.Errorf("duplicated id=%s detected, execution fatal", k)
				e.log.Error().Err(err).Str("id", k).Msg("duplicated id detected, execution fatal")
				return nil, err
			}
			result.Desired[resource.Name(k)] = v
		}

		for k, v := range desiredErrors {
			result.DesiredErrors[k] = v
			val, ok := e.cmd.Observed[resource.Name(k)]
			if !ok {
				e.log.Debug().Str("id", k).Err(v).Msg("desired resource previous state not found, skipping")
				continue
			}
			_, exist := result.Desired[resource.Name(k)]
			if exist {
				err = errors.Errorf("duplicated id=%s detected, execution fatal", k)
				e.log.Error().Err(err).Str("id", k).Msg("duplicated id detected, execution fatal")
				return nil, err
			}
			result.Desired[resource.Name(k)] = &resource.DesiredComposed{Resource: val.Resource}
		}

		for k, v := range outputs {
			_, exist := result.Outputs[k]
			if exist {
				return nil, errors.Errorf("output duplicate id=%s detected", k)
			}
			result.Outputs[k] = v
		}

		var hasStatus bool
		var hasOutputs bool
		var status interface{}
		var xrOutputs interface{}
		status, hasStatus = e.cmd.XR.Resource.Object["status"]
		if hasStatus {
			t := status.(map[string]interface{})
			xrOutputs, hasOutputs = t["outputs"]
		}
		if !hasStatus || !hasOutputs {
			for k, v := range outputsErrs {
				e.log.Debug().Str("id", k).Err(v).Msg("output previous state not found, skipping")
				result.OutputsErrors[k] = v
			}
			continue
		} else {
			t := xrOutputs.(map[string]interface{})
			for k, v := range outputsErrs {
				val, ok := t[k]
				if ok {
					e.log.Debug().Str("id", k).Err(v).Msg("output previous state found")
					result.Outputs[k] = val
				} else {
					e.log.Debug().Str("id", k).Err(v).Msg("output previous state not found, skipping")
					result.OutputsErrors[k] = v
				}
			}
		}
	}
	return result, nil
}

func (e *JsonnetExecutor) getCrossformObject(fileImport string,
	name string,
	vm *jsonnet.VM,
	log zerolog.Logger,
) (*crossform, error) {
	var crossform crossform
	getCrossform := fmt.Sprintf("%s m['%s'].crossform", fileImport, name)
	jsonStr, err := vm.EvaluateAnonymousSnippet("example1.jsonnet", getCrossform)
	if err != nil {
		log.Warn().Err(err).Str("field", name).Str("json", jsonStr).Msg("unable to get crossform object")
		return nil, err
	}
	err = json.Unmarshal([]byte(jsonStr), &crossform)
	if err != nil {
		log.Error().Err(err).Str("field", name).Str("json", jsonStr).Msg("unable to unmarshal crossform object")
		return nil, err
	}
	return &crossform, nil
}

func (e *JsonnetExecutor) getResource(
	fileImport string,
	name string,
	metadata *metadata,
	vm *jsonnet.VM,
	log zerolog.Logger,
) (*resource.DesiredComposed, bool, error) {
	crossform, err := e.getCrossformObject(fileImport, name, vm, log)
	if err != nil {
		return nil, false, err
	}
	if crossform.Deferred {
		return nil, crossform.Deferred, nil
	}

	exec := fmt.Sprintf("%s m['%s']", fileImport, name)
	log.Debug().Str("id", metadata.Id).Str("jsonnetCode", exec).Msg("evaluating resource")
	jsonStr, err := vm.EvaluateAnonymousSnippet("example1.jsonnet", exec)
	if err != nil {
		e.log.Warn().Err(err).Str("field", name).Str("id", metadata.Id).Str("jsonnetCode", exec).Msg("error evaluating resource")
		return nil, false, err
	}

	var obj map[string]interface{}
	err = json.Unmarshal([]byte(jsonStr), &obj)
	if err != nil {
		log.Error().Err(err).Str("id", metadata.Id).Str("json", jsonStr).Msg("unable to unmarshal resource")
		return nil, false, err
	}

	ready := resource.ReadyUnspecified
	if crossform.Ready.Valid {
		if crossform.Ready.Bool {
			ready = resource.ReadyTrue
		} else {
			ready = resource.ReadyFalse
		}
	}

	log.Debug().Str("id", metadata.Id).Str("json", jsonStr).Msg("resource evaluating success")

	var t composed.Unstructured
	t.Unstructured.Object = obj
	return &resource.DesiredComposed{Resource: &t, Ready: ready}, crossform.Deferred, nil
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
	map[string]error,
	[]string,
	map[string]*crossform,
	map[string]error,
	map[string]interface{},
	map[string]error,
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

	e.log.Debug().Msg("getting outputs object fields")
	jsonStr, err := vm.EvaluateAnonymousSnippet("example1.jsonnet", fmt.Sprintf("%s std.objectFields(m)", fileImport))
	if err != nil {
		log.Error().Err(err).Msg("unable to get main object fields")
		return nil, nil, nil, nil, nil, nil, nil, nil, nil, err
	}
	names := make([]string, 0)
	err = json.Unmarshal([]byte(jsonStr), &names)
	if err != nil {
		log.Error().Err(err).Msg("unable to unmarshal main object fields")
		return nil, nil, nil, nil, nil, nil, nil, nil, nil, err
	}

	resources := make(map[string]*resource.DesiredComposed)
	resourcesErrs := make(map[string]error)
	resourcesDeferred := make([]string, 0)
	requests := make(map[string]*crossform)
	requestsErrs := make(map[string]error)
	outputs := make(map[string]interface{})
	outputsErrs := make(map[string]error)
	inputs := make(map[string]*crossform)
	inputsErrs := make(map[string]error)

	for _, name := range names {
		log := log.With().Str("file", filename).Str("field", name).Logger()

		metadata, err := e.getMetadata(fileImport, name, filename, vm, log)
		if err != nil {
			log.Error().Err(err).Str("field", name).Str("json", jsonStr).Msg("unable to get crossform metadata")
			return nil, nil, nil, nil, nil, nil, nil, nil, nil, err
		}

		switch metadata.Type {
		case "resource":
			if evaluate {
				res, isDeferred, err := e.getResource(fileImport, name, metadata, vm, log)
				if err != nil {
					resourcesErrs[metadata.Id] = err
					continue
				}
				if isDeferred {
					resourcesDeferred = append(resourcesDeferred, metadata.Id)
				} else {
					resources[metadata.Id] = res
				}
				log.Debug().Str("id", metadata.Id).Msg("resource unmarshal success")
			}
		case "request":
			crossform, err := e.getCrossformObject(fileImport, name, vm, log)
			if err != nil {
				log.Warn().Err(err).Str("field", name).Str("json", jsonStr).Msg("unable to unmarshal crossform object")
				requestsErrs[metadata.Id] = err
				continue
			}
			requests[metadata.Id] = crossform
			log.Debug().Str("id", metadata.Id).Msg("request unmarshal success")
		case "output":
			if evaluate {
				crossform, err := e.getCrossformObject(fileImport, name, vm, log)
				if err != nil {
					outputsErrs[metadata.Id] = err
					continue
				}
				outputs[metadata.Id] = crossform.Output
				log.Debug().Str("id", metadata.Id).Msg("outputs unmarshal success")
			}
		case "input":
			crossform, err := e.getCrossformObject(fileImport, name, vm, log)
			if err != nil {
				log.Warn().Err(err).Str("field", name).Str("json", jsonStr).Msg("unable to unmarshal crossform object")
				inputsErrs[metadata.Id] = err
				continue
			}
			inputs[metadata.Id] = crossform
			log.Debug().Str("id", metadata.Id).Msg("input unmarshal success")
		}
	}
	return resources, resourcesErrs, resourcesDeferred, requests, requestsErrs, outputs, outputsErrs, inputs, inputsErrs, nil
}
