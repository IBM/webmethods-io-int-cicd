#!/bin/bash

#############################################################################
#                                                                           #
# storeSecret.sh : Stores the secret in GITHUB ACTION.                      #
#                                                                           #
#############################################################################

 secretName=$1
 secretValue=$2
 repo_user=$3
 repoName=$4
 PAT=$5
 HOME_DIR=$6
 debug=${@: -1}

if [[ "$debug" != "debug" && "$debug" != "trace" ]]; then
  debug=""
fi

# Validate required inputs
[ -z "$secretName" ] && echo "Missing template parameter secretName" >&2 && exit 1
[ -z "$secretValue" ] && echo "Missing template parameter secretValue" >&2 && exit 1
[ -z "$repo_user" ] && echo "Missing template parameter repo_user" >&2 && exit 1
[ -z "$repoName" ] && echo "Missing template parameter repoName" >&2 && exit 1
[ -z "$PAT" ] && echo "Missing template parameter PAT" >&2 && exit 1
[ -z "$HOME_DIR" ] && echo "Missing template parameter HOME_DIR" >&2 && exit 1


# Debug mode
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

  # Get public key (to encrypt secret)
  response=$(curl -s -H "Authorization: token ${PAT}" \
    -H "Accept: application/vnd.github+json" \
    https://api.github.com/repos/${repo_user}/${repoName}/actions/secrets/public-key)

  keyId=$(echo "$response" | jq -r '.key_id')
  keyValue=$(echo "$response" | jq -r '.key')

  if [[ -z "$keyId" || "$keyId" == "null" ]]; then
    echod"❌ Failed to retrieve repository public key."
    return 1
  fi

  # Encrypt the value using your Python script
   encryptedValue=$(python $HOME_DIR/self/pipelines/scripts/github/encryptGithubSecret.py "${keyValue}" "${secretValue}")
   
  # Construct the JSON payload
  secretJson=$(jq -n \
    --arg value "$encryptedValue" \
    --arg keyId "$keyId" \
    '{encrypted_value: $value, key_id: $keyId}')

  # Store the secret
  response=$(curl -s -o /dev/null -w "%{http_code}" \
    -X PUT \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    -u ${repo_user}:${PAT} \
    "https://api.github.com/repos/${repo_user}/${repoName}/actions/secrets/${secretName}" \
    -d "$secretJson")

  if [[ "$response" == "201" || "$response" == "204" ]]; then
    echod "✅ Secret '${secretName}' successfully stored in GitHub."
  else
    echod "❌ Failed to store secret '${secretName}'. HTTP status: $response"
  fi
