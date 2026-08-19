#!/bin/bash

#############################################################################
# Prepare a target project while preserving API-led creation for non-DADA.  #
#############################################################################

LOCAL_DEV_URL="$1"
admin_user="$2"
admin_password="$3"
project_name="$4"
automation_repo_dir="$5"
synch_project="$6"
project_has_apis="$7"
asset_type_list="$8"
debug="${@: -1}"

if [[ "$debug" != "debug" && "$debug" != "trace" ]]; then
  debug=""
fi

for required in LOCAL_DEV_URL admin_user admin_password project_name automation_repo_dir synch_project; do
  [ -z "${!required}" ] && echo "Missing template parameter ${required}" >&2 && exit 1
done

project_config="${automation_repo_dir}/project-config.yml"
if [ ! -f "$project_config" ]; then
  echo "Project configuration was not found: ${project_config}" >&2
  exit 1
fi
if ! yq e '.' "$project_config" >/dev/null 2>&1; then
  echo "Project configuration is not valid YAML: ${project_config}" >&2
  exit 1
fi

function echod() {
  if [[ "$debug" == "debug" || "$debug" == "trace" ]]; then
    echo "$@" >&2
  fi
}

# Undefined Azure variables arrive as their literal $(name) expression.
[[ "$project_has_apis" == "true" ]] || project_has_apis="false"
dada_enabled=$(yq e -r '.project.dada.enabled // false' "$project_config")
[[ "$dada_enabled" == "true" ]] || dada_enabled="false"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export HOME_DIR="$(dirname "$automation_repo_dir")"

if [ "$dada_enabled" = "true" ]; then
  dada_repository=$(yq e -r '.project.dada.repository // ""' "$project_config")
  dada_branch=$(yq e -r '.project.dada.branch // ""' "$project_config")
  dada_git_account_alias=$(yq e -r '.project.dada.git-account-alias // ""' "$project_config")

  [ -z "$dada_repository" ] && echo "Missing project.dada.repository in ${project_config}" >&2 && exit 1
  [ -z "$dada_branch" ] && echo "Missing project.dada.branch in ${project_config}" >&2 && exit 1
  [ -z "$dada_git_account_alias" ] && echo "Missing project.dada.git-account-alias in ${project_config}" >&2 && exit 1

  echod "Preparing DADA target project from destination-branch configuration."
  "$script_dir/createProject.sh" \
    "$LOCAL_DEV_URL" "$admin_user" "$admin_password" "$project_name" "" \
    true "$dada_git_account_alias" "$dada_repository" "$dada_branch" "" "$debug"
  exit $?
fi

# Preserve the existing behavior: during a complete regular-project sync,
# REST/SOAP API import is allowed to create the project itself.
assets_declare_apis="false"
asset_types_normalized=$(echo "$asset_type_list" | tr ',' '\n' | tr -d ' ')
if echo "$asset_types_normalized" | grep -E '^(rest_api|soap_api)$' >/dev/null 2>&1; then
  assets_declare_apis="true"
fi

if [[ "$synch_project" == "true" && ( "$project_has_apis" == "true" || "$assets_declare_apis" == "true" ) ]]; then
  echod "Skipping regular project creation because API import will create the project."
  exit 0
fi

existing_project_id=$(yq e -r '.project.project-id // ""' "$project_config")
echod "Preparing regular target project with exported project ID '${existing_project_id}'."
"$script_dir/createProject.sh" \
  "$LOCAL_DEV_URL" "$admin_user" "$admin_password" "$project_name" \
  "$existing_project_id" false "" "" "" "" "$debug"
