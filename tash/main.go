package main

import (
	"fmt"
	"os"
)

func main() {
	if len(os.Args) != 2 {
		fmt.Fprintf(os.Stderr, "Usage: %s path/to/recipe.yaml\n", os.Args[0])
		os.Exit(1)
	}

	recipe := expectValue(readRecipe(os.Args[1]))

	task := expectValue(readTask(recipe.Base))

	expect(perform(task, recipe))

	expect(writeTask(task, os.Stdout))
}
