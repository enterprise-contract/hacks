#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

RH_TITLE="Red Hat Build"
RH_REPO="registry.redhat.io/rhtas/ec-rhel9"
# There's no latest tag but there is a floating tag, currently 0.2
RH_TAG="${1:-"0.4"}"

UPSTREAM_TITLE="Upstream Build"
UPSTREAM_REPO="quay.io/enterprise-contract/ec-cli"
UPSTREAM_TAG="snapshot"

_show_details() {
  local title="$1"
  local ref="$2"

  # Make sure we have the latest
  podman pull --quiet $ref

  # Get the digest
  local digest="$(skopeo inspect "docker://$ref" | jq -r .Digest)"

  echo ""
  echo $title
  echo $title | tr '[:print:]' '-'

  echo Ref:
  echo "   $ref"

  echo Pinned ref:
  echo "   $ref@$digest"

  echo Version:
  podman run --rm "$ref@$digest" version | sed 's/^/   /'

  echo Binaries in /usr/local/bin:
  podman run --rm --entrypoint /bin/bash "$ref@$digest" -c 'ls -l /usr/local/bin' | sed 's/^/   /'

  echo Command for poking around:
  echo "    podman run --rm -it --entrypoint /bin/bash $ref"

  echo ""
}

_show_details "$RH_TITLE" "$RH_REPO:$RH_TAG"

_show_details "$UPSTREAM_TITLE" "$UPSTREAM_REPO:$UPSTREAM_TAG"
