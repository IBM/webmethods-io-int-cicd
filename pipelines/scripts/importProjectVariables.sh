#!/bin/bash
set -euo pipefail

#################################################################################################################################################################
# Script Name: importProjectVariables.sh                                                                                                                              #
#                                                                                                                                                               #
# Summary:                                                                                                                                                      #
#   This script imports Project Variables configurations (single or bulk) into a                                                                                        #
#   webMethods.io project environment. It can handle both individual                                                                                            #
#   Project Variables imports (from `Project VariablessKeyList.json`) and bulk imports                                                                                          #
#   (from `Project VariablessList.json`).                                                                                                                               #
#                                                                                                                                                               #
# Usage:                                                                                                                                                        #
#   ./importProjectVariables.sh <LOCAL_DEV_URL> <admin_user> <admin_password> <repoName> <HOME_DIR> <assetID>                                                #
#                                                                                                                                                               #
# Example:                                                                                                                                                      #
#   ./importProjectVariables.sh \                                                                                                                                     #
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
#   assetID         - service name of the Project Variables                                                                              #
#################################################################################################################################################################

function echod() {
  echo "[DEBUG] $@"
}


# Import all Project Variables configurations in bulk
function importProjectVariables() {
  LOCAL_DEV_URL=$1
  admin_user=$2
  admin_password=$3
  repoName=$4
  HOME_DIR=$5

  cd "${HOME_DIR}/${repoName}" || exit 1

        output_dir="./assets/projectConfigs/ProjectVariable"
        mkdir -p "$output_dir"

        individual_file="$output_dir/${assetID}_ProjectVariable.json"

  if [ -f "$individual_file" ]; then
    echod "✅ Project Variables list found at: ${individual_file}"

    IMPORT_PROJECT_VARIABLES_URL="${LOCAL_DEV_URL}/apis/v1/rest/projects/${repoName}/configurations/variables?type=projectVariable"

    # Read JSON payload for bulk import
    ProjectVariablesJSON=$(jq -c '.output' "$individual_file")

    echod "📦 Project Variables JSON Payload: $ProjectVariablesJSON"

    # Perform the import via POST request
    ProjectVariablessImportJson=$(curl --silent --location --request POST "$IMPORT_PROJECT_VARIABLES_URL" \
      --header 'Content-Type: application/json' \
      --header 'Accept: application/json' \
      --data-raw "$ProjectVariablesJSON" \
      -u "${admin_user}:${admin_password}")

    ProjectVariablessImportCreatedJson=$(echo "$ProjectVariablessImportJson" | jq -r '.output // empty')

    if [ -z "$ProjectVariablessImportCreatedJson" ]; then
      echo "❌ Project Variables import failed. Response:"
      echo "ProjectVariablessImportCreatedJson"
      return 1
    else
      echo "✅ Successfully imported Project Variabless."
      echo "$ProjectVariablessImportCreatedJson"
    fi
  else
    echo "⚠️  Missing Project Variables file, skipping: ${individual_file}"
    return 0
  fi
}



# Start execution
importProjectVariables "$@"
