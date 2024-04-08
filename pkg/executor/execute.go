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
	Desired map[resource.Name]*resource.DesiredComposed
	Request map[string]*fnv1beta1.ResourceSelector
	Errors  map[string]error
	Report  string
}
