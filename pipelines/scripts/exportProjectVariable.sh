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
echo "Starting exportProjectVariable.sh"
echo "Arguments: $@"

function echod() {
        if [ "${debug:-}" == "debug" ] || [ "${debug:-}" == "trace" ]; then
                echo "$@" >&2
        fi
}



function exportProjectVariableList() {
    LOCAL_DEV_URL=$1
    admin_user=$2
    admin_password=$3
    repoName=$4
    HOME_DIR=$5
    assetID=$6
    envTypes=${7:-}
    source_type=${8:-}
    debug=${@: -1}

   

    echod "Running exportProjectVariableList with parameters:"
    echod "LOCAL_DEV_URL=$LOCAL_DEV_URL"
    echod "admin_user=$admin_user"
    echod "repoName=$repoName"
    echod "HOME_DIR=$HOME_DIR"
    echod "assetID=$assetID"
    

    cd "${HOME_DIR}/${repoName}" || exit 1

	if [ -z "$assetID" ] || [ "$assetID" = "null" ] || [ "$assetID" = "NA" ]; then
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

    mapfile -t pv_names < <(echo "$ProjectVariableListJson" | jq -r '.output[]?.name // empty')
    if [ ${#pv_names[@]} -eq 0 ]; then
        echo "ℹ️ No Project Variables found; skipping export."
        return
    fi

    output_dir="./assets/projectConfigs/projectVariables"
    mkdir -p "$output_dir"

    # Save full export
    export_file="$output_dir/ProjectVariable_List_Full.json"
    echo "$ProjectVariableListJson" | jq '.' > "$export_file"
    echo "✅ Full project variable list saved to: $export_file"

    for pv in "${pv_names[@]}"; do
      echod "Exporting project variable: $pv"
      exportProjectVariable "$LOCAL_DEV_URL" "$admin_user" "$admin_password" "$repoName" "$pv" "$envTypes" "$source_type" "$debug"
    done
	fi
    else
        exportProjectVariable "$LOCAL_DEV_URL" "$admin_user" "$admin_password" "$repoName" "$assetID" "$envTypes" "$source_type" "$debug"
    fi 
}

function exportProjectVariable() {
    LOCAL_DEV_URL=$1
    admin_user=$2
    admin_password=$3
    repoName=$4
    assetID=$5
    envTypes=${6:-}
    source_type=${7:-}
    debug=${@: -1}

    if [[ "$debug" != "debug" && "$debug" != "trace" ]]; then
        debug=""
    fi

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
        output_dir="./assets/projectConfigs/projectVariables/${assetID}"
        mkdir -p "$output_dir"

        base_file="${output_dir}/${assetID}-${source_type}.json"
        echo "$ProjectVariableJson" | jq '.' > "$base_file"
        echo "✅ Saved: $base_file"

        if [ -n "${envTypes:-}" ]; then
          configPerEnv "$output_dir" "$envTypes" "project_variable" "${assetID}-${source_type}.json" "$assetID"
        fi
    else
        echo "⚠️ Skipping invalid JSON for assetID: $assetID"
    fi
}

exportProjectVariableList "$@"
