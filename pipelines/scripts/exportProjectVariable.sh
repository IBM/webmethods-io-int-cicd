#!/bin/bash

#################################################################################################################################################################
# Summary:                                                                                                                                                      #
#   Exports project variable details from a given repository in the local development environment.                                                         #
#   The script retrieves the project variable list via API and saves it locally in JSON files.                                                             #
#   It stores both the full export and specific sections (packages, variables, connections, certificates,                                                       #
#   schedules, alert rules, and version control accounts).                                                                                                      #
#                                                                                                                                                               #
# Usage:                                                                                                                                                        #
#   ./exportProjectVariable.sh <LOCAL_DEV_URL> <admin_user> <admin_password> <repoName> <HOME_DIR>                                                         #
#                                                                                                                                                               #
# Mandatory Fields:                                                                                                                                             #
#   LOCAL_DEV_URL   - Base URL of the local dev environment (e.g., http://localhost:5555)                                                                       #
#   admin_user      - Admin username for authentication                                                                                                         #
#   admin_password  - Admin password for authentication                                                                                                         #
#   repoName        - Name of the repository/project from which to export variables                                                                        #
#   HOME_DIR        - Path to the base working directory where exported files will be stored                                                                    #
#################################################################################################################################################################


set -x
echo "Starting exportProjectVariable.sh"
echo "Arguments: $@"

function echod() {
        echo "$@" >&2   
}



function exportProjectVariableList() {
    LOCAL_DEV_URL=$1
    admin_user=$2
    admin_password=$3
    repoName=$4
    HOME_DIR=$5
    assetID=$6
    debug=${@: -1}

    # Debug mode
    if [ "$debug" == "debug" ]; then
        echo "......Running in Debug mode ......" >&2
        set -x
    fi

   

    echod "Running exportProjectVariableList with parameters:"
    echod "LOCAL_DEV_URL=$LOCAL_DEV_URL"
    echod "admin_user=$admin_user"
    echod "repoName=$repoName"
    echod "HOME_DIR=$HOME_DIR"
    echod "assetID=$assetID"
    

    cd "${HOME_DIR}/${repoName}" || exit 1

	if [ -z "$assetID" ] || [ "$assetID" = "null" ]; then
    PROJECT_VARIABLE_EXPORT_LIST_URL="${LOCAL_DEV_URL}/apis/v2/rest/projects/${repoName}/configurations/variables?type=ProjectVariable"

    # Call API to get Project variable list
    ProjectVariableListJson=$(curl --silent --location --request GET "${PROJECT_VARIABLE_EXPORT_LIST_URL}" \
        --header 'Content-Type: application/json' \
        --header 'Accept: application/json' \
        -u "${admin_user}:${admin_password}")

    # Validate response
    if [ -z "$ProjectVariableListJson" ] || [ "$ProjectVariableListJson" == "null" ]; then
        echo "❌ No Project variables retrieved."
        echod "$ProjectVariableListJson"
        return
    fi

    # Pretty print for local storage
    ProjectVariableListExport=$(echo "$ProjectVariableListJson" | jq '.')

    output_dir="./assets/projectConfigs/ProjectVariable"
    mkdir -p "$output_dir"

    # Save full export
    export_file="$output_dir/ProjectVariable_List_Full.json"
    echo "$ProjectVariableListExport" > "$export_file"
    echo "✅ Full project variable list saved to: $export_file"
	fi
    else
        exportProjectVariable "$LOCAL_DEV_URL" "$admin_user" "$admin_password" "$repoName" "$assetID"
    fi 
}

function exportProjectVariable() {
    LOCAL_DEV_URL=$1
    admin_user=$2
    admin_password=$3
    repoName=$4
    assetID=$5

    echod "Running exportProjectVariable with parameters:"
    echod "LOCAL_DEV_URL=$LOCAL_DEV_URL"
    echod "admin_user=$admin_user"
    echod "admin_password=****"
    echod "repoName=$repoName"
    echod "assetID=$assetID"
    
    SINGLE_PROJECT_VARIABLE_GET_URL="${LOCAL_DEV_URL}/apis/v2/rest/projects/${repoName}/configurations/variables/${assetID}?type=projectVariable"

    ProjectVariableJson=$(curl --silent --location --request GET "$SINGLE_PROJECT_VARIABLE_GET_URL" \
        --header 'Content-Type: application/json' \
        --header 'Accept: application/json' \
        -u "${admin_user}:${admin_password}")

    if [ -z "$ProjectVariableJson" ] || [ "$ProjectVariableJson" = "null" ]; then
        echo "⚠️ Skipping: No data for $assetID"
        return
    fi

    if echo "$ProjectVariableJson" | jq empty 2>/dev/null; then
        output_dir="./assets/projectConfigs/ProjectVariable"
        mkdir -p "$output_dir"

        individual_file="$output_dir/${assetID}_ProjectVariable.json"
        echo "$ProjectVariableJson" | jq '.' > "$individual_file"
        echo "✅ Saved: $individual_file"
    else
        echo "⚠️ Skipping invalid JSON for assetID: $assetID"
    fi
}

exportProjectVariableList "$@"
