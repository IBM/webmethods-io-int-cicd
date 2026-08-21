#!/bin/bash

#############################################################################
# Persist project and optional external Git metadata, then commit it once.   #
#############################################################################

repo_name="$1"
project_id="$2"
home_dir="$3"
dev_user="$4"
feature_branch="$5"
external_git_enabled="${6:-false}"
external_git_repository="${7:-}"
external_git_api_repository_path="${8:-}"
external_git_branch="${9:-dev}"
external_git_account_alias="${10:-}"
debug="${@: -1}"

for required in repo_name project_id home_dir dev_user feature_branch; do
  [ -z "${!required}" ] && echo "Missing template parameter ${required}" >&2 && exit 1
done

if [ "$external_git_enabled" = "true" ]; then
  [ -z "$external_git_repository" ] && echo "Missing external Git repository" >&2 && exit 1
  [ -z "$external_git_api_repository_path" ] && echo "Missing external Git API repository path" >&2 && exit 1
  [ -z "$external_git_branch" ] && echo "Missing external Git branch" >&2 && exit 1
  [ -z "$external_git_account_alias" ] && echo "Missing external Git connection alias" >&2 && exit 1
fi

repo_dir="${home_dir}/${repo_name}"
config_file="${repo_dir}/project-config.yml"
mkdir -p "$repo_dir"
touch "$config_file"

PROJECT_ID="$project_id" PROJECT_NAME="$repo_name" yq -i '
  .project."project-id" = strenv(PROJECT_ID) |
  .project."project-name" = strenv(PROJECT_NAME)
' "$config_file"

if [ "$external_git_enabled" = "true" ]; then
  EXTERNAL_GIT_REPOSITORY="$external_git_repository" \
  EXTERNAL_GIT_API_REPOSITORY_PATH="$external_git_api_repository_path" \
  EXTERNAL_GIT_BRANCH="$external_git_branch" \
  EXTERNAL_GIT_ACCOUNT_ALIAS="$external_git_account_alias" \
  yq -i '
    .project."external-git".enabled = true |
    .project."external-git".repository = strenv(EXTERNAL_GIT_REPOSITORY) |
    .project."external-git"."api-repository-path" = strenv(EXTERNAL_GIT_API_REPOSITORY_PATH) |
    .project."external-git".branch = strenv(EXTERNAL_GIT_BRANCH) |
    .project."external-git"."account-alias" = strenv(EXTERNAL_GIT_ACCOUNT_ALIAS) |
    del(.project.dada)
  ' "$config_file"
fi

cd "$repo_dir"
git config user.email "noemail.com"
git config user.name "$dev_user"
git add project-config.yml
if git diff --cached --quiet; then
  [ -n "$debug" ] && echo "Project configuration is already current." >&2
  exit 0
fi
git commit -m "Initialize: push the project config to repository."
git push origin "HEAD:${feature_branch}"
