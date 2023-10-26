#!/bin/env bash
# Copyright 2023 Red Hat, Inc.
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

set -o errexit
set -o pipefail
set -o nounset

# Find all the attestation files
ATTESTATIONS=$( find ./recordings -name attestation.json )

# If a content field is found, assume it contains base64
# encoded json, and insert a new field with the decoded object.
JQ_QUERY='
  walk(
    if type == "object" and .content? then
      .__decodedContent = (.content | @base64d | fromjson)
    else
      .
    end
  )
'

TMP_OUTPUT=/tmp/decoded-content-att.json
for att in $ATTESTATIONS; do
  # Apply the transformation
  jq "$JQ_QUERY" $att > $TMP_OUTPUT

  # Keep the output only if there were changes
  diff $att $TMP_OUTPUT >/dev/null || cp $TMP_OUTPUT $(dirname $att)
done
