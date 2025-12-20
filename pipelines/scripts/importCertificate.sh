#!/bin/bash
set -euo pipefail

#################################################################################################################################################################
# Script Name: importCertificate.sh                                                                                                                              #
#                                                                                                                                                               #
# Summary:                                                                                                                                                      #
#   This script imports Certificate configurations (single or bulk) into a                                                                                        #
#   webMethods.io project environment. It can handle both individual                                                                                            #
#   Certificate imports (from `CertificatesKeyList.json`) and bulk imports                                                                                          #
#   (from `CertificatesList.json`).                                                                                                                               #
#                                                                                                                                                               #
# Usage:                                                                                                                                                        #
#   ./importCertificate.sh <LOCAL_DEV_URL> <admin_user> <admin_password> <repoName> <HOME_DIR> <assetID>                                                #
#                                                                                                                                                               #
# Example:                                                                                                                                                      #
#   ./importCertificate.sh \                                                                                                                                     #
#     "http://localhost:5555" \                                                                                                                                 #
#     "Administrator" \                                                                                                                                         #
#     "manage" \                                                                                                                                                #
#     "myProjectRepo" \                                                                                                                                         #
#     "/home/user/projects" \                                                                                                                                   #
#     "dwd"                                                                                                                                                    #
#                                                                                                                                                               #
# Mandatory Fields:                                                                                                                                             #
#   LOCAL_DEV_URL      - Base URL of the local dev environment (e.g. http://localhost:5555)                                                                     #
#   admin_user         - Administrator username for authentication                                                                                              #
#   admin_password     - Administrator password for authentication                                                                                              #
#   repoName           - Name of the repository/project in HOME_DIR                                                                                             #
#   HOME_DIR           - Base directory containing the repo and assets                                                                                          #
#   assetID            - service name of the Certificate                                                                              #
#################################################################################################################################################################

function echod() {
        echo "$@" >&2   
}



# Import all Certificate configurations in bulk
function importCertificate() {
  LOCAL_DEV_URL=$1
  admin_user=$2
  admin_password=$3
  repoName=$4
  HOME_DIR=$5
  assetID=$6
  debug=${@: -1}

  if [ "${debug}" == "debug" ]; then
    echo "......Running in Debug mode ......" >&2
    set -x
  fi

  cd "${HOME_DIR}/${repoName}" || exit 1

    output_dir="./assets/projectConfigs/Certificates"
    mkdir -p "$output_dir"

    individual_file="$output_dir/${assetID}_Certificate.json"

  if [ -f "$individual_file" ]; then
    echod "✅ Certificate list found at: ${individual_file}"

    IMPORT_PROJECT_VARIABLES_URL="${LOCAL_DEV_URL}/apis/v1/rest/projects/${repoName}/configurations/certificates"

    # Read JSON payload for import
    CertificateJSON=$(jq -c '.output' "$individual_file")

    echod "📦 Certificate JSON Payload: $CertificateJSON"

    # Perform the import via POST request
    CertificatesImportJson=$(curl --silent --location --request POST "$IMPORT_PROJECT_VARIABLES_URL" \
      --header 'Content-Type: application/json' \
      --header 'Accept: application/json' \
      --data-raw "$CertificateJSON" \
      -u "${admin_user}:${admin_password}")

    CertificatesImportCreatedJson=$(echo "$CertificatesImportJson" | jq -r '.output // empty')

    if [ -z "$CertificatesImportCreatedJson" ]; then
      echo "❌ Certificate import failed. Response:"
      echo "CertificatesImportCreatedJson"
      return 1
    else
      echo "✅ Successfully imported Certificates."
      echo "$CertificatesImportCreatedJson"
    fi
  else
    echo "⚠️  Missing Certificate file, skipping: ${individual_file}"
    return 0
  fi
}



# Start execution
importCertificate "$@"
