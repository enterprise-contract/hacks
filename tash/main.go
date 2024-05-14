package main

import (
	"bytes"
	"fmt"
	"os"
	"path"
	"slices"
	"sort"
	"strings"

	pipeline "github.com/tektoncd/pipeline/pkg/apis/pipeline/v1"
	core "k8s.io/api/core/v1"
	"mvdan.cc/sh/v3/syntax"
	"sigs.k8s.io/yaml"
)

var (
	image = "quay.io/redhat-appstudio/build-trusted-artifacts:latest@sha256:4e39fb97f4444c2946944482df47b39c5bbc195c54c6560b0647635f553ab23d"

	use = pipeline.Step{
		Name:  "use-trusted-artifact",
		Image: image,
		Args: []string{
			"use",
			"$(params.SOURCE_ARTIFACT)=/var/workdir/source",
			"$(params.CACHI2_ARTIFACT)=/var/workdir/cachi2",
		},
	}

	create = pipeline.Step{
		Name:  "create-trusted-artifact",
		Image: image,
		Env: []core.EnvVar{
			{
				Name:  "IMAGE_EXPIRES_AFTER",
				Value: "$(params.ociArtifactExpiresAfter)",
			},
		},
		VolumeMounts: []core.VolumeMount{
			{
				Name:      "source",
				MountPath: "/var/source",
			},
		},
		Args: []string{
			"create",
			"--store",
			"$(params.ociStorage)",
			"$(results.sourceArtifact.path)=/var/source",
		},
	}
)

func fail(err error) {
	fmt.Fprint(os.Stderr, err)
	os.Exit(1)
}

func check[T any](val T, err error) T {
	if err != nil {
		fail(err)
	}

	return val
}

func removeEnvUse(f *syntax.File, name string) []*syntax.Stmt {
	modified := make([]*syntax.Stmt, 0, len(f.Stmts))
	syntax.Walk(f, func(node syntax.Node) bool {
		if p, ok := node.(*syntax.ParamExp); ok {
			// parameter expansion, e.g. ${name}
			if p.Param.Value == name {
				// remove every line starting from the line where the ${name} was used
				start := p.Param.Pos().Line()

				var end uint = 0
				for _, s := range f.Stmts {
					line := s.Pos().Line()
					if line == start {
						if ifstmt, ok := s.Cmd.(*syntax.IfClause); ok {
							// if the if statement is at the start line, remove
							// the lines till the corresponding `fi` statement
							end = ifstmt.FiPos.Line()
						}
						if assign, ok := s.Cmd.(*syntax.CallExpr); ok {
							// remove the whole assignment
							end = assign.End().Line()
						}
					}

					if line < start || (line > end || end == 0) {
						// add only the lines that are not in the start-end segment
						modified = append(modified, s)
					}
				}
			}
		}

		return true
	})

	return modified
}

func removeUnusedFunctions(f *syntax.File) []*syntax.Stmt {
	used := make([]string, 0, 10) // includes used functions and other calls (echo, printf...)
	syntax.Walk(f, func(node syntax.Node) bool {
		if c, ok := node.(*syntax.CallExpr); ok && len(c.Args) > 0 {
			// first argument of a call statement is the name
			used = append(used, c.Args[0].Lit())
		}

		return true
	})

	sort.Strings(used)

	forRemoval := make([]struct{ start, end uint }, 0, 10)
	syntax.Walk(f, func(node syntax.Node) bool {
		if fn, ok := node.(*syntax.FuncDecl); ok {
			if _, found := slices.BinarySearch(used, fn.Name.Value); !found {
				// we found a function declared and unused
				forRemoval = append(forRemoval, struct{ start, end uint }{fn.Pos().Line(), fn.End().Line()})
			}
		}
		return true
	})

	modified := make([]*syntax.Stmt, 0, len(f.Stmts))
	for _, s := range f.Stmts {
		line := s.Position.Line()
		remove := false
		for _, r := range forRemoval {
			if remove = line >= r.start && line <= r.end; remove {
				// found lines comprising a unused function declaration
				break
			}
		}

		if !remove {
			modified = append(modified, s)
		}
	}

	return modified
}

type Recipe struct {
	Base           string                `json:"base"`
	AddParams      pipeline.ParamSpecs   `json:"addParams"`
	RemoveParams   []string              `json:"removeParams"`
	AddResult      []pipeline.TaskResult `json:"addResult"`
	AddEnvironment []core.EnvVar         `json:"addEnvironment"`
	AddVolumeMount []core.VolumeMount    `json:"addVolumeMount"`
	AddVolume      []core.Volume         `json:"addVolume"`
	Add            []string              `json:"add"`
}

