#!/bin/bash

#############################################################################
# Reconcile framework-owned project metadata for Initialize and Export.      #
#############################################################################

config_file="$1"
project_name="$2"
project_id="$3"
external_git_enabled="${4:-false}"
external_git_repository="${5:-}"
external_git_api_repository_path="${6:-}"
external_git_branch="${7:-}"
external_git_account_alias="${8:-}"

for required in config_file project_name project_id; do
  [ -z "${!required}" ] && echo "Missing template parameter ${required}" >&2 && exit 1
done

if [ "$external_git_enabled" != "true" ] && [ "$external_git_enabled" != "false" ]; then
  echo "external_git_enabled must be true or false." >&2
  exit 1
fi

if [ "$external_git_enabled" = "true" ]; then
  for required in external_git_repository external_git_api_repository_path external_git_branch external_git_account_alias; do
    [ -z "${!required}" ] && echo "Missing external Git metadata: ${required}" >&2 && exit 1
  done
fi

mkdir -p "$(dirname "$config_file")"
touch "$config_file"

PROJECT_ID="$project_id" PROJECT_NAME="$project_name" \
EXTERNAL_GIT_ENABLED="$external_git_enabled" \
yq -i '
  .project."project-id" = strenv(PROJECT_ID) |
  .project."project-name" = strenv(PROJECT_NAME) |
  .project."external-git".enabled = (strenv(EXTERNAL_GIT_ENABLED) == "true") |
  del(.project.dada)
' "$config_file" || exit $?

if [ "$external_git_enabled" = "true" ]; then
  EXTERNAL_GIT_REPOSITORY="$external_git_repository" \
  EXTERNAL_GIT_API_REPOSITORY_PATH="$external_git_api_repository_path" \
  EXTERNAL_GIT_BRANCH="$external_git_branch" \
  EXTERNAL_GIT_ACCOUNT_ALIAS="$external_git_account_alias" \
  yq -i '
    .project."external-git".repository = strenv(EXTERNAL_GIT_REPOSITORY) |
    .project."external-git"."api-repository-path" = strenv(EXTERNAL_GIT_API_REPOSITORY_PATH) |
    .project."external-git".branch = strenv(EXTERNAL_GIT_BRANCH) |
    .project."external-git"."account-alias" = strenv(EXTERNAL_GIT_ACCOUNT_ALIAS)
  ' "$config_file" || exit $?
else
  yq -i '
    del(.project."external-git".repository,
        .project."external-git"."api-repository-path",
        .project."external-git".branch,
        .project."external-git"."account-alias")
  ' "$config_file" || exit $?
fi
