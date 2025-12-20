#!/bin/bash

#################################################################################################################################################################
# Script Name: exportSchedulersList.sh                                                                                                                          #
# Summary    : Exports all schedulers or a single scheduler configuration from                                                                                  #
#              a given webMethods.io project repository using REST APIs.                                                                                        #
#                                                                                                                                                               #
# Usage      : ./exportSchedulersList.sh <LOCAL_DEV_URL> <admin_user> <admin_password> <repoName> <HOME_DIR> <SINGLE_SCHEDULER>                                 #
#                                                                                                                                                               #
# Mandatory Fields:                                                                                                                                             #
#   LOCAL_DEV_URL   - The base URL of the target webMethods.io environment                                                                                      #
#   admin_user      - Administrator username for authentication                                                                                                 #
#   admin_password  - Administrator password for authentication                                                                                                 #
#   repoName        - Repository (project) name in webMethods.io                                                                                                #
#   HOME_DIR        - Local home directory path for storing exports                                                                                             #
#   SINGLE_SCHEDULER - true/false; when "true", exports individual scheduler configs                                                                            #
#                                                                                                                                                               #
# Example:                                                                                                                                                      #
#   ./exportSchedulersList.sh "https://mytenant.webmethods.io" "Administrator" "manage" "MyRepo" "/home/user/projects" true                                     #
#                                                                                                                                                               #
#################################################################################################################################################################


set -euo pipefail


echo "Starting exportSchedulersList.sh"
echo "Arguments: $@"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/configPerEnv.sh"

function echod() {
        echo "$@" >&2   
}


function exportSchedulersList() {
    LOCAL_DEV_URL=$1
    admin_user=$2
    admin_password=$3
    repoName=$4
    HOME_DIR=$5
    SINGLE_SCHEDULER=$6
    envTypes=${7:-}
    source_type=${8:-}
    debug=${@: -1}

    # Debug mode
    if [ "$debug" == "debug" ]; then
        echo "......Running in Debug mode ......" >&2
        set -x
    fi

    echo "Running exportSingleScheduler with parameters:"
    echo "LOCAL_DEV_URL=$LOCAL_DEV_URL"
    echo "admin_user=$admin_user"
    echo "admin_password=****"
    echo "repoName=$repoName"
    echo "HOME_DIR=$HOME_DIR"
    echo "SINGLE_SCHEDULER=$SINGLE_SCHEDULER"
    echo "envTypes=$envTypes"

    cd "${HOME_DIR}/${repoName}" || exit 1

    SCHEDULERS_GET_LIST_URL="${LOCAL_DEV_URL}/apis/v1/rest/projects/${repoName}/configurations/schedulers"

    # Call API to get scheduler list
    SchedulersListJson=$(curl --silent --location --request GET "$SCHEDULERS_GET_LIST_URL" \
        --header 'Content-Type: application/json' \
        --header 'Accept: application/json' \
        -u "${admin_user}:${admin_password}")

    # Extract service names (may be empty)
    mapfile -t schedulers < <(echo "$SchedulersListJson" | jq -r '.output[]?.serviceName // empty')

    SchedulersList_file="./assets/projectConfigs/schedules/SchedulersList.json"
    SchedulersKeyList_file="./assets/projectConfigs/schedules/SchedulersKeyList.json"

    if [ ${#schedulers[@]} -eq 0 ]; then
        echo "ℹ️ No schedulers found; skipping export."
        return 0
    else
        mkdir -p ./assets/projectConfigs/schedules
        echo "$SchedulersListJson" | jq '.' > "$SchedulersList_file"
        printf "%s\n" "${schedulers[@]}" > "$SchedulersKeyList_file"
        echo "✅ Schedulers list saved to: $SchedulersList_file"
        echo "✅ Scheduler keys saved to: $SchedulersKeyList_file"

        # echo "SINGLE_SCHEDULER = $SINGLE_SCHEDULER"
        # if [ "$SINGLE_SCHEDULER" == "true" ]; then
        #     echo "$SchedulersListJson" | jq -r '.output[].serviceName' > "$SchedulersKeyList_file"
        #     echo "✅ Scheduler keys saved to: $SchedulersKeyList_file"
        # fi
    fi

     exportSingleScheduler "$LOCAL_DEV_URL" "$admin_user" "$admin_password" "$repoName" "$SchedulersKeyList_file" "$SINGLE_SCHEDULER" "$envTypes" "$source_type" "$debug"

    cd "${HOME_DIR}/${repoName}" || exit 1
}

function exportSingleScheduler() {
    LOCAL_DEV_URL=$1
    admin_user=$2
    admin_password=$3
    repoName=$4
    SchedulersKeyList_file=$5
    SINGLE_SCHEDULER=$6
    envTypes=${7:-}
    source_type=${8:-}
    debug=${@: -1}

    echo "Running exportSingleScheduler with parameters:"
    echo "LOCAL_DEV_URL=$LOCAL_DEV_URL"
    echo "admin_user=$admin_user"
    echo "admin_password=****"
    echo "repoName=$repoName"
    echo "SchedulersKeyList_file=$SchedulersKeyList_file"
    echo "SINGLE_SCHEDULER=$SINGLE_SCHEDULER"

    output_base="./assets/projectConfigs/schedules"
    mkdir -p "$output_base"

    while IFS= read -r serviceName; do
        if [ -z "$serviceName" ]; then
            continue
        fi

        echo "Fetching Service Name: $serviceName"
        SINGLE_SCHEDULERS_GET_URL="${LOCAL_DEV_URL}/apis/v1/rest/projects/${repoName}/configurations/schedulers/${serviceName}"

        singleSchedulerJson=$(curl --silent --location --request GET "$SINGLE_SCHEDULERS_GET_URL" \
            --header 'Content-Type: application/json' \
            --header 'Accept: application/json' \
            -u "${admin_user}:${admin_password}")

        singleScheduleExport=$(echo "$singleSchedulerJson" | jq '.')

        if [ -z "$singleScheduleExport" ] || [ "$singleScheduleExport" == "null" ]; then
            echo "⚠️ Skipping: No data for $serviceName"
            continue
        fi

        if echo "$singleScheduleExport" | jq empty 2>/dev/null; then
            service_dir="${output_base}/${serviceName}"
            mkdir -p "$service_dir"
            base_file="${service_dir}/${serviceName}-${source_type}.json"
            echo "$singleScheduleExport" | jq '.' > "$base_file"
            echo "✅ Saved: $base_file"

            # Also keep a generic copy with the original name
            echo "$singleScheduleExport" | jq '.' > "${service_dir}/${serviceName}_scheduler.json"

            if [ -n "$envTypes" ]; then
              configPerEnv "$service_dir" "$envTypes" "scheduler" "${serviceName}-${source_type}.json" "$serviceName"
            fi
        else
            echo "⚠️ Skipping invalid JSON for service: $serviceName"
        fi

    done < "$SchedulersKeyList_file"
}

# Start execution
exportSchedulersList "$@"
