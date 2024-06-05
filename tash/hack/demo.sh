#!/bin/bash

# With an empty recipe we just do canonical formatting of the input.
# Do this so we get a more meaningful diff below.
yq '{"base": .base}' git-clone-recipe.yaml >empty-recipe.yaml
DEBUG=1 go run .. empty-recipe.yaml >git-clone-a.yaml

# The real recipe
DEBUG=1 go run .. git-clone-recipe.yaml >git-clone-b.yaml

# Set DIFF=vimdiff if you like vimdiff
${DIFF:-diff} git-clone-a.yaml git-clone-b.yaml

# Use this to see the raw diff
#${DIFF:-diff} $(yq .base git-clone-recipe.yaml) git-clone-b.yaml
