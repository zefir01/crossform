package crossplane

import (
	"context"
	"crossform.io/pkg/RepoManager"
	"crossform.io/pkg/executor"
	"crossform.io/pkg/logger"
	"github.com/crossplane/crossplane-runtime/pkg/errors"
	"github.com/crossplane/function-sdk-go"
	fnv1beta1 "github.com/crossplane/function-sdk-go/proto/v1beta1"
	"github.com/crossplane/function-sdk-go/request"
	"github.com/crossplane/function-sdk-go/resource"
	"github.com/crossplane/function-sdk-go/response"
	"github.com/fatih/structs"
	"github.com/rs/zerolog"
	"google.golang.org/protobuf/encoding/protojson"
	"sigs.k8s.io/yaml"
	"strings"
)

type Function struct {
	fnv1beta1.UnimplementedFunctionRunnerServiceServer
	log         zerolog.Logger
	repoManager *RepoManager.RepoManager
}

func NewFunction(repoManager *RepoManager.RepoManager) *Function {
	return &Function{
		log:         logger.GetLogger("crossplane").With().Logger(),
		repoManager: repoManager,
	}
}

func (f *Function) Run() error {
	endpoint := ":8083"
	protocol := "tcp"
	f.log.Info().Str("protocol", protocol).Str("endpoint", endpoint).Msg("Listening crossplane function")
	return function.Serve(f,
		function.Listen(protocol, endpoint),
		function.Insecure(true))
}

