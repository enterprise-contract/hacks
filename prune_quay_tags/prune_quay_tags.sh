#!/usr/bin/env bash
# Copyright The Conforma Contributors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail
# Exit on error, undefined variable, or pipeline failure

# ---------------------------
# Ensure required commands are available
# ---------------------------
for cmd in skopeo jq curl date; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "❌ '$cmd' is not installed or not in your PATH. Please install $cmd."
    exit 1
  fi
done

# ---------------------------
# Defaults for CLI arguments
# ---------------------------
REPO=""
FILTER=""
DAYS=""
BEFORE=""
QUAY_TOKEN=""
DRY_RUN=false

# ---------------------------
# Parse flags
# ---------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)    REPO="$2";         shift 2;;
    --filter)  FILTER="$2";       shift 2;;
    --days)    DAYS="$2";         shift 2;;
    --before)  BEFORE="$2";       shift 2;;
    --token)   QUAY_TOKEN="$2";   shift 2;;
    --dry-run) DRY_RUN=true;      shift;;
    *) echo "Usage: $0 --repo <repo> --filter <regex> [--days N | --before YYYY-MM-DD] [--token] [--dry-run]"; exit 1;;
  esac
done

# ---------------------------
# Validate required arguments
# ---------------------------
if [[ -z "$REPO" || -z "$FILTER" ]]; then
  echo "❌ Missing --repo or --filter"
  exit 1
fi
if [[ -z "$DAYS" && -z "$BEFORE" ]]; then
  echo "❌ You must supply either --days or --before"
  exit 1
fi

# ---------------------------
# Compute cutoff epoch time
# ---------------------------
if [[ -n "$DAYS" ]]; then
  CUTOFF=$(date -d "-$DAYS days" +%s)
else
  CUTOFF=$(date -d "$BEFORE" +%s)
fi

# ---------------------------
# Echo context to user
# ---------------------------
echo "🔍 Repo:    $REPO"
echo "🔎 Filter:  $FILTER"
echo "📅 Cutoff:  Before $(date -d "@$CUTOFF" +'%Y-%m-%d %H:%M:%S %Z')"
if [[ -n "${QUAY_TOKEN:-}" ]]; then
  echo "🔑 Token:   ${QUAY_TOKEN:0:4}... (truncated)"
fi
$DRY_RUN && echo "🧪 Dry‑run: ON"

# ---------------------------
# Authentication check
# ---------------------------
# Look for quay.io credentials in various files
if jq -e '.auths["quay.io"]' ~/.docker/config.json >/dev/null 2>&1; then
  echo "✅ 🐋 Logged in via Docker credentials"
# check to Podman/containers
elif jq -e '."quay.io"' ~/.config/containers/auth.json >/dev/null 2>&1; then
  echo "✅ 🦭 Logged in via containers/auth.json"
# check Skopeo
elif jq -e '.auths["quay.io"]' $XDG_RUNTIME_DIR/containers/auth.json >/dev/null 2>&1; then
  echo "✅ 📦 Logged in via \$XDG_RUNTIME_DIR/containers/auth.json"
# no creds? Suggest logging in
else
  echo "❌ No quay.io entry found in your credential files"
  echo "Please log in to quay.io using Podman, Docker, or Skopeo first."
  exit 1
fi

echo ""

# ---------------------------
# Pagination & tag fetching
# ---------------------------
PAGE=1
BASE_URL="https://quay.io/api/v1/repository/${REPO}/tag/?limit=100"
DELETED=0
FOUND=0

ALL_LINES=()

while :; do
  # build curl args
  curl_args=( -sfG "${BASE_URL}" )
  curl_args+=( --data-urlencode "page=${PAGE}" )
  curl_args+=( --data-urlencode "onlyActiveTags=true" )
  curl_args+=( --data-urlencode "filter_tag_name=like:${FILTER}" )
  [[ -n "${QUAY_TOKEN:-}" ]] && curl_args+=( -H "Authorization: Bearer ${QUAY_TOKEN}" )

  # fetch (will exit on HTTP error thanks to -f)
  RESPONSE=$(curl "${curl_args[@]}")

  # check for API‐level error
  if [[ "$(jq -r '.error // empty' <<<"$RESPONSE")" ]]; then
    echo "❌ API error: $(jq -r '.error' <<<"$RESPONSE")" >&2
    exit 1
  fi

  # extract and accumulate this page’s tags
  mapfile -t page_lines < <(
    jq -r --arg f "$FILTER" '
      .tags[]
      | "\(.name)|\(.last_modified)"
    ' <<<"$RESPONSE"
  )
  ALL_LINES+=( "${page_lines[@]}" )

  # pagination check
  has_additional=$(jq -r '.has_additional // "false"' <<<"$RESPONSE")
  if [[ "$has_additional" == "true" ]]; then
    ((PAGE++))
  else
    break
  fi
done

# ---------------------------
# Process each matching tag
# ---------------------------
for LINE in "${ALL_LINES[@]}"; do
    IFS="|" read -r tag last_modified <<< "$LINE"
    last_sec=$(date -d "$last_modified" +%s 2>/dev/null || echo 0)
    if [[ "$last_sec" -lt "$CUTOFF" ]]; then
        # add to the count of found tags, incrementing safely:
        : $((FOUND++))
        fmt=$(date -d "$last_modified" +"%Y-%m-%d %H:%M:%S %Z")
        if $DRY_RUN; then
          printf "%-80s %s 💡 would be deleted\n" "$tag" "$fmt"
        else
          if skopeo delete "docker://quay.io/${REPO}:${tag}" &> /dev/null; then
            printf "%-80s %s ✅ deleted\n" "$tag" "$fmt"
            # add to the count of deleted tags, incrementing safely:
            : $((DELETED++))
          else
            printf "%-80s %s ❌ failed\n"  "$tag" "$fmt"
          fi
        fi
    fi
done

echo ""
# ---------------------------
# Summary output
# ---------------------------
if $DRY_RUN; then
  echo "🧪 Dry-run: would delete $FOUND tags matching “$FILTER”"
else
  echo "🔢 Total matching tags found: $FOUND"
  echo "✅ Total tags deleted: $DELETED"
fi
