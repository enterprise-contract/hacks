package main

import (
	"io"
	"os"
	"slices"
	"strings"

	pipeline "github.com/tektoncd/pipeline/pkg/apis/pipeline/v1"
	"github.com/tektoncd/pipeline/pkg/substitution"
	core "k8s.io/api/core/v1"
	"sigs.k8s.io/yaml"
)

func readTask(path string) (*pipeline.Task, error) {
	b := expectValue(os.ReadFile(path))
	task := pipeline.Task{}
	return &task, yaml.Unmarshal(b, &task)
}

func writeTask(task *pipeline.Task, writer io.Writer) error {
	if c, ok := writer.(io.Closer); ok {
		defer c.Close()
	}
	b, err := yaml.Marshal(task)
	if err != nil {
		return err
	}

	_, err = writer.Write(b)

	return err
}

func format(task *pipeline.Task) error {
	if err := formatScripts(task); err != nil {
		return err
	}

	slices.SortFunc(task.Spec.Params, func(a, b pipeline.ParamSpec) int {
		return strings.Compare(a.Name, b.Name)
	})

	slices.SortFunc(task.Spec.Volumes, func(a, b core.Volume) int {
		return strings.Compare(a.Name, b.Name)
	})

	for i := range task.Spec.Steps {
		slices.SortFunc(task.Spec.Steps[i].Env, func(a, b core.EnvVar) int {
			return strings.Compare(a.Name, b.Name)
		})
	}

	return nil
}

func applyReplacements(in string, replacements map[string]string) string {
	return substitution.ApplyReplacements(in, replacements)
}