func (f *Function) RunFunction(_ context.Context, req *fnv1beta1.RunFunctionRequest) (*fnv1beta1.RunFunctionResponse, error) {
	jsonString := protojson.Format(req)
	y, _ := yaml.JSONToYAML([]byte(jsonString))
	f.log.Debug().Str("request", string(y)).Msg("Received crossplane grpc request")

	rsp := response.To(req, response.DefaultTTL)

	desired, err := request.GetDesiredComposedResources(req)
	if err != nil {
		f.log.Error().Err(err).Msg("cannot get desired resources")
		response.Fatal(rsp, errors.Wrapf(err, "cannot get desired resources from %T", req))
		return rsp, nil
	}

	ctxJson, err := req.GetContext().MarshalJSON()
	if err != nil {
		f.log.Error().Err(err).Msg("cannot marshal json context")
		response.Fatal(rsp, errors.Wrapf(err, "cannot marshal json context %T", req))
		return rsp, nil
	}

	xr, err := request.GetObservedCompositeResource(req)
	if err != nil {
		f.log.Error().Err(err).Msg("cannot get observed composite resource")
		response.Fatal(rsp, errors.Wrapf(err, "cannot get observed composite resource from %T", req))
		return rsp, nil
	}

	requested, err := request.GetExtraResources(req)
	if err != nil {
		f.log.Error().Err(err).Msg("cannot get requested extra resources")
		response.Fatal(rsp, errors.Wrapf(err, "cannot get requested extra resources in %T", rsp))
		return rsp, nil
	}

	observed, err := request.GetObservedComposedResources(req)
	if err != nil {
		f.log.Error().Err(err).Msg("cannot get observed resource")
		response.Fatal(rsp, errors.Wrapf(err, "cannot get input resource in %T", rsp))
		return rsp, nil
	}

	spec := xr.Resource.Object["spec"].(map[string]interface{})
	result, err := f.repoManager.Execute(&executor.ExecCommand{
		RepositoryUrl:      spec["repository"].(string),
		RepositoryRevision: spec["revision"].(string),
		Path:               spec["path"].(string),
		ModuleName:         xr.Resource.GetName(),
		Observed:           observed,
		Requested:          requested,
		XR:                 xr,
		Context:            string(ctxJson),
	})
	if err != nil {
		f.log.Error().Err(err).Msg("execution error")
		response.Fatal(rsp, errors.Wrapf(err, "execution error in %T", rsp))
		return rsp, nil
	}
	for k := range result.Desired {
		_, exist := desired[k]
		if exist {
			f.log.Error().Str("id", string(k)).Msg("duplicated ID found. check function input.name")
			response.Fatal(rsp, errors.Wrapf(err, "duplicated ID=%s found. check function input.name", k))
			return rsp, nil
		}
	}

	for _, v := range result.Desired {
		metadata, ok := v.Resource.Object["metadata"]
		if !ok {
			continue
		}
		metadataTyped, ok := metadata.(map[string]interface{})
		if !ok {
			continue
		}
		delete(metadataTyped, "managedFields")
		delete(metadataTyped, "creationTimestamp")
		delete(metadataTyped, "generation")
		delete(metadataTyped, "ownerReferences")
		delete(metadataTyped, "resourceVersion")
		delete(metadataTyped, "uid")

		finalizersTyped, ok := metadataTyped["finalizers"].(map[string]interface{})
		if ok {
			delete(finalizersTyped, "finalizer.managedresource.crossplane.io")
		}

		labelsTyped, ok := metadataTyped["labels"].(map[string]interface{})
		if ok {
			for k := range labelsTyped {
				if strings.HasPrefix(k, "crossplane.io/") {
					delete(labelsTyped, k)
				}
			}
		}

		annotationsTyped, ok := metadataTyped["annotations"].(map[string]interface{})
		if ok {
			for k := range annotationsTyped {
				if strings.HasPrefix(k, "crossplane.io/") {
					delete(annotationsTyped, k)
				}
			}
		}

		delete(v.Resource.Object, "status")
	}

	for k, v := range result.Desired {
		apiVersion, ok := v.Resource.Object["apiVersion"]
		if !ok {
			continue
		}
		kind, ok := v.Resource.Object["kind"]
		if !ok {
			continue
		}
		metadata, ok := v.Resource.Object["metadata"]
		if !ok {
			continue
		}
		metadataTyped, ok := metadata.(map[string]interface{})
		if !ok {
			continue
		}
		name, ok := metadataTyped["name"]
		if !ok {
			continue
		}
		if apiVersion != xr.Resource.Object["apiVersion"] {
			continue
		}
		if kind != xr.Resource.Object["kind"] {
			continue
		}
		metadata, _ = xr.Resource.Object["metadata"]
		metadataTyped, _ = metadata.(map[string]interface{})
		if name != metadataTyped["name"] {
			continue
		}
		delete(result.Desired, k)
		x := resource.Composite{}
		x.Resource.Object = v.Resource.Object
		xr = &x
	}
	delete(xr.Resource.Object, "metadata")
	delete(xr.Resource.Object, "spec")

	status, ok := xr.Resource.Object["status"].(map[string]interface{})
	if !ok {
		status = make(map[string]interface{})
		xr.Resource.Object["status"] = status
	}
	status["hasErrors"] = len(result.DesiredErrors) > 0 || len(result.OutputsErrors) > 0
	//status["report"] = "\n  " + strings.Replace(result.Report, "\n", "  \n", -1)
	report := newReport(result)
	status["report"] = structs.Map(report)

	repo, err := f.repoManager.GetRepo(spec["repository"].(string), spec["revision"].(string))
	if err == nil {
		repository, ok := status["repository"]
		if !ok {
			repository = make(map[string]interface{})
			status["repository"] = repository
		}
		rr := repository.(map[string]interface{})
		rr["message"] = repo.Status.Message
		rr["commitSha"] = repo.Status.CommitSha
		rr["ok"] = repo.Status.IsInitialized && repo.Status.IsUpdateSuccess
	}
	status["outputs"] = result.Outputs

	err = response.SetDesiredCompositeResource(rsp, xr)
	if err != nil {
		f.log.Error().Err(err).Msg("cannot set desired XR")
		response.Fatal(rsp, errors.Wrapf(err, "cannot set desired XR %T", rsp))
		return rsp, nil
	}

	if len(result.Request) > 0 {
		rsp.Requirements = &fnv1beta1.Requirements{
			ExtraResources: result.Request,
		}
	}

	if err := response.SetDesiredComposedResources(rsp, result.Desired); err != nil {
		f.log.Error().Err(err).Msg("cannot set desired composed resources")
		response.Fatal(rsp, errors.Wrapf(err, "cannot set desired composed resources in %T", rsp))
		return rsp, nil
	}

	response.Normalf(rsp, report.String())

	return rsp, nil
}
