#!/bin/bash


# This is a test script to compare the output of the 
# ec validate image command with and without the --use-go-gather flag.
# This script requires that you've modified ec to not remove the ec-work-* directories
# At the time of this writing, this is achieved by commenting out the following line
# in the ec code:
#
# cmd/validate/image.go:  defer c.Destroy()


# Directory to start searching for Enterprise Contract Policy YAML files
SEARCH_DIR="/path/to/your/yaml/files"

# Define the command arguments

# Specify an image to validate, this is arbitrary as don't actually care about the image
IMAGE="quay.io/redhat-user-workloads/rhtap-build-tenant/build/image-controller@sha256:c9fccfb292e8ca14a48f568e7272f6c2c94b30cf12f3d68f3ea552e92976d47d"
CERT_OIDC_ISSUER="https://localhost"
CERT_IDENTITY="https://localhost"
IGNORE_REKOR="--ignore-rekor"
OUTPUT="--output data"

# Function to find the newest ec-work-* directory
find_newest_ec_work_dir() {
    find /tmp -maxdepth 1 -type d -name "ec-work-*" -printf '%T+ %p\n' | sort -r | head -n 1 | awk '{print $2}'
}

# Function to extract the sources from the policy file
# This avoids any other fields in the policy file that may cause issues
extract_sources_to_tmp() {
    local yaml_file="$1"
    local tmp_file="$2"
    
    yq eval '.spec.sources' "$yaml_file" > "$tmp_file"
    
    sed -i '1s/^/sources:\n/' "$tmp_file"
}

# Function to ignore the config.json files in the directories
# This is because the config.json file is different in each run due to timestamps
ignore_config_json() {
    local dir="$1"
    find "$dir" -name "config.json" -type f -delete
}

# Find all the YAML files in the search directory, processing the ones that are in
# the EnterpriseContractPolicy directories. This is to avoid processing other YAML files
# such as ReleasePlanAdmission files, etc.

# This script will process the policy file twice, 
# once with the --use-go-gather flag and once without.
# After each run, the ec-work-* directory is moved to a temporary directory
# and the config.json files are removed from the directories.
# The script then compares the two directories to see if they are equal.

find "$SEARCH_DIR" -type f -name "*.yaml" | while read -r yaml_file; do
    if grep -q "EnterpriseContractPolicy" "$yaml_file"; then
        echo "Processing $yaml_file"
        
        TMP_POLICY_FILE=$(mktemp /tmp/policy-XXXXXX.yaml)
        
        extract_sources_to_tmp "$yaml_file" "$TMP_POLICY_FILE"

        ec validate image --policy "$TMP_POLICY_FILE" --image $IMAGE --certificate-oidc-issuer $CERT_OIDC_ISSUER --certificate-identity $CERT_IDENTITY $IGNORE_REKOR $OUTPUT > /dev/null 2>&1
        
        BASE_DIR=$(find_newest_ec_work_dir)
        if [ -z "$BASE_DIR" ]; then
            echo "Error: No ec-work-* directory found after the first command."
            exit 1
        fi
        echo "Base directory found: $BASE_DIR"
        
        NUMBER=$(date +%s)
        mkdir -p "/tmp/$NUMBER/base"
        mv "$BASE_DIR"/* "/tmp/$NUMBER/base/"
        
        USEGOGATHER=1 ec validate image --policy "$TMP_POLICY_FILE" --image $IMAGE --certificate-oidc-issuer $CERT_OIDC_ISSUER --certificate-identity $CERT_IDENTITY $IGNORE_REKOR $OUTPUT > /dev/null 2>&1
        
        GATHER_DIR=$(find_newest_ec_work_dir)
        if [ -z "$GATHER_DIR" ]; then
            echo "Error: No ec-work-* directory found after the second command."
            exit 1
        fi
        echo "Gather directory found: $GATHER_DIR"
        
        mkdir -p "/tmp/$NUMBER/gather"
        mv "$GATHER_DIR"/* "/tmp/$NUMBER/gather/"
                
        ignore_config_json "/tmp/$NUMBER/base"
        ignore_config_json "/tmp/$NUMBER/gather"
        
        diff -r "/tmp/$NUMBER/base" "/tmp/$NUMBER/gather"
        
        if [ $? -ne 0 ]; then
            echo -e "Error: Directories /tmp/$NUMBER/base and /tmp/$NUMBER/gather are not equal.\n"
            exit 1
        else
            echo -e "Directories are equal.\n"
        fi

        rm -f "$TMP_POLICY_FILE"
    fi
done
