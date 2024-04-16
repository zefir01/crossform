package executor

func Execute(path string, cmd *ExecCommand) (*ExecResult, error) {
	e, err := NewExecutor(cmd, path)
	if err != nil {
		return nil, err
	}
	return e.Exec()
}
