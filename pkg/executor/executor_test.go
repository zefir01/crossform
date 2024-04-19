package executor

import (
	"crossform.io/pkg/logger"
	"errors"
	"fmt"
	"github.com/kylelemons/godebug/diff"
	"gopkg.in/yaml.v3"
	"os"
	"testing"
)

type testCase struct {
	path   string
	cmd    *ExecCommand
	err    string
	result string
	name   string
}

func TestExecutor(t *testing.T) {
	logger.InitLog()
	var cases []*testCase

	entries, err := os.ReadDir("testdata")
	if err != nil {
		t.Error(err)
		return
	}
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		entries2, err := os.ReadDir("testdata/" + e.Name())
		if err != nil {
			t.Error(err)
			return
		}
		for _, e2 := range entries2 {
			if !e.IsDir() {
				continue
			}
			testPath := fmt.Sprintf("testdata/%s/%s", e.Name(), e2.Name())
			cmdYaml, err := os.ReadFile(testPath + "/command.yaml")
			if err != nil {
				t.Error(err)
				return
			}
			var cmd ExecCommand
			err = yaml.Unmarshal(cmdYaml, &cmd)
			if err != nil {
				t.Error(err)
				return
			}
			cmd.Path = "src"

			if _, err := os.Stat(testPath + "/result.yaml"); errors.Is(err, os.ErrNotExist) {
				em, err := os.ReadFile(testPath + "/error.yaml")
				if err != nil {
					t.Error(err)
					return
				}
				tc := testCase{
					name: testPath,
					path: testPath,
					cmd:  &cmd,
					err:  string(em),
				}
				cases = append(cases, &tc)
			} else {
				result, err := os.ReadFile(testPath + "/result.yaml")
				if err != nil {
					t.Error(err)
					return
				}
				tc := testCase{
					name:   testPath,
					path:   testPath,
					cmd:    &cmd,
					result: string(result),
				}
				cases = append(cases, &tc)
			}
		}
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			e, err := NewExecutor(tc.cmd, tc.path)
			if tc.err != "" && err != nil {
				if tc.err == err.Error() {
					return
				}
			}
			res, err := e.Exec()
			if err != nil {
				t.Fatalf(err.Error())
				return
			}
			resYaml, err := yaml.Marshal(res)
			if string(resYaml) != tc.result {
				t.Fatalf(err.Error())
				return
			}
			if string(resYaml) != tc.result {
				t.Fatalf(diff.Diff(string(resYaml), tc.result))
			}
		})
	}
}
