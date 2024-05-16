package main

import (
	"bytes"
	"slices"
	"strings"

	pipeline "github.com/tektoncd/pipeline/pkg/apis/pipeline/v1"
	core "k8s.io/api/core/v1"
)

var (
	image = "quay.io/redhat-appstudio/build-trusted-artifacts:latest@sha256:4e39fb97f4444c2946944482df47b39c5bbc195c54c6560b0647635f553ab23d"

	sourceResult = pipeline.TaskResult{
		Name:        "sourceArtifact",
		Description: "The OCI reference to the trusted source artifact containing the cloned git repo.",
		Type:        pipeline.ResultsTypeString,
	}

	useParams = pipeline.ParamSpecs{
		{
			Name:        "SOURCE_ARTIFACT",
			Type:        pipeline.ParamTypeString,
			Description: "The trusted artifact URI containing the application source code.",
		},
		{
			Name:        "CACHI2_ARTIFACT",
			Type:        pipeline.ParamTypeString,
			Description: "The trusted artifact URI containing the prefetched dependencies.",
			Default:     &pipeline.ParamValue{Type: pipeline.ParamTypeString, StringVal: ""},
		},
	}

	createParams = pipeline.ParamSpecs{
		{
			Name:        "ociStorage",
			Description: "The OCI repository where the clone repository will be stored.",
			Type:        pipeline.ParamTypeString,
		},
		{
			Name:        "ociArtifactExpiresAfter",
			Description: "Expiration date for the artifacts created in the OCI repository.",
			Type:        pipeline.ParamTypeString,
			Default:     &pipeline.ParamValue{Type: pipeline.ParamTypeString, StringVal: ""},
		},
	}
)

func perform(task *pipeline.Task, recipe *Recipe) error {
	task.Name += recipe.Suffix
	task.Spec.Description = recipe.Description
	if _, ok := task.Annotations["tekton.dev/displayName"]; ok {
		task.Annotations["tekton.dev/displayName"] += recipe.DisplaySuffix
	}
	task.Spec.Params = slices.DeleteFunc(task.Spec.Params, func(ps pipeline.ParamSpec) bool {
		for _, rm := range recipe.RemoveParams {
			if ps.Name == rm {
				return true
			}
		}

		return false
	})
	task.Spec.Workspaces = slices.DeleteFunc(task.Spec.Workspaces, func(wd pipeline.WorkspaceDeclaration) bool {
		for _, rm := range recipe.RemoveWorkspaces {
			if wd.Name == rm {
				return true
			}
		}
		return false
	})
	if len(task.Spec.Workspaces) == 0 {
		task.Spec.Workspaces = nil
	}

	task.Spec.Params = append(task.Spec.Params, recipe.AddParams...)

	if recipe.use {
		task.Spec.Params = append(task.Spec.Params, useParams...)
	}

	if recipe.create {
		task.Spec.Params = append(task.Spec.Params, createParams...)
	}

	if len(recipe.AddResult) == 0 && recipe.create {
		recipe.AddResult = []pipeline.TaskResult{sourceResult}
	}
	task.Spec.Results = append(task.Spec.Results, recipe.AddResult...)

	if len(recipe.AddVolume) == 0 {
		recipe.AddVolume = []core.Volume{core.Volume{
			Name: recipe.WorkdirName,
			VolumeSource: core.VolumeSource{
				EmptyDir: &core.EmptyDirVolumeSource{},
			},
		}}
	}
	task.Spec.Volumes = append(task.Spec.Volumes, recipe.AddVolume...)

	if len(recipe.AddVolumeMount) == 0 {
		recipe.AddVolumeMount = []core.VolumeMount{core.VolumeMount{
			Name:      recipe.WorkdirName,
			MountPath: "/var/" + recipe.WorkdirName,
		}}
	}

	removeEnv := func(env *[]string) func(core.EnvVar) bool {
		return func(e core.EnvVar) bool {
			for _, rm := range recipe.RemoveParams {
				if strings.Contains(e.Value, "$(params."+rm+")") {
					*env = append(*env, e.Name)
					return true
				}
			}

			for _, rm := range recipe.RemoveWorkspaces {
				if strings.Contains(e.Value, "$(workspaces."+rm+".path)") {
					*env = append(*env, e.Name)
					return true
				}
			}

			return false
		}
	}

	templateEnv := make([]string, 0, 5)
	if task.Spec.StepTemplate != nil {
		task.Spec.StepTemplate.VolumeMounts = append(task.Spec.StepTemplate.VolumeMounts, recipe.AddVolumeMount...)

		task.Spec.StepTemplate.Env = slices.DeleteFunc(task.Spec.StepTemplate.Env, removeEnv(&templateEnv))
	}

	for i := range task.Spec.Steps {
		env := make([]string, 0, 5)

		task.Spec.Steps[i].Env = slices.DeleteFunc(task.Spec.Steps[i].Env, removeEnv(&env))

		task.Spec.Steps[i].Env = append(task.Spec.Steps[i].Env, recipe.AddEnvironment...)

		if task.Spec.StepTemplate == nil {
			task.Spec.Steps[i].VolumeMounts = append(task.Spec.Steps[i].VolumeMounts, recipe.AddVolumeMount...)
		}

		task.Spec.Steps[i].WorkingDir = applyReplacements(task.Spec.Steps[i].WorkingDir, recipe.Replacements)

		if !isShell(task.Spec.Steps[i].Script) {
			continue
		}

		if len(recipe.Replacements) > 0 {
			task.Spec.Steps[i].Script = applyReplacements(task.Spec.Steps[i].Script, recipe.Replacements)
		}

		r := strings.NewReader(task.Spec.Steps[i].Script)
		f, err := parser.Parse(r, task.Spec.Steps[i].Name+"_script.sh")
		if err != nil {
			return err
		}

		for _, rm := range templateEnv {
			f.Stmts = removeEnvUse(f, rm)
		}
		for _, rm := range env {
			f.Stmts = removeEnvUse(f, rm)
		}
		if len(recipe.RegexReplacements) > 0 {
			f.Stmts = replaceLiterals(f, recipe.RegexReplacements)
		}

		f.Stmts = removeUnusedFunctions(f)

		buf := bytes.Buffer{}
		if err := printer.Print(&buf, f); err != nil {
			return err
		}

		task.Spec.Steps[i].Script = buf.String()
	}

	if recipe.use {
		task.Spec.Steps = append([]pipeline.Step{pipeline.Step{
			Name:  "use-trusted-artifact",
			Image: image,
			Args: []string{
				"use",
				"$(params.SOURCE_ARTIFACT)=/var/" + recipe.WorkdirName + "/source",
				"$(params.CACHI2_ARTIFACT)=/var/" + recipe.WorkdirName + "/cachi2",
			},
		}}, task.Spec.Steps...)
	}
	if recipe.create {
		task.Spec.Steps = append(task.Spec.Steps, pipeline.Step{
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
					Name:      recipe.WorkdirName,
					MountPath: "/var/" + recipe.WorkdirName,
				},
			},
			Args: []string{
				"create",
				"--store",
				"$(params.ociStorage)",
				"$(results.sourceArtifact.path)=/var/" + recipe.WorkdirName,
			},
		})
	}

	if err := format(task); err != nil {
		return err
	}

	return nil
}
