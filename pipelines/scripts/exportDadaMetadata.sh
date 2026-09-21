#!/bin/bash

################################################################################
# Reconcile project mode and export imported-package metadata for either Git mode. #
################################################################################

LOCAL_DEV_URL="$1"
admin_user="$2"
admin_password="$3"
project_name="$4"
automation_repo_dir="$5"
repo_user="$6"
PAT="$7"
environment_config_dir="${8:-}"
debug="${9:-}"

if [[ "$environment_config_dir" == "debug" || "$environment_config_dir" == "trace" ]]; then
  debug="$environment_config_dir"
  environment_config_dir=""
fi
[[ "$debug" != "debug" && "$debug" != "trace" ]] && debug=""

for required in LOCAL_DEV_URL admin_user admin_password project_name automation_repo_dir repo_user PAT; do
  [ -z "${!required}" ] && echo "Missing template parameter ${required}" >&2 && exit 1
done

function echod() {
  [[ "$debug" == "debug" || "$debug" == "trace" ]] && echo "$@" >&2
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_config="${automation_repo_dir}/project-config.yml"
config_root="${automation_repo_dir}/assets/dada/config"
scaffolding_destination="${config_root}/scaffolding"
package_metadata="${config_root}/imported-package-metadata.yml"
branch_mapping="${config_root}/imported-package-branches.yml"
exported_project_config="${automation_repo_dir}/assets/projectConfigs/ProjectConfiguration/ProjectConfiguration_List_Full.json"
response_file=$(mktemp)
repo_response_file=$(mktemp)
temp_dir=$(mktemp -d)
trap 'rm -f "$response_file" "$repo_response_file"; rm -rf "$temp_dir"' EXIT

[ ! -f "$project_config" ] && echo "Project configuration file does not exist: ${project_config}" >&2 && exit 1

if [ -f "$exported_project_config" ] && \
   jq -e '.configurations | type == "object"' "$exported_project_config" >/dev/null 2>&1; then
  echod "Reusing exported project configuration from ${exported_project_config}."
  jq '.configurations.packages //= []' "$exported_project_config" > "$response_file"
else
  config_url="${LOCAL_DEV_URL}/apis/v2/rest/projects/${project_name}/configurations"
  http_status=$(curl --silent --show-error --location \
    --output "$response_file" --write-out '%{http_code}' \
    --header 'Accept: application/json' \
    --user "${admin_user}:${admin_password}" \
    "$config_url") || {
      echo "Failed to query project configurations for '${project_name}'." >&2
      exit 1
    }

  if [[ "$http_status" =~ ^2[0-9][0-9]$ ]] && \
     jq -e '.configurations | type == "object"' "$response_file" >/dev/null 2>&1; then
    normalized_response=$(mktemp)
    jq '.configurations.packages //= []' "$response_file" > "$normalized_response" && \
      mv "$normalized_response" "$response_file"
  else
    echod "Full project configuration was unavailable (HTTP ${http_status}); querying imported packages directly."
    packages_url="${LOCAL_DEV_URL}/apis/v1/rest/projects/${project_name}/configurations/packages"
    packages_status=$(curl --silent --show-error --location \
      --output "$response_file" --write-out '%{http_code}' \
      --header 'Accept: application/json' \
      --user "${admin_user}:${admin_password}" \
      "$packages_url") || {
        echo "Failed to query imported packages for '${project_name}'." >&2
        exit 1
      }
    if [[ ! "$packages_status" =~ ^2[0-9][0-9]$ ]] || \
       ! jq -e '(.output == null) or (.output | type == "array")' "$response_file" >/dev/null 2>&1; then
      echo "Imported packages API failed with HTTP ${packages_status}: $(cat "$response_file")" >&2
      exit 1
    fi
    normalized_response=$(mktemp)
    jq '{configurations: {packages: (.output // [])}}' "$response_file" > "$normalized_response" && \
      mv "$normalized_response" "$response_file"
  fi
fi
if ! jq -e '.configurations.packages | type == "array"' "$response_file" >/dev/null 2>&1; then
  echo "Project configuration response does not contain a configurations.packages array." >&2
  exit 1
fi

project_id=$(jq -r '.metadata.project // empty' "$response_file")
[ -z "$project_id" ] && project_id=$(yq e '.project."project-id" // ""' "$project_config")
[ -z "$project_id" ] && echo "Unable to determine the project ID for '${project_name}'." >&2 && exit 1

has_external_mode=$(yq e '.project."external-git" | has("enabled")' "$project_config")
if [ "$has_external_mode" = "true" ]; then
  external_mode=$(yq e '.project."external-git".enabled' "$project_config")
else
  external_mode=$(yq e '.project.dada.enabled // ""' "$project_config")
fi
dada_repository=$(yq e '.project."external-git".repository // .project.dada.repository // ""' "$project_config")
dada_api_repository_path=$(yq e '.project."external-git"."api-repository-path" // .project.dada.repository // ""' "$project_config")
dada_branch=$(yq e '.project."external-git".branch // .project.dada.branch // ""' "$project_config")
dada_account_alias=$(yq e '.project."external-git"."account-alias" // .project.dada."git-account-alias" // ""' "$project_config")

conventional_repo_name="${project_name}Project"
[ -z "$dada_repository" ] && dada_repository="${repo_user}/${conventional_repo_name}"
project_name_initial=$(printf '%s' "$project_name" | cut -c1 | tr '[:lower:]' '[:upper:]')
project_name_rest=$(printf '%s' "$project_name" | cut -c2-)
[ -z "$dada_api_repository_path" ] && dada_api_repository_path="${repo_user}/${project_name_initial}${project_name_rest}Project"
[ -z "$dada_branch" ] && dada_branch="dev"
scaffolding_name="${dada_api_repository_path##*/}"

# Old projects may not contain mode metadata. Repository existence is not enough
# to identify external Git because Initialize may have created an empty Project
# repository. The product-owned scaffolding file is the authoritative indicator.
if [[ "$external_mode" != "true" && "$external_mode" != "false" ]]; then
  scaffolding_api_url="https://api.github.com/repos/${dada_repository}/contents/config/scaffolding/${scaffolding_name}.yml?ref=${dada_branch}"
  scaffolding_status=$(curl --silent --show-error --location \
    --output "$repo_response_file" --write-out '%{http_code}' \
    --header 'Accept: application/vnd.github+json' \
    --header "Authorization: Bearer ${PAT}" \
    "$scaffolding_api_url") || {
      echo "Unable to determine whether '${project_name}' uses external Git." >&2
      exit 1
    }
  case "$scaffolding_status" in
    200) external_mode="true" ;;
    404) external_mode="false" ;;
    *)
      echo "External Git scaffolding probe failed with HTTP ${scaffolding_status}; project mode was not changed." >&2
      exit 1
      ;;
  esac
