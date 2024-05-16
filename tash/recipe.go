package main

import (
	"os"
	"slices"
	"sort"

	pipeline "github.com/tektoncd/pipeline/pkg/apis/pipeline/v1"
	core "k8s.io/api/core/v1"
	"sigs.k8s.io/yaml"
)

type Recipe struct {
	Add               []string              `json:"add"`
	AddEnvironment    []core.EnvVar         `json:"addEnvironment"`
	AddParams         pipeline.ParamSpecs   `json:"addParams"`
	AddResult         []pipeline.TaskResult `json:"addResult"`
	AddVolume         []core.Volume         `json:"addVolume"`
	AddVolumeMount    []core.VolumeMount    `json:"addVolumeMount"`
	Base              string                `json:"base"`
	Description       string                `json:"description"`
	DisplaySuffix     string                `json:"displaySuffix"`
	RegexReplacements map[string]string     `json:"regexReplacements"`
	RemoveParams      []string              `json:"removeParams"`
	RemoveWorkspaces  []string              `json:"removeWorkspaces"`
	Replacements      map[string]string     `json:"replacements"`
	Suffix            string                `json:"suffix"`
	WorkdirName       string                `json:"workdirName"`
	use               bool
	create            bool
}

func readRecipe(path string) (*Recipe, error) {
	b := expectValue(os.ReadFile(path))

	// with defaults
	recipe := Recipe{
		Suffix:        "-oci-ta",
		DisplaySuffix: " oci trusted artifacts",
		WorkdirName:   "workdir",
	}

	if err := yaml.Unmarshal(b, &recipe); err != nil {
		return nil, err
	}

	sort.Strings(recipe.Add)
	_, recipe.use = slices.BinarySearch(recipe.Add, "use")
	_, recipe.create = slices.BinarySearch(recipe.Add, "create")

	return &recipe, nil
}
