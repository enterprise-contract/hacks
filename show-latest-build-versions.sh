#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

# Set this for verbose output
VERBOSE="${VERBOSE:-""}"

_show_details() {
	local title="$1"
	local ref="$2"
	local ver="$3"

	# Make sure we have the latest
  podman pull --quiet $ref >/dev/null

	# Get the digest
	local digest="$(skopeo inspect "docker://$ref" | jq -r .Digest)"

	# The likely original Konflux built image
	local konflux_image="quay.io/redhat-user-workloads/rhtap-contract-tenant/ec-$ver/cli-$ver@$digest"

	if [ "$VERBOSE" = "1" ]; then
		# Verbose output
		echo ""
		echo $title
		echo $title | tr '[:print:]' '-'

		echo Ref:
		echo "   $ref"

		echo Pinned ref:
		echo "   $ref@$digest"

		if [[ -n "$ver" ]]; then
			echo Likely Konflux build ref:
			echo "   $konflux_image"
		fi

		echo Version:
		podman run --rm "$ref@$digest" version | sed 's/^/   /'

		echo Binaries in /usr/local/bin:
		podman run --rm --entrypoint /bin/bash "$ref@$digest" -c 'ls -l /usr/local/bin' | sed 's/^/   /'

		echo Command for poking around:
		echo "    podman run --rm -it --entrypoint /bin/bash $ref"

		echo ""

	else
		# Brief output
		echo "$ref@$digest"
		[[ -n "$ver" ]] && echo "$konflux_image"
		podman run --rm "$ref@$digest" version | sed 's/^/   /' | head -3
		echo ""

	fi
}

# Built and pushed by Konflux from a release branch
# (This is shipped to customers with RHTAS)
RH_TITLE="Red Hat Build"
RH_REPO="registry.redhat.io/rhtas/ec-rhel9"
RH_TAGS="${1:-"0.4 0.5 0.6"}"

# Built/pushed by Konflux from main branch
# (This is used by Red Hat Konflux)
UPSTREAM_KONFLUX_TITLE="Upstream Konflux Build"
UPSTREAM_KONFLUX_REPO="quay.io/enterprise-contract/cli"
UPSTREAM_KONFLUX_TAG="latest"
UPSTREAM_KONFLUX_COMPONENT="cli-main-ci"

# Built/pushed by GitHub from main branch
UPSTREAM_GITHUB_TITLE="Upstream GitHub Build"
UPSTREAM_GITHUB_REPO="quay.io/enterprise-contract/ec-cli"
UPSTREAM_GITHUB_TAG="snapshot"
UPSTREAM_GITHUB_COMPONENT=""

for t in ${RH_TAGS}; do
	_show_details "$RH_TITLE ($t)" "$RH_REPO:$t" "cli-v${t/./}"
done

_show_details "$UPSTREAM_KONFLUX_TITLE" "$UPSTREAM_KONFLUX_REPO:$UPSTREAM_KONFLUX_TAG" "$UPSTREAM_KONFLUX_COMPONENT"

_show_details "$UPSTREAM_GITHUB_TITLE" "$UPSTREAM_GITHUB_REPO:$UPSTREAM_GITHUB_TAG" "$UPSTREAM_GITHUB_COMPONENT"
