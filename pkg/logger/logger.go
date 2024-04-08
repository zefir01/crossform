package logger

import (
	"github.com/rs/zerolog"
	"github.com/rs/zerolog/pkgerrors"
	"os"
	"time"
)

var Logger zerolog.Logger

func InitLog() {
	zerolog.ErrorStackMarshaler = pkgerrors.MarshalStack
	Logger = zerolog.New(zerolog.ConsoleWriter{Out: os.Stdout, TimeFormat: time.RFC3339}).
		With().Stack().Caller().Timestamp().Logger()
	zerolog.SetGlobalLevel(zerolog.InfoLevel)
}

func GetLogger(system string) zerolog.Logger {
	return Logger.With().Str("system", system).Logger()
}
