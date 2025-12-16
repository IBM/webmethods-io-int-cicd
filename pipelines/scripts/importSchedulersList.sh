#!/bin/bash
set -euo pipefail

#################################################################################################################################################################
# Script Name: importSchedulers.sh                                                                                                                              #
#                                                                                                                                                               #
# Summary:                                                                                                                                                      #
#   This script imports scheduler configurations (single or bulk) into a                                                                                        #
#   webMethods.io project environment. It can handle both individual                                                                                            #
#   scheduler imports (from `SchedulersKeyList.json`) and bulk imports                                                                                          #
#   (from `SchedulersList.json`).                                                                                                                               #
#                                                                                                                                                               #
# Usage:                                                                                                                                                        #
#   ./importSchedulers.sh <LOCAL_DEV_URL> <admin_user> <admin_password> <repoName> <HOME_DIR> <SINGLE_SCHEDULER>                                                #
#                                                                                                                                                               #
# Example:                                                                                                                                                      #
#   ./importSchedulers.sh \                                                                                                                                     #
#     "http://localhost:5555" \                                                                                                                                 #
#     "Administrator" \                                                                                                                                         #
#     "manage" \                                                                                                                                                #
#     "myProjectRepo" \                                                                                                                                         #
#     "/home/user/projects" \                                                                                                                                   #
#     "true"                                                                                                                                                    #
#                                                                                                                                                               #
# Mandatory Fields:                                                                                                                                             #
#   LOCAL_DEV_URL      - Base URL of the local dev environment (e.g. http://localhost:5555)                                                                     #
#   admin_user         - Administrator username for authentication                                                                                              #
#   admin_password     - Administrator password for authentication                                                                                              #
#   repoName           - Name of the repository/project in HOME_DIR                                                                                             #
#   HOME_DIR           - Base directory containing the repo and assets                                                                                          #
#   SINGLE_SCHEDULER   - Flag ("true" or "false"):                                                                                                              #
#                          "true"  → Import schedulers one-by-one from SchedulersKeyList.json                                                                   #
#                          "false" → Bulk import schedulers from SchedulersList.json                                                                            #
#################################################################################################################################################################

function echod() {
  echo "[DEBUG] $@"
}

