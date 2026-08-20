#!/bin/bash

#############################################################################
# Validate and resolve portable DADA initialization settings.               #
#############################################################################

repo_user="$1"
PAT="$2"
project_name="$3"
dada_enabled=$(echo "${4:-false}" | tr '[:upper:]' '[:lower:]')
dada_git_account_alias="${5:-}"
LOCAL_DEV_URL="${6:-}"
admin_user="${7:-}"
admin_password="${8:-}"
debug="${@: -1}"

for required in repo_user PAT project_name; do
  [ -z "${!required}" ] && echo "Missing template parameter ${required}" >&2 && exit 1
done

if [ "$dada_enabled" != "true" ]; then
  jq -n '{enabled: false, gitAccountAlias: "", repository: "", branch: "dev"}'
  exit 0
fi

if [ -z "$dada_git_account_alias" ]; then
  echo "DADA Git connection alias is required when DADA initialization is enabled." >&2
  exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dada_repository="${repo_user}/${project_name^}Project"

project_uid=""
if [ -n "$LOCAL_DEV_URL" ] && [ -n "$admin_user" ] && [ -n "$admin_password" ]; then
  project_response=$(curl --silent --location --request GET \
    "${LOCAL_DEV_URL}/apis/v1/rest/projects/${project_name}" \
    --header 'Accept: application/json' \
    --user "${admin_user}:${admin_password}")
  project_uid=$(echo "$project_response" | jq -r '.output.uid // empty')
fi

if [ -n "$project_uid" ]; then
  echo "Project '${project_name}' already exists; new-project DADA repository validation is not required." >&2
else
  if ! dada_repository=$("${script_dir}/github/validateDadaRepo.sh" \
    "$repo_user" "$PAT" "$project_name" "$debug"); then
    echo "DADA repository preparation failed. Repository initialization and project creation have been stopped." >&2
    exit 1
  fi
fi

jq -n \
  --arg alias "$dada_git_account_alias" \
  --arg repository "$dada_repository" \
  '{enabled: true, gitAccountAlias: $alias, repository: $repository, branch: "dev"}'
