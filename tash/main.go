package main

import (
	"os"
	"path"
)

func main() {
	recipe := expectValue(readRecipe(os.Args[1]))

	task := expectValue(readTask(recipe.Base))

	if os.Getenv("DEBUG") != "" {
		expect(format(task))
		writeTask(task, path.Base(recipe.Base)+".original")
	}

	expect(perform(task, recipe))

	expect(writeTask(task, path.Base(recipe.Base)))
}
