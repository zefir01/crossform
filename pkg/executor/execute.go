package executor

import (
	fnv1beta1 "github.com/crossplane/function-sdk-go/proto/v1beta1"
	"github.com/crossplane/function-sdk-go/resource"
)

type ExecCommand struct {
	RepositoryUrl      string
	RepositoryRevision string
	Path               string
	Observed           map[resource.Name]resource.ObservedComposed
	Requested          map[string][]resource.Extra
	ModuleName         string
	XR                 *resource.Composite
	Context            string
}

type ExecResult struct {
	Desired               map[resource.Name]*resource.DesiredComposed
	DesiredErrors         map[string]error
	Request               map[string]*fnv1beta1.ResourceSelector
	RequestErrors         map[string]error
	Outputs               map[string]interface{}
	OutputsErrors         map[string]error
	Inputs                map[string]string
	InputsErrors          map[string]error
	InputsValidationError error
}

func NewExecResult() *ExecResult {
	return &ExecResult{
		Desired:       make(map[resource.Name]*resource.DesiredComposed),
		DesiredErrors: make(map[string]error),
		Request:       make(map[string]*fnv1beta1.ResourceSelector),
		RequestErrors: make(map[string]error),
		Outputs:       make(map[string]interface{}),
		OutputsErrors: make(map[string]error),
		Inputs:        make(map[string]string),
		InputsErrors:  make(map[string]error),
	}
}
