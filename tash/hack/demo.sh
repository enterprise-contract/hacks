#!/bin/bash

DEBUG=1 go run .. git-clone-recipe.yaml
diff git-clone.yaml*
