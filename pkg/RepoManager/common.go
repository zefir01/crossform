package RepoManager

import (
	"fmt"
	"os"
	"sigs.k8s.io/controller-runtime/pkg/log"
)

//var logger = zerolog.New(zerolog.ConsoleWriter{Out: os.Stdout}).
//	With().
//	Caller().
//	Logger()

// CheckIfError should be used to naively panics if an error is not nil.
func CheckIfError(err error) {
	if err == nil {
		return
	}
	log.Log.Error(err, fmt.Sprintf("error: %s", err))
	os.Exit(1)
}
