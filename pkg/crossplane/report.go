package crossplane

import (
	"crossform.io/pkg/executor"
	"encoding/json"
	"fmt"
	"strings"
)

type reportItem struct {
	typ      string
	id       string
	deferred bool
	Error    error
}

func newReportItem(typ, id string, err error, deferred bool) *reportItem {
	item := &reportItem{
		typ:      typ,
		id:       id,
		Error:    err,
		deferred: deferred,
	}
	return item
}

func (i *reportItem) String() string {
	return fmt.Sprintf("%s %s %s", i.typ, i.id, i.Status())
}
func (i *reportItem) Status() string {
	if i.Error != nil {
		return fmt.Sprintf("ERROR:\n%s", i.Error)
	}
	if i.deferred {
		return "DEFERRED"
	}
	return "OK"
}

type report struct {
	Resources        map[string]string `json:"resources,omitempty" structs:"resources,omitempty"`
	Requests         map[string]string `json:"requests,omitempty" structs:"requests,omitempty"`
	Outputs          map[string]string `json:"outputs,omitempty" structs:"outputs,omitempty"`
	Inputs           map[string]string `json:"inputs,omitempty" structs:"inputs,omitempty"`
	InputsValidation string            `json:"inputsValidation,omitempty" structs:"inputsValidation,omitempty"`
	items            []*reportItem
}

func (r *report) String() string {
	items := make([]string, 0)
	for _, v := range r.items {
		items = append(items, v.String())
	}
	inputsValidation := fmt.Sprintf("Inputs validation: %s\n", r.InputsValidation)
	return inputsValidation + strings.Join(items, "\n")
}

func (r *report) Map() (map[string]interface{}, error) {
	jsonData, _ := json.Marshal(r)
	v := map[string]interface{}{}
	err := json.Unmarshal(jsonData, &v)
	return v, err
}

func newReport(result *executor.ExecResult) *report {
	r := &report{
		Requests:         make(map[string]string),
		Resources:        make(map[string]string),
		Outputs:          make(map[string]string),
		Inputs:           make(map[string]string),
		InputsValidation: "OK",
		items:            make([]*reportItem, 0),
	}
	if result.InputsValidationError != nil {
		r.InputsValidation = result.InputsValidationError.Error()
	}
	for k := range result.Request {
		i := newReportItem("Request", k, nil, false)
		r.items = append(r.items, i)
		r.Requests[k] = i.Status()
	}
	for k, v := range result.RequestErrors {
		i := newReportItem("Request", k, v, false)
		r.items = append(r.items, i)
		r.Requests[k] = i.Status()
	}
	for _, k := range result.Deferred {
		i := newReportItem("Resource", k, nil, true)
		r.items = append(r.items, i)
		r.Resources[k] = i.Status()
	}
	for k := range result.Desired {
		i := newReportItem("Resource", string(k), nil, false)
		r.items = append(r.items, i)
		r.Resources[string(k)] = i.Status()
	}
	for k, v := range result.DesiredErrors {
		i := newReportItem("Resource", k, v, false)
		r.items = append(r.items, i)
		r.Resources[k] = i.Status()
	}
	for k := range result.Outputs {
		i := newReportItem("Output", k, nil, false)
		r.items = append(r.items, i)
		r.Outputs[k] = i.Status()
	}
	for k, v := range result.OutputsErrors {
		i := newReportItem("Output", k, v, false)
		r.items = append(r.items, i)
		r.Outputs[k] = i.Status()
	}
	for k := range result.Inputs {
		i := newReportItem("Input", k, nil, false)
		r.items = append(r.items, i)
		r.Inputs[k] = i.Status()
	}
	for k, v := range result.InputsErrors {
		i := newReportItem("Input", k, v, false)
		r.items = append(r.items, i)
		r.Inputs[k] = i.Status()
	}
	return r
}