## Import multiple schedulers from list
# Import multiple schedulers from list
function importSingleScheduler() {
  LOCAL_DEV_URL=$1
  admin_user=$2
  admin_password=$3
  repoName=$4
  HOME_DIR=$5

  scheduler_file="${HOME_DIR}/${repoName}/assets/projectConfigs/Schedulers/SchedulersKeyList.json"

  if [ ! -f "$scheduler_file" ]; then
    echo "❌ Scheduler file not found: $scheduler_file"
    return 1
  fi

  echod "✅ Scheduler file found: ${scheduler_file}"

  # Detect if file is valid JSON
  if jq empty "$scheduler_file" 2>/dev/null; then
    # JSON array case
    mapfile -t schedulers < <(jq -r '.[]' "$scheduler_file")
  else
    # Plain text fallback
    mapfile -t schedulers < "$scheduler_file"
  fi

  if [ ${#schedulers[@]} -eq 0 ]; then
    echo "❌ No scheduler names found in $scheduler_file"
    return 1
  fi

  for SchedulerServiceName in "${schedulers[@]}"; do
    echod "📌 Processing scheduler: $SchedulerServiceName"

    CREATE_URL="${LOCAL_DEV_URL}/apis/v1/rest/projects/${repoName}/configurations/schedulers/${SchedulerServiceName}"
    single_scheduler_file="${HOME_DIR}/${repoName}/assets/projectConfigs/Schedulers/${SchedulerServiceName}_scheduler.json"

    if [ ! -f "$single_scheduler_file" ]; then
      echo "❌ Scheduler config not found: $single_scheduler_file"
      continue
    fi

    # Extract only the array [] from { "output": [...] }
    schedulerPayload=$(jq -c '.output' "$single_scheduler_file" 2>/dev/null)
    if [ -z "$schedulerPayload" ] || ! jq empty <<<"$schedulerPayload" 2>/dev/null; then
      echo "❌ Invalid payload in $single_scheduler_file"
      continue
    fi

   current_time=$(date +%s000)  # Unix time in milliseconds

# Get the scheduleType value
schedule_type=$(echo "$schedulerPayload" | jq -r '.scheduleType')

# Only modify if scheduleType is NOT "runOnce"
if [[ "$schedule_type" != "runOnce" ]]; then
  schedulerPayload=$(echo "$schedulerPayload" | jq \
    --argjson ct "$current_time" '
      if (.executionTime == [])
      then .executionTime = [$ct]
      else .
      end
    ')
fi

    echod "🛠 Final scheduler payload: $schedulerPayload"

    response=$(curl --silent --location --request POST "$CREATE_URL" \
      --header 'Content-Type: application/json' \
      --header 'Accept: application/json' \
      --data-raw "$schedulerPayload" \
      -u "${admin_user}:${admin_password}")

    createdCode=$(echo "$response" | jq -r '.output.code // empty')
    if [ "$createdCode" -eq 0 ] 2>/dev/null; then
      description=$(echo "$response" | jq -r '.output.description // empty')
      echo "✅ Created scheduler: $SchedulerServiceName ($description)"
    else
      echo "❌ Failed to create scheduler: $SchedulerServiceName"
      echo "   Response: $response"
    fi
  done
}



# Import all scheduler configurations in bulk
function importScheduler() {
  LOCAL_DEV_URL=$1
  admin_user=$2
  admin_password=$3
  repoName=$4
  HOME_DIR=$5
  SINGLE_SCHEDULER=$6

  cd "${HOME_DIR}/${repoName}" || exit 1

  scheduler_dir="./assets/projectConfigs/Schedulers"
  schedulersList_file="${scheduler_dir}/SchedulersList.json"

  if [ -f "$schedulersList_file" ]; then
    echod "✅ Schedulers list found at: ${schedulersList_file}"

    IMPORT_SCHEDULERS_URL="${LOCAL_DEV_URL}/apis/v1/rest/projects/${repoName}/configurations/schedulers"

    # Read JSON payload for bulk import
    SchedulersJSON=$(jq -c '.output' "$schedulersList_file")

    echod "📦 Schedulers JSON Payload: $SchedulersJSON"

    # Perform the import via PUT request
    SchedulersImportJson=$(curl --silent --location --request PUT "$IMPORT_SCHEDULERS_URL" \
      --header 'Content-Type: application/json' \
      --header 'Accept: application/json' \
      --data-raw "$SchedulersJSON" \
      -u "${admin_user}:${admin_password}")

    SchedulersImportCreatedJson=$(echo "$SchedulersImportJson" | jq -r '.output // empty')

    if [ -z "$SchedulersImportCreatedJson" ]; then
      echo "❌ Scheduler import failed. Response:"
      echo "$SchedulersImportJson"
      return 1
    else
      echo "✅ Successfully imported schedulers."
      echo "$SchedulersImportCreatedJson"
    fi
  else
    echo "❌ Missing schedulers file: ${schedulersList_file}"
    return 1
  fi
}


# Main import entry point
function projectImportschedulers() {
  LOCAL_DEV_URL=$1
  admin_user=$2
  admin_password=$3
  repoName=$4
  HOME_DIR=$5
  SINGLE_SCHEDULER=$6

  scheduler_dir="${HOME_DIR}/${repoName}/assets/projectConfigs/Schedulers"

  if [ ! -d "$scheduler_dir" ]; then
    echo "❌ Scheduler config folder not found at: $scheduler_dir"
    return 1
  fi

  if [ "$SINGLE_SCHEDULER" == "true" ]; then
    importSingleScheduler "$LOCAL_DEV_URL" "$admin_user" "$admin_password" "$repoName" "$HOME_DIR" "$SINGLE_SCHEDULER"
  else
    importScheduler "$LOCAL_DEV_URL" "$admin_user" "$admin_password" "$repoName" "$HOME_DIR" "$SINGLE_SCHEDULER"
  fi
}

# Start execution
projectImportschedulers "$@"