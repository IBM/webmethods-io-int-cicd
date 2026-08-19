#!/bin/bash

#############################################################################
#                                                                           #
# createProject.sh : Creates Project if does not exists                     #
#                                                                           #
#############################################################################

LOCAL_DEV_URL="$1"
admin_user="$2"
admin_password="$3"
repoName="$4"
inuid="$5"
dada_enabled="${6:-false}"
dada_git_account_alias="${7:-}"
dada_repository_url="${8:-}"
dada_branch="${9:-dev}"
instance_api_key="${10:-}"
debug="${@: -1}"

if [[ "$dada_enabled" != "true" ]]; then
  dada_enabled="false"
fi

# Normalize debug flag
if [[ "$debug" != "debug" && "$debug" != "trace" ]]; then
  debug=""
fi

# Validate required inputs
[ -z "$LOCAL_DEV_URL" ] && echo "Missing template parameter LOCAL_DEV_URL" >&2 && exit 1
[ -z "$admin_user" ] && echo "Missing template parameter admin_user" >&2 && exit 1
[ -z "$admin_password" ] && echo "Missing template parameter admin_password" >&2 && exit 1
[ -z "$repoName" ] && echo "Missing template parameter repoName" >&2 && exit 1

if [ "$dada_enabled" == "true" ]; then
  [ -z "$dada_git_account_alias" ] && echo "Missing DADA Git connection alias" >&2 && exit 1
  [ -z "$dada_repository_url" ] && echo "Missing DADA repository URL" >&2 && exit 1
  [ -z "$dada_branch" ] && echo "Missing DADA branch" >&2 && exit 1
fi

# Debug / Trace mode
if [ "$debug" == "trace" ]; then
  echo "......Running in Trace mode ......" >&2
  set -x
elif [ "$debug" == "debug" ]; then
  echo "......Running in Debug mode ......" >&2
fi

function echod() {
  if [ "$debug" == "debug" ] || [ "$debug" == "trace" ]; then
    echo "$@" >&2
  fi
}

PROJECT_URL="${LOCAL_DEV_URL}/apis/v1/rest/projects/${repoName}"

echod "Checking if project exists..."
response=$(curl --silent --location --request GET "$PROJECT_URL" \
  --header 'Accept: application/json' \
  -u "${admin_user}:${admin_password}")

uid=$(echo "$response" | jq -r '.output.uid // empty')
name=$(echo "$response" | jq -r '.output.name // empty')
        

if [ -n "$inuid" ]; then
  if [[ "$uid" == "$inuid" ]]; then
    echod "Project with "$uid "already exists"
  else
    if [ -n "$uid" ]; then
      echod "Project "$name" exists with different uid: "$uid
      exit 1
    fi
  fi
fi


if [ -z "$uid" ]; then
    # If REST API exports exist locally, let API import create the project
    rest_api_dir="${HOME_DIR:-.}/${repoName}/assets/rest_api"
    if [ -d "$rest_api_dir" ] && ls "$rest_api_dir"/*.zip >/dev/null 2>&1; then
      echod "Project not found, but REST API exports detected. Skipping explicit project creation; project will be created during API import."
      exit 0
    fi

    echod "Project does not exist. Creating..."  
    CREATE_URL="${LOCAL_DEV_URL}/apis/v1/rest/projects"

    if [ "$dada_enabled" == "true" ]; then
      echod "Creating DADA project with user Git connection alias '${dada_git_account_alias}'..."
      json=$(jq -n \
        --arg name "$repoName" \
        --arg gitAccountName "$dada_git_account_alias" \
        --arg pathToRepository "$dada_repository_url" \
        --arg branch "$dada_branch" \
        '{name: $name, description: "Created by Automated CI as a DADA project", externalGitDetails: {gitAccountName: $gitAccountName, pathToRepository: $pathToRepository, branch: $branch}, syncStorage: "git"}')
    elif [ -n "$inuid" ]; then
      echod "Creating with name & uid..."
      json=$(jq -n --arg name "$repoName" --arg uid "$inuid" \
        '{name: $name, uid: $uid, description: "Created by Automated CI for feature branch"}')
    else
      echod "Creating with only name..."
      json=$(jq -n --arg name "$repoName" \
        '{name: $name, description: "Created by Automated CI for feature branch"}')
    fi

    curl_headers=(
      --header 'Content-Type: application/json'
      --header 'Accept: application/json'
    )
    if [ -n "$instance_api_key" ]; then
      curl_headers+=(--header "x-instance-api-key: ${instance_api_key}")
    fi

    projectCreateResp=$(curl --silent --location --request POST "$CREATE_URL" \
      "${curl_headers[@]}" \
      --data-raw "$json" -u "${admin_user}:${admin_password}")

    uidcreated=$(echo "$projectCreateResp" | jq -r '.output.uid // empty')

    if [ -n "$uidcreated" ]; then
        echod "Project "$repoName "created successfully with uid: $uidcreated"
        echo "$uidcreated"   # ✅ Output only the name to stdout
    else
        echod "Project creation failed:"
        echod "$projectCreateResp"
        if [ "$dada_enabled" == "true" ]; then
          echod "Verify that private Git connection alias '${dada_git_account_alias}' exists for the initiating webMethods user and can access '${dada_repository_url}'."
        fi
        exit 1
    fi
else
    echod "Project already exists with name: $name"
    echo "$uid"  # ✅ Still echo the name if already exists
fi
