package executor

func Execute(path string, cmd *ExecCommand) (*ExecResult, error) {
	e, err := NewExecutor(cmd, path)
	if err != nil {
		return nil, err
	}
	result, err := e.Exec()
	//if err == nil && len(cmd.Requested) == len(result.Request) {
	//	_ = e.writeTestData(result, err)
	//}
	return result, err
}
