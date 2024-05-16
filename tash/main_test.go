package main

import (
	"os"
	"path"
	"testing"

	"github.com/google/go-cmp/cmp"
)

func TestGolden(t *testing.T) {
	dirs, err := os.ReadDir("golden")
	if err != nil {
		t.Fatal(err)
	}

	for _, dir := range dirs {
		t.Run(dir.Name(), func(t *testing.T) {
			task, err := readTask(path.Join("golden", dir.Name(), "base.yaml"))
			if err != nil {
				t.Fatal(err)
			}
			expected, err := readTask(path.Join("golden", dir.Name(), "ta.yaml"))
			if err != nil {
				t.Fatal(err)
			}

			recipe, err := readRecipe(path.Join("golden", dir.Name(), "recipe.yaml"))
			if err != nil {
				t.Fatal(err)
			}

			if err := perform(task, recipe); err != nil {
				t.Fatal(err)
			}

			if err := format(expected); err != nil {
				t.Fatal(err)
			}

			if diff := cmp.Diff(expected, task); diff != "" {
				t.Errorf("%s mismatch (-want +got):\n%s", dir.Name(), diff)
			}
		})
	}
}
