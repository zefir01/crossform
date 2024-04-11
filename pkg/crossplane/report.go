package crossplane

import (
	"crossform.io/pkg/executor"
	"fmt"
	"strings"
)

type reportItem struct {
	Ok    bool   `json:"ok" structs:"ok"`
	Error string `json:"error,omitempty"  structs:"error,omitempty"`
}

func (i *reportItem) String(typ string, id string) string {
	if i.Ok {
		return fmt.Sprintf("%s %s OK", typ, id)
	}
	return fmt.Sprintf("%s %s ERROR:\n%s", typ, id, i.Error)
}

type report struct {
	Resources map[string]reportItem `json:"resources,omitempty" structs:"resources,omitempty"`
	Requests  map[string]reportItem `json:"requests,omitempty" structs:"requests,omitempty"`
	Outputs   map[string]reportItem `json:"outputs,omitempty" structs:"outputs,omitempty"`
}

func (r *report) String() string {
	items := make([]string, 0)
	for k, v := range r.Requests {
		items = append(items, v.String("Request", k))
	}
	for k, v := range r.Resources {
		items = append(items, v.String("Resource", k))
	}
	for k, v := range r.Outputs {
		items = append(items, v.String("Output", k))
	}
	return strings.Join(items, "\n")
}

func newReport(result *executor.ExecResult) *report {
	r := &report{
		Requests:  make(map[string]reportItem),
		Resources: make(map[string]reportItem),
		Outputs:   make(map[string]reportItem),
	}
	for k := range result.Request {
		item := reportItem{
			Ok: true,
		}
		r.Requests[k] = item
	}
	for k, v := range result.RequestErrors {
		item := reportItem{
			Ok:    false,
			Error: v.Error(),
		}
		r.Requests[k] = item
	}
	for k := range result.Desired {
		item := reportItem{
			Ok: true,
		}
		r.Resources[string(k)] = item
	}
	for k, v := range result.DesiredErrors {
		item := reportItem{
			Ok:    false,
			Error: v.Error(),
		}
		r.Resources[k] = item
	}
	for k := range result.Outputs {
		item := reportItem{
			Ok: true,
		}
		r.Outputs[k] = item
	}
	for k, v := range result.OutputsErrors {
		item := reportItem{
			Ok:    false,
			Error: v.Error(),
		}
		r.Outputs[k] = item
	}
	return r
}
