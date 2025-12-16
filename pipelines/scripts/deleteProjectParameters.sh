#!/bin/bash

####################################################################################################################################################################
#                                                                                                                                                                  #
#  deleteProjectParameter.sh : Delete project parameters from a webMethods.io Project                                                                              #
#                                                                                                                                                                  #
#  FUNCTIONS:                                                                                                                                                      #
#   - deleteProjectParameter : Deletes a single project parameter by name.                                                                                         #
#   - extractProjectParameters : Batch-deletes project parameters by reading them from a file (line by line).                                                      #
#                                                                                                                                                                  #
#  MANDATORY PARAMETERS:                                                                                                                                           #
#   LOCAL_DEV_URL          : Base URL of the Tenant (e.g., http://localhost:5555)                                                                                  #
#   admin_user             : Admin username for authentication                                                                                                     #
#   admin_password         : Admin password for authentication                                                                                                     #
#   projectParameter       : The project parameter name to delete (used in single delete)                                                                          #
#   repo_name              : Name of the project/repository where parameters exist                                                                                 #
#   project_param_file     : File containing a list of project parameter names (one per line, used in batch delete)                                                 #
#                                                                                                                                                                  #
#  USAGE EXAMPLES:                                                                                                                                                 #
#   Delete a single project parameter:                                                                                                                             #
#     ./deleteProjectParameter.sh "http://localhost:5555" "admin" "password" "ParamName" "MyRepo"                                                                  #
#                                                                                                                                                                  #
#   Delete multiple project parameters from file:                                                                                                                  #
#     ./deleteProjectParameter.sh "http://localhost:5555" "admin" "password" "./projectParams.txt" "MyRepo"                                                        #
#                                                                                                                                                                  #
####################################################################################################################################################################


# Debug echo
function echod() {
  echo "[DEBUG] $@"
}

# Function to delete a single Project Parameter entry
function deleteProjectParameter() {
  LOCAL_DEV_URL=$1
  admin_user=$2
  admin_password=$3
  assetID=$4
  repo_name=$5

  if [ -z "$assetID" ]; then
    echo "❌ Project Parameter name not provided!"
    exit 1
  fi

  PROJECT_PARAMETER_DELETE_URL="${LOCAL_DEV_URL}/apis/v1/rest/projects/${repo_name}/projectParameter/${assetID}"
  echod "Deleting Project Parameter: $assetID"
  echod "API URL: $PROJECT_PARAMETER_DELETE_URL"

  response=$(curl --silent --location --request DELETE "$PROJECT_PARAMETER_DELETE_URL" \
    --header 'Content-Type: application/json' \
    --header 'Accept: application/json' \
    -u "${admin_user}:${admin_password}")

  status=$(echo "$response" | jq -r '.output.code // empty')

  if [ "$status" == "SUCCESS" ]; then
    echo "✅ Project Parameter '$projectParameter' deleted successfully."
  else
    echo "❌ Failed to delete Project Parameter '$projectParameter'"
    echo "Response: $response"
  fi
}

# Function to read Project Parameter names from a file and delete them
function extractProjectParameters() {
  LOCAL_DEV_URL=$1
  admin_user=$2
  admin_password=$3
  project_param_file=$4
  repo_name=$5
  assetID=$6

  # If project_param_file is provided, read from file
  if [ -n "$project_param_file" ] && [ -f "$project_param_file" ]; then
    echo "📄 Reading Project Parameters from file: $project_param_file"
    while IFS= read -r projectParameter || [ -n "$projectParameter" ]; do
      # Skip empty lines or comments
      if [[ -n "$projectParameter" && ! "$projectParameter" =~ ^# ]]; then
        deleteProjectParameter "$LOCAL_DEV_URL" "$admin_user" "$admin_password" "$projectParameter" "$repo_name"
      fi
    done < "$project_param_file"
  # Otherwise, check if assetID is provided and use it directly
  elif [ -n "$assetID" ]; then
    deleteProjectParameter "$LOCAL_DEV_URL" "$admin_user" "$admin_password" "$assetID" "$repo_name"
  else
    echo "❌ Either project_param_file or assetID must be provided!"
    return 1
  fi
}

deleteProjectParameter "$@"