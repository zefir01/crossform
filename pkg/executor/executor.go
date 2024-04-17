package executor

import (
	"crossform.io/pkg/logger"
	"encoding/json"
	"github.com/crossplane/crossplane-runtime/pkg/errors"
	fnv1beta1 "github.com/crossplane/function-sdk-go/proto/v1beta1"
	"github.com/crossplane/function-sdk-go/resource"
	"github.com/crossplane/function-sdk-go/resource/composed"
	"github.com/rs/zerolog"
	"os"
)

type genericExecutor interface {
	GetFileNames() []string
	GetFields(fileName string) []string
	GetMetadataObject(fileName, field string) *metadata
	GetCrossformObject(fileName, field string) (*crossform, error)
	ValidateInputs(inputs map[string]*crossform, input map[string]interface{}) error
	GetResource(fileName, field string) (map[string]interface{}, bool, resource.Ready, error)
}

type Executor struct {
	log      zerolog.Logger
	cmd      *ExecCommand
	path     string
	executor genericExecutor
}

func NewExecutor(cmd *ExecCommand, path string) (*Executor, error) {
	e := &Executor{
		log: logger.GetLogger("jsonnetExecutor").With().
			Str("url", cmd.RepositoryUrl).
			Str("revision", cmd.RepositoryRevision).
			Str("directory", cmd.Path).
			Logger(),
		cmd:  cmd,
		path: path,
	}

	if _, err := os.Stat(path + "/" + cmd.Path); os.IsNotExist(err) {
		return nil, err
	}

	observed, requested, xr, context, err := e.marshal()

	var ex genericExecutor = nil
	ex, err = newJsonnetExecutor(path+"/"+cmd.Path, observed, requested, xr, context)
	if err != nil {
		return nil, err
	}
	if ex == nil {
		ex, err = newCueExecutor(path+"/"+cmd.Path, observed, requested, xr, context)
		if err != nil {
			return nil, err
		}
		if ex == nil {
			return nil, errors.New("project type not supported")
		}
	}
	e.executor = ex
	return e, nil
}

func (e *Executor) marshal() (string, string, string, string, error) {
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

func (e *Executor) makeRequestResult(
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

func (e *Executor) Exec() (*ExecResult, error) {
	e.log.Debug().Msg("start execution")

	result := NewExecResult()

	for _, file := range e.executor.GetFileNames() {

		desired, desiredErrors, resourcesDeferred, request, requestsErrs, outputs, outputsErrs, inputs, inputsErrs, err :=
			e.execFile(file, false)
		if err != nil {
			return nil, errors.Wrap(err, "Jsonnet execution fatal error")
		}

		xrSpec := e.cmd.XR.Resource.Object["spec"]
		xrInputs := xrSpec.(map[string]interface{})["inputs"]
		if err := e.executor.ValidateInputs(inputs, xrInputs.(map[string]interface{})); err != nil {
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
			err := e.makeRequestResult(result.Request, request)
			if err != nil {
				return nil, err
			}
			return result, nil
		}

		desired, desiredErrors, resourcesDeferred, request, requestsErrs, outputs, outputsErrs, inputs, inputsErrs, err =
			e.execFile(file, true)
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

func (e *Executor) execFile(
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
	e.log.Debug().
		Str("file", filename).
		Msg("begin jsonnet execution")
	log := e.log.With().Str("file", filename).Logger()

	names := e.executor.GetFields(filename)

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

		metadata := e.executor.GetMetadataObject(filename, name)

		switch metadata.Type {
		case "resource":
			if evaluate {
				res, isDeferred, ready, err := e.executor.GetResource(filename, name)
				if err != nil {
					resourcesErrs[metadata.Id] = err
					continue
				}
				if isDeferred {
					resourcesDeferred = append(resourcesDeferred, metadata.Id)
				} else {
					var t composed.Unstructured
					t.Unstructured.Object = res
					resources[metadata.Id] = &resource.DesiredComposed{Resource: &t, Ready: ready}
				}
				log.Debug().Str("id", metadata.Id).Msg("resource unmarshal success")
			}
		case "request":
			crossform, err := e.executor.GetCrossformObject(filename, name)
			if err != nil {
				requestsErrs[metadata.Id] = err
				continue
			}
			requests[metadata.Id] = crossform
			log.Debug().Str("id", metadata.Id).Msg("request unmarshal success")
		case "output":
			if evaluate {
				crossform, err := e.executor.GetCrossformObject(filename, name)
				if err != nil {
					outputsErrs[metadata.Id] = err
					continue
				}
				outputs[metadata.Id] = crossform.Output
				log.Debug().Str("id", metadata.Id).Msg("outputs unmarshal success")
			}
		case "input":
			crossform, err := e.executor.GetCrossformObject(filename, name)
			if err != nil {
				inputsErrs[metadata.Id] = err
				continue
			}
			inputs[metadata.Id] = crossform
			log.Debug().Str("id", metadata.Id).Msg("input unmarshal success")
		}
	}
	return resources, resourcesErrs, resourcesDeferred, requests, requestsErrs, outputs, outputsErrs, inputs, inputsErrs, nil
}
