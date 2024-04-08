package repo

import "github.com/rs/zerolog"

type Status struct {
	Name            string
	IsInitialized   bool
	Message         string
	IsUpdateSuccess bool
	CommitSha       string
	Revision        string
}

func NewStatus(name string) *Status {
	return &Status{
		Name:            name,
		IsInitialized:   false,
		Message:         "UnInitialized",
		IsUpdateSuccess: false,
		CommitSha:       "UnInitialized",
		Revision:        "UnInitialized",
	}
}

func (s Status) MarshalZerologObject(e *zerolog.Event) {
	e.Str("name", s.Name).
		Bool("IsInitialized", s.IsInitialized).
		Str("Message", s.Message).
		Bool("IsUpdateSuccess", s.IsUpdateSuccess).
		Str("CommitSha", s.CommitSha).
		Str("Revision", s.Revision)
}
