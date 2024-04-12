package executor

import "github.com/guregu/null/v5"

type metadata struct {
	Id   string `json:"id"`
	Type string `json:"type"`
}

type request struct {
	ApiVersion string            `json:"apiVersion"`
	Kind       string            `json:"kind"`
	Name       string            `json:"name,omitempty"`
	Labels     map[string]string `json:"labels,omitempty"`
}

type crossform struct {
	Metadata metadata               `json:"metadata"`
	Ready    null.Bool              `json:"ready,omitempty"`
	Request  *request               `json:"request,omitempty"`
	Output   interface{}            `json:"output,omitempty"`
	Schema   map[string]interface{} `json:"schema,omitempty"`
	Deferred bool                   `json:"deferred,omitempty"`
}