func main() {
	b := check(os.ReadFile(os.Args[1]))

	// with defaults
	recipe := Recipe{
		AddParams: pipeline.ParamSpecs{
			{
				Name:        "ociStorage",
				Description: "The OCI repository where the clone repository will be stored.",
				Type:        pipeline.ParamTypeString,
			},
			{
				Name:        "imageExpiresAfter",
				Description: "Expiration date for the artifacts created in the OCI repository.",
				Type:        pipeline.ParamTypeString,
			},
		},
		AddResult: []pipeline.TaskResult{
			{
				Name:        "sourceArtifact",
				Description: "The OCI reference to the trusted source artifact containing the cloned git repo.",
				Type:        pipeline.ResultsTypeString,
			},
		},
		AddVolumeMount: []core.VolumeMount{
			{
				Name:      "source",
				MountPath: "/var/source",
			},
		},
		AddVolume: []core.Volume{
			{
				Name: "source",
				VolumeSource: core.VolumeSource{
					EmptyDir: &core.EmptyDirVolumeSource{},
				},
			},
		},
	}

	if err := yaml.Unmarshal(b, &recipe); err != nil {
		fail(err)
	}

	b = check(os.ReadFile(recipe.Base))
	task := pipeline.Task{}
	if err := yaml.Unmarshal(b, &task); err != nil {
		fail(err)
	}

	p := syntax.NewParser(syntax.KeepComments(true))
	if os.Getenv("DEBUG") != "" {
		for i := range task.Spec.Steps {
			if task.Spec.Steps[i].Script == "" {
				continue
			}

			r := strings.NewReader(task.Spec.Steps[i].Script)
			f := check(p.Parse(r, ""))
			buf := bytes.Buffer{}
			syntax.NewPrinter(syntax.KeepPadding(true), syntax.Indent(2)).Print(&buf, f)

			task.Spec.Steps[i].Script = buf.String()
		}

		b = check(yaml.Marshal(&task))

		if err := os.WriteFile(path.Base(recipe.Base)+".original", b, 0644); err != nil {
			fail(err)
		}
	}

	task.Spec.Params = slices.DeleteFunc(task.Spec.Params, func(ps pipeline.ParamSpec) bool {
		for _, rm := range recipe.RemoveParams {
			if ps.Name == rm {
				return true
			}
		}

		return false
	})
	task.Spec.Params = append(task.Spec.Params, recipe.AddParams...)
	task.Spec.Results = append(task.Spec.Results, recipe.AddResult...)
	task.Spec.Volumes = append(task.Spec.Volumes, recipe.AddVolume...)

	for i := range task.Spec.Steps {
		env := make([]string, 0, 5)
		task.Spec.Steps[i].Env = slices.DeleteFunc(task.Spec.Steps[i].Env, func(e core.EnvVar) bool {
			for _, rm := range recipe.RemoveParams {
				if strings.Contains(e.Value, "$(params."+rm+")") {
					env = append(env, e.Name)
					return true
				}
			}

			return false
		})

		task.Spec.Steps[i].Env = append(task.Spec.Steps[i].Env, recipe.AddEnvironment...)
		task.Spec.Steps[i].VolumeMounts = append(task.Spec.Steps[i].VolumeMounts, recipe.AddVolumeMount...)

		if task.Spec.Steps[i].Script == "" {
			continue
		}

		r := strings.NewReader(task.Spec.Steps[i].Script)
		f := check(p.Parse(r, ""))

		for _, rm := range env {
			f.Stmts = removeEnvUse(f, rm)
		}
		f.Stmts = removeUnusedFunctions(f)

		buf := bytes.Buffer{}
		syntax.NewPrinter(syntax.KeepPadding(true), syntax.Indent(2)).Print(&buf, f)

		task.Spec.Steps[i].Script = buf.String()
	}

	sort.Strings(recipe.Add)
	if _, found := slices.BinarySearch(recipe.Add, "use"); found {
		task.Spec.Steps = append([]pipeline.Step{use}, task.Spec.Steps...)
	}
	if _, found := slices.BinarySearch(recipe.Add, "create"); found {
		task.Spec.Steps = append(task.Spec.Steps, create)
	}

	b = check(yaml.Marshal(&task))

	if err := os.WriteFile(path.Base(recipe.Base), b, 0644); err != nil {
		fail(err)
	}
}