fi

package_count=$(jq -r '.configurations.packages | length' "$response_file")

if [ "$external_mode" = "true" ]; then
  echod "Project uses external Git; reading product metadata from ${dada_repository}:${dada_branch}."
  if ! bash "${script_dir}/github/cloneRepository.sh" \
    "$repo_user" "$PAT" "$dada_repository" "$dada_branch" "${temp_dir}/dada-repository"; then
    echo "Unable to read external project repository '${dada_repository}' branch '${dada_branch}'." >&2
    exit 1
  fi

  source_scaffolding="${temp_dir}/dada-repository/config/scaffolding/${scaffolding_name}.yml"
  source_mapping="${temp_dir}/dada-repository/config/scaffolding/projectmapping.yml"
  if [ ! -f "$source_scaffolding" ]; then
    echo "Required project scaffolding file 'config/scaffolding/${scaffolding_name}.yml' was not found." >&2
    exit 1
  fi

  [ -z "$dada_account_alias" ] && dada_account_alias=$(yq e ".packages[] | select(.name == \"${scaffolding_name}\") | .gitServerName // \"\"" "$source_scaffolding" | head -1)
  scaffolding_branch=$(yq e ".packages[] | select(.name == \"${scaffolding_name}\") | .gitBranch // \"\"" "$source_scaffolding" | head -1)
  [ -n "$scaffolding_branch" ] && dada_branch="$scaffolding_branch"

  bash "${script_dir}/updateProjectConfig.sh" "$project_config" "$project_name" "$project_id" true \
    "$dada_repository" "$dada_api_repository_path" "$dada_branch" "$dada_account_alias" || exit $?

  mkdir -p "$scaffolding_destination"
  find "$scaffolding_destination" -maxdepth 1 -type f -name '*.yml' -delete
  cp "$source_scaffolding" "$scaffolding_destination/"
  [ -f "$source_mapping" ] && cp "$source_mapping" "$scaffolding_destination/"
  rm -f "$package_metadata"

  if [ "$package_count" -gt 0 ] && [ -n "$environment_config_dir" ]; then
    bash "${script_dir}/updateImportedPackageBranchMap.sh" \
      "$automation_repo_dir" "${scaffolding_destination}/$(basename "$source_scaffolding")" \
      "$environment_config_dir" "$debug" || exit $?
  elif [ "$package_count" -eq 0 ]; then
    rm -f "$branch_mapping"
  fi
else
  echod "Project uses internal Git; exporting framework-owned package metadata."
  bash "${script_dir}/updateProjectConfig.sh" "$project_config" "$project_name" "$project_id" false || exit $?
  rm -rf "$scaffolding_destination"

  if [ "$package_count" -eq 0 ]; then
    rm -f "$package_metadata" "$branch_mapping"
    exit 0
  fi

  mkdir -p "$config_root"
  metadata_temp=$(mktemp "${config_root}/.imported-package-metadata.XXXXXX")
  jq '{version: "1.0", packages: [.configurations.packages[] | {
        name: .packageName,
        gitUrl: .gitUrl,
        gitServerName: .gitServerName,
        gitUsername: .gitUserName,
        gitBranch: .gitBranch
      }]}' "$response_file" | yq -P e '.' - > "$metadata_temp" || {
        rm -f "$metadata_temp"
        echo "Unable to generate imported-package metadata." >&2
        exit 1
      }
  mv "$metadata_temp" "$package_metadata"

  if [ -n "$environment_config_dir" ]; then
    bash "${script_dir}/updateImportedPackageBranchMap.sh" \
      "$automation_repo_dir" "$package_metadata" "$environment_config_dir" "$debug" || exit $?
  else
    echod "No environment configuration directory supplied; branch mapping was not generated."
  fi
fi

echod "Project mode and imported-package metadata exported successfully."
