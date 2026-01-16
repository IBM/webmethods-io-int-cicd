#!/bin/bash

#################################################################################################################################################################
# Script Name: exportCertificatesList.sh                                                                                                                          #
# Summary    : Exports all Certificates or a single Certificate configuration from                                                                                  #
#              a given webMethods.io project repository using REST APIs.                                                                                        #
#                                                                                                                                                               #
# Usage      : ./exportCertificatesList.sh <LOCAL_DEV_URL> <admin_user> <admin_password> <repoName> <HOME_DIR> <assetID>                                 #
#                                                                                                                                                               #
# Mandatory Fields:                                                                                                                                             #
#   LOCAL_DEV_URL   - The base URL of the target webMethods.io environment                                                                                      #
#   admin_user      - Administrator username for authentication                                                                                                 #
#   admin_password  - Administrator password for authentication                                                                                                 #
#   repoName        - Repository (project) name in webMethods.io                                                                                                #
#   HOME_DIR        - Local home directory path for storing exports                                                                                             #
#   assetID         - service name of the Certificate                                                                            #
#                                                                                                                                                               #
# Example:                                                                                                                                                      #
#   ./exportCertificatesList.sh "https://mytenant.webmethods.io" "Administrator" "manage" "MyRepo" "/home/user/projects" true                                     #
#                                                                                                                                                               #
#################################################################################################################################################################


set -euo pipefail
LOCAL_DEV_URL=$1
admin_user=$2
admin_password=$3
repoName=$4
HOME_DIR=$5
assetID=$6
envTypes=${7:-}
source_type=${8:-}
debug=${@: -1}

if [[ "$debug" != "debug" && "$debug" != "trace" ]]; then
    debug=""
fi

# Debug mode
if [ "$debug" == "trace" ]; then
    echo "......Running in Trace mode ......" >&2
    set -x
elif [ "$debug" == "debug" ]; then
    echo "......Running in Debug mode ......" >&2
fi

echo "Starting exportCertificatesList.sh"
echo "Arguments: $@"


function echod() {
        if [ "${debug:-}" == "debug" ] || [ "${debug:-}" == "trace" ]; then
                echo "$@" >&2   
        fi
}

exportCertificatesList() {
    LOCAL_DEV_URL=$1
    admin_user=$2
    admin_password=$3
    repoName=$4
    HOME_DIR=$5
    assetID=$6
    envTypes=${7:-}
    source_type=${8:-}
    debug=${@: -1}




    echo "Running exportCertificatesList with parameters:"
    echo "LOCAL_DEV_URL=$LOCAL_DEV_URL"
    echo "admin_user=$admin_user"
    echo "admin_password=****"
    echo "repoName=$repoName"
    echo "HOME_DIR=$HOME_DIR"
    echo "assetID=$assetID"
    #echo "CERT_TYPE=$CERT_TYPE"
    echo "---------------------------------------------"

    cd "${HOME_DIR}/${repoName}" || exit 1

    if [ -z "$assetID" ] || [ "$assetID" = "null" ] || [ "$assetID" = "NA" ]; then
        Certificates_GET_LIST_URL="${LOCAL_DEV_URL}/apis/v1/rest/projects/${repoName}/configurations/certificates"

        CertificatesListJson=$(curl --silent --location --request GET "$Certificates_GET_LIST_URL" \
            --header 'Content-Type: application/json' \
            --header 'Accept: application/json' \
            -u "${admin_user}:${admin_password}")

        CertificatesList_file="./assets/projectConfigs/certificates/CertificatesList.json"

        if [ -z "$CertificatesListJson" ] || [ "$CertificatesListJson" = "null" ]; then
            echo "❌ No Certificates retrieved."
            return 0
        fi

        mapfile -t cert_entries < <(echo "$CertificatesListJson" | jq -r '.output[]? | [.certificateType, (if .certificateType == "PARTNER_CERTIFICATE" then .name elif .certificateType == "KEY_STORE" then .keyStoreName elif .certificateType == "TRUST_STORE" then .TrustStoreName else empty end)] | @tsv')
        if [ ${#cert_entries[@]} -eq 0 ]; then
            echo "ℹ️ No certificates found; skipping export."
            return 0
        fi

        mkdir -p ./assets/projectConfigs/certificates
        echo "$CertificatesListJson" | jq '.' > "$CertificatesList_file"
        echo "✅ Certificates List saved to: $CertificatesList_file"

        for entry in "${cert_entries[@]}"; do
            CERT_TYPE=$(echo "$entry" | awk -F'\t' '{print $1}')
            CERT_NAME=$(echo "$entry" | awk -F'\t' '{print $2}')
            if [[ -n "$CERT_NAME" && -n "$CERT_TYPE" ]]; then
                echo "🔹 Exporting certificate: $CERT_NAME  (Type: $CERT_TYPE)"
                exportSingleCertificate "$LOCAL_DEV_URL" "$admin_user" "$admin_password" "$repoName" "$CERT_NAME" "$CERT_TYPE"
            else
                echo "⚠️ Skipping invalid certificate entry (missing name or type)"
            fi
        done
    else
        echo "🔹 Exporting single certificate: $assetID  (Type: $CERT_TYPE)"
        exportSingleCertificate "$LOCAL_DEV_URL" "$admin_user" "$admin_password" "$repoName" "$assetID" "$CERT_TYPE"
    fi
}


function exportSingleCertificate() {
    LOCAL_DEV_URL=$1
    admin_user=$2
    admin_password=$3
    repoName=$4
    assetID=$5
    CERT_TYPE=$6

    echo "Running exportSingleCertificate with parameters:"
    echo "LOCAL_DEV_URL=$LOCAL_DEV_URL"
    echo "admin_user=$admin_user"
    echo "admin_password=****"
    echo "repoName=$repoName"
    echo "assetID=$assetID"
    echo "CERT_TYPE=$CERT_TYPE"
    
    SINGLE_Certificates_GET_URL="${LOCAL_DEV_URL}/apis/v1/rest/projects/${repoName}/configurations/certificates/${assetID}?certificateType=${CERT_TYPE}"

    singleCertificateJson=$(curl --silent --location --request GET "$SINGLE_Certificates_GET_URL" \
        --header 'Content-Type: application/json' \
        --header 'Accept: application/json' \
        -u "${admin_user}:${admin_password}")

    if [ -z "$singleCertificateJson" ] || [ "$singleCertificateJson" = "null" ]; then
        echo "⚠️ Skipping: No data for $assetID"
        return
    fi

    if echo "$singleCertificateJson" | jq empty 2>/dev/null; then
        output_dir="./assets/projectConfigs/certificates/${assetID}"
        mkdir -p "$output_dir"

        base_file="${output_dir}/${assetID}-${source_type}.json"
        echo "$singleCertificateJson" | jq '.' > "$base_file"
        echo "✅ Saved: $base_file"

        # replicate per env if provided
        if [ -n "${envTypes:-}" ]; then
          configPerEnv "$output_dir" "$envTypes" "certificate" "${assetID}-${source_type}.json" "$assetID"
        fi
    else
        echo "⚠️ Skipping invalid JSON for assetID: $assetID"
    fi
}


# Start execution
exportCertificatesList "$@"
