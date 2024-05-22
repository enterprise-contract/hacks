package main

import (
	"os"
)

func main() {
	recipe := expectValue(readRecipe(os.Args[1]))

	task := expectValue(readTask(recipe.Base))

	expect(perform(task, recipe))

	expect(writeTask(task, os.Stdout))
}
