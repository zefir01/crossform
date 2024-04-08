package executor

func Execute(path string, cmd *ExecCommand) (*ExecResult, error) {
	e := NewJsonnetExecutor(cmd, path)
	return e.Exec()
}
