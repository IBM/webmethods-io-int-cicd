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
project_existed="${11:-false}"
repo_existed="${12:-false}"
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
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_config_updater="${script_dir}/../updateProjectConfig.sh"

has_external_git_flag=$(yq '.project."external-git" | has("enabled")' "$config_file")
existing_external_git=$(yq '.project."external-git".enabled' "$config_file")
existing_legacy_dada=$(yq '.project.dada.enabled // false' "$config_file")
trusted_external_git=false

# Repositories initialized before the external-git naming change store the
# same trusted association under project.dada. Honour that metadata only when
# the replacement external-git flag is absent; an explicit false must win.
if [ "$existing_external_git" = "true" ] || { [ "$has_external_git_flag" != "true" ] && [ "$existing_legacy_dada" = "true" ]; }; then
  trusted_external_git=true
fi

if [ "$external_git_enabled" = "true" ] && { [ "$project_existed" != "true" ] || { [ "$repo_existed" = "true" ] && [ "$trusted_external_git" = "true" ]; }; }; then
  bash "$project_config_updater" "$config_file" "$repo_name" "$project_id" true \
    "$external_git_repository" "$external_git_api_repository_path" \
    "$external_git_branch" "$external_git_account_alias" || exit $?
elif [ "$external_git_enabled" = "true" ]; then
  bash "$project_config_updater" "$config_file" "$repo_name" "$project_id" false || exit $?
  echo "Project already existed without trusted external Git metadata; conversion was not performed." >&2
else
  bash "$project_config_updater" "$config_file" "$repo_name" "$project_id" false || exit $?
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
