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
debug="${@: -1}"

# Normalize debug flag
if [[ "$debug" != "debug" && "$debug" != "trace" ]]; then
  debug=""
fi

# Validate required inputs
[ -z "$LOCAL_DEV_URL" ] && echo "Missing template parameter LOCAL_DEV_URL" >&2 && exit 1
[ -z "$admin_user" ] && echo "Missing template parameter admin_user" >&2 && exit 1
[ -z "$admin_password" ] && echo "Missing template parameter admin_password" >&2 && exit 1
[ -z "$repoName" ] && echo "Missing template parameter repoName" >&2 && exit 1

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
    echod "Project does not exist. Creating..."  
    CREATE_URL="${LOCAL_DEV_URL}/apis/v1/rest/projects"

    if [ -n "$inuid" ]; then
      echod "Creating with name & uid..."
      json='{ "name": "'"${repoName}"'", "uid": "'"${inuid}"'", "description": "Created by Automated CI for feature branch"}'
    else
      echod "Creating with only name..."
      json='{ "name": "'"${repoName}"'", "description": "Created by Automated CI for feature branch"}'
    fi

    projectCreateResp=$(curl --silent --location --request POST "$CREATE_URL" \
      --header 'Content-Type: application/json' \
      --header 'Accept: application/json' \
      --data-raw "$json" -u "${admin_user}:${admin_password}")

    uidcreated=$(echo "$projectCreateResp" | jq -r '.output.uid // empty')

    if [ -n "$uidcreated" ]; then
        echod "Project "$repoName "created successfully with uid: $uidcreated"
        echo "$uidcreated"   # ✅ Output only the name to stdout
    else
        echod "Project creation failed:"
        echod "$projectCreateResp"
        exit 1
    fi
else
    echod "Project already exists with name: $name"
    echo "$uid"  # ✅ Still echo the name if already exists
fi
