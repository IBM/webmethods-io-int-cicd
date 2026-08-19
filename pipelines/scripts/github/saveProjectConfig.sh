#!/bin/bash

#############################################################################
# Persist project and optional DADA metadata, then commit it once.           #
#############################################################################

repo_name="$1"
project_id="$2"
home_dir="$3"
dev_user="$4"
feature_branch="$5"
dada_enabled="${6:-false}"
dada_repository="${7:-}"
dada_branch="${8:-dev}"
dada_git_account_alias="${9:-}"
debug="${@: -1}"

for required in repo_name project_id home_dir dev_user feature_branch; do
  [ -z "${!required}" ] && echo "Missing template parameter ${required}" >&2 && exit 1
done

if [ "$dada_enabled" = "true" ]; then
  [ -z "$dada_repository" ] && echo "Missing DADA repository" >&2 && exit 1
  [ -z "$dada_branch" ] && echo "Missing DADA branch" >&2 && exit 1
  [ -z "$dada_git_account_alias" ] && echo "Missing DADA Git connection alias" >&2 && exit 1
fi

repo_dir="${home_dir}/${repo_name}"
config_file="${repo_dir}/project-config.yml"
mkdir -p "$repo_dir"
touch "$config_file"

PROJECT_ID="$project_id" PROJECT_NAME="$repo_name" DADA_ENABLED="$dada_enabled" \
DADA_REPOSITORY="$dada_repository" DADA_BRANCH="$dada_branch" \
DADA_GIT_ACCOUNT_ALIAS="$dada_git_account_alias" \
yq -i '
  .project."project-id" = strenv(PROJECT_ID) |
  .project."project-name" = strenv(PROJECT_NAME) |
  .project.dada.enabled = (strenv(DADA_ENABLED) == "true") |
  .project.dada.repository = strenv(DADA_REPOSITORY) |
  .project.dada.branch = strenv(DADA_BRANCH) |
  .project.dada."git-account-alias" = strenv(DADA_GIT_ACCOUNT_ALIAS)
' "$config_file"

if [ "$dada_enabled" != "true" ]; then
  yq -i 'del(.project.dada.repository, .project.dada.branch, .project.dada."git-account-alias")' "$config_file"
fi

cd "$repo_dir"
git config user.email "noemail.com"
git config user.name "$dev_user"
git add project-config.yml
git commit -m "Initialize: push the project config to repository."
git push origin "HEAD:${feature_branch}"

