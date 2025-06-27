#!/bin/bash

# Script to check if a Tekton Task bundle used in a PipelineRun is outdated.
# It parses an error message, extracts image and task details,
# downloads attestation, queries a policy data source for the latest bundle,
# and compares them.

# --- How to Use ---
# Run $ ./gemini_check_bundle_ref.sh error_msg.txt
# Where error_msg.txt contains the error message emitted by Conforma in the logs.
# Example:
#   ✕ [Violation] tasks.required_tasks_found
#     ImageRef: quay.io/redhat-user-workloads/rhtap-release-2-tenant/release-service/release-service@sha256:71bafc0b63e86183ab29deba798d4e9b06b2731e057a819b348dd8e52d32c048
#     Reason: Required task "rpms-signature-scan" is missing
#     Term: rpms-signature-scan
#     Title: All required tasks were included in the pipeline
#     Description: Ensure that the set of required tasks are included in the PipelineRun attestation. To exclude this rule add
#     "tasks.required_tasks_found:rpms-signature-scan" to the `exclude` section of the policy configuration.
#     Solution: Make sure all required tasks are in the build pipeline. The required task list is contained as
#     https://conforma.dev/docs/ec-cli/configuration.html#_data_sources under the key 'required-tasks'.


# --- Configuration ---
# The base URL for the acceptable bundles policy data.
# This should point to the quay.io/konflux-ci/tekton-catalog/data-acceptable-bundles:latest
# as per your description.
POLICY_DATA_SOURCE="oci::quay.io/konflux-ci/tekton-catalog/data-acceptable-bundles:latest"

# --- Functions ---

# Function to extract a value from the error message using grep and awk
extract_from_error() {
    local field_name="$1"
    local error_message="$2"
    echo "$error_message" | grep -oP "${field_name}:\s*\K.*" | head -n 1 | awk '{$1=$1};1'
}

# Function to extract the SHA256 digest from a full reference (e.g., quay.io/path@sha256:digest)
extract_sha256_digest() {
    local full_ref="$1"
    echo "$full_ref" | awk -F'@' '{print $2}'
}

# --- Main Script ---

if [ -z "$1" ]; then
    echo "Usage: $0 <path_to_error_message_file>"
    echo "       Or pipe the error message: cat error.txt | $0"
    exit 1
fi

# Read the error message from file or stdin
if [ -f "$1" ]; then
    ERROR_MESSAGE=$(cat "$1")
else
    ERROR_MESSAGE=$(cat -)
fi

echo "--- Analyzing Error Message ---"

# 1. Extract ImageRef and Task Name
IMAGE_REF=$(extract_from_error "ImageRef" "$ERROR_MESSAGE")
TASK_NAME=$(extract_from_error "Term" "$ERROR_MESSAGE")

if [ -z "$IMAGE_REF" ] || [ -z "$TASK_NAME" ]; then
    echo "Error: Could not extract ImageRef or Task Name from the provided error message."
    echo "Please ensure the error message format is correct."
    exit 1
fi

echo "Extracted ImageRef: ${IMAGE_REF}"
echo "Extracted Task Name: ${TASK_NAME}"
echo ""

echo "--- Step 1: Downloading Attestation and Extracting User's Bundle Reference ---"

# Step 1. Download attestation and extract the bundle reference used by the user
# Note: cosign and jq must be installed on the system for this to work.
USER_BUNDLE_REF_FULL=$(cosign download attestation "${IMAGE_REF}" 2>/dev/null | \
    jq -r '.payload | @base64d | fromjson | .predicate.buildConfig.tasks[] | select(.name == "'"${TASK_NAME}"'") | .ref.params[] | select(.name == "bundle") | .value')

if [ -z "$USER_BUNDLE_REF_FULL" ]; then
    echo "Error: Could not extract user's bundle reference from attestation. Attestation might not exist or task name mismatch."
    echo "Make sure cosign is installed and configured, and the image reference is correct."
    exit 1
fi

USER_BUNDLE_SHA=$(extract_sha256_digest "${USER_BUNDLE_REF_FULL}")

echo "User's Bundle Reference (Full): ${USER_BUNDLE_REF_FULL}"
echo "User's Bundle SHA256: ${USER_BUNDLE_SHA}"
echo ""

echo "--- Step 2: Extracting Tag from User's Bundle Reference ---"

# Step 2. Extract the tag name from the user's bundle ref
# Example: quay.io/konflux-ci/tekton-catalog/task-rpms-signature-scan:0.2@sha256:...
# We need "0.2"
BUNDLE_REPO_AND_TAG=$(echo "${USER_BUNDLE_REF_FULL}" | awk -F'@' '{print $1}')
BUNDLE_TAG=$(echo "${BUNDLE_REPO_AND_TAG}" | awk -F':' '{print $NF}')

if [ -z "$BUNDLE_TAG" ]; then
    echo "Error: Could not extract tag from user's bundle reference."
    exit 1
fi

echo "Extracted Bundle Tag: ${BUNDLE_TAG}"
echo ""

echo "--- Step 3: Getting Latest Bundle Reference from Policy Data ---"

# Step 3. Get the latest bundle ref for the task from the policy data source
# Note: ec-cli and jq must be installed for this to work.
LATEST_BUNDLE_INFO=$(ec inspect policy-data --source "${POLICY_DATA_SOURCE}" 2>/dev/null | \
    jq -r '.["trusted_tasks"]|to_entries[]|select(.key|contains("'${TASK_NAME}':'${BUNDLE_TAG}'"))|.value[0]')

if [ -z "$LATEST_BUNDLE_INFO" ] || [ "$LATEST_BUNDLE_INFO" == "null" ]; then
    echo "Error: Could not retrieve latest bundle information for task '${TASK_NAME}:${BUNDLE_TAG}' from policy data."
    echo "Ensure ec-cli is installed and configured, and the task/tag combination exists in the policy data."
    exit 1
fi

LATEST_BUNDLE_REF_SHA=$(echo "$LATEST_BUNDLE_INFO" | jq -r '.ref')
LATEST_BUNDLE_EFFECTIVE_ON=$(echo "$LATEST_BUNDLE_INFO" | jq -r '.effective_on')

echo "Latest Bundle SHA256 from Policy: ${LATEST_BUNDLE_REF_SHA}"
echo "Latest Bundle Effective On: ${LATEST_BUNDLE_EFFECTIVE_ON}"
echo ""

echo "--- Step 4: Comparing Bundle References ---"

# Step 4. Compare the SHAs
if [ "$USER_BUNDLE_SHA" == "$LATEST_BUNDLE_REF_SHA" ]; then
    echo "✅ CONCLUSION: The bundle reference used by the user is UP-TO-DATE."
else
    echo "❌ CONCLUSION: The bundle reference used by the user is OUTDATED!"
    echo ""
    echo "User's bundle SHA: ${USER_BUNDLE_SHA}"
    echo "Latest bundle SHA: ${LATEST_BUNDLE_REF_SHA} (Effective on: ${LATEST_BUNDLE_EFFECTIVE_ON})"
    echo ""
    echo "Solution: Advise the user to update their Tekton Task bundle to the latest effective version."
fi

echo "--- Script Finished ---"
