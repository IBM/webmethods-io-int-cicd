#!/bin/bash

#############################################################################
# Validate and resolve portable external Git initialization settings.       #
#############################################################################

repo_user="$1"
PAT="$2"
project_name="$3"
external_git_enabled=$(echo "${4:-false}" | tr '[:upper:]' '[:lower:]')
external_git_account_alias="${5:-}"
external_git_branch="${6:-dev}"
LOCAL_DEV_URL="${7:-}"
admin_user="${8:-}"
admin_password="${9:-}"
debug="${@: -1}"

for required in repo_user PAT project_name; do
  [ -z "${!required}" ] && echo "Missing template parameter ${required}" >&2 && exit 1
done

if [ "$external_git_enabled" != "true" ]; then
  jq -n '{enabled: false, gitAccountAlias: "", physicalRepository: "", apiRepositoryPath: "", branch: "dev"}'
  exit 0
fi

if [ -z "$external_git_account_alias" ] || [ "$external_git_account_alias" = "NA" ]; then
  echo "External Git connection alias is required when external Git initialization is enabled." >&2
  exit 1
fi
[ -z "$external_git_branch" ] && echo "External Git branch is required when external Git initialization is enabled." >&2 && exit 1

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The product currently requires the first project character and "Project"
# suffix to be uppercase in its API path. Keep that workaround separate from
# the physical repository name created by validateExternalGitRepo.sh.
physical_repository="${repo_user}/${project_name}Project"
api_repository_path="${repo_user}/${project_name^}Project"

project_uid=""
if [ -n "$LOCAL_DEV_URL" ] && [ -n "$admin_user" ] && [ -n "$admin_password" ]; then
  project_response=$(curl --silent --location --request GET \
    "${LOCAL_DEV_URL}/apis/v1/rest/projects/${project_name}" \
    --header 'Accept: application/json' \
    --user "${admin_user}:${admin_password}")
  project_uid=$(echo "$project_response" | jq -r '.output.uid // empty')
fi

if [ -n "$project_uid" ]; then
  echo "Project '${project_name}' already exists; new external Git repository validation is not required." >&2
else
  if ! "${script_dir}/github/validateExternalGitRepo.sh" \
    "$repo_user" "$PAT" "$project_name" "$debug" >/dev/null; then
    echo "External Git repository preparation failed. Repository initialization and project creation have been stopped." >&2
    exit 1
  fi
fi

jq -n \
  --arg alias "$external_git_account_alias" \
  --arg physicalRepository "$physical_repository" \
  --arg apiRepositoryPath "$api_repository_path" \
  --arg branch "$external_git_branch" \
  '{enabled: true, gitAccountAlias: $alias, physicalRepository: $physicalRepository, apiRepositoryPath: $apiRepositoryPath, branch: $branch}'
