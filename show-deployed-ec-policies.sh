#!/usr/bin/env bash
#
# Run this script to quickly answer the question "What version of
# conforma/policy do we think is being used right now in Konflux?"
#
# Do it by looking in the applicable git repos, rather than inspecting
# the cluster/clusters directly, which would probably be more dependable
# but would require some extra effort to make cluster credentials available.
#
set -o errexit
set -o nounset
set -o pipefail

APPLICABLE_REPOS="
  git@github.com:redhat-appstudio/infra-deployments.git
  git@gitlab.cee.redhat.com:releng/konflux-release-data.git
"

EC_POLICIES="${PWD}/../policy"

OPT_RAW="${1:-""}"

for repo in $APPLICABLE_REPOS; do
  echo "$repo:"
  echo "$repo:" | tr '[:print:]' '-'

  TMP_DIR=$(mktemp -d)
  cd $TMP_DIR
  git clone --quiet --depth 1 "$repo" .

  GREP_OUTPUT=$( git grep 'quay.io/enterprise-contract/ec-release-policy' )
  if [[ $OPT_RAW == "--raw" ]]; then
    # Show the raw grep results
    echo "$GREP_OUTPUT"

  elif [[ $OPT_RAW == "--short" ]]; then
    # Simpler output
    echo "$GREP_OUTPUT" | cut -d':' -f4,5,6 | sort | uniq

  else
    # Show the commit message for the unique shas found.
    # The multiple cuts are to pull the git shas from lines like this:
    #   foo/bar/file.yaml:   - oci::quay.io/enterprise-contract/ec-release-policy:git-9e347db@sha256:209d9d...
    # The git log is to show the full commit message for convenience.
    # The sed is to indent the commit.
    # Generally there is just one uniq sha per repo, but we won't assume that.
    echo "$GREP_OUTPUT" |
      cut -d':' -f5 | cut -d'@' -f1 | cut -d'-' -f2 |
      sort | uniq |
      xargs -i git --git-dir $EC_POLICIES/.git/ log -n1 \{\} |
      sed 's/^/    /'

  fi

  rm -rf $TMP_DIR

  echo ""
  echo ""

done
