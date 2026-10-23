#!/bin/bash

#############################################################################
# Import external packages declared by the destination branch scaffolding.  #
#############################################################################

LOCAL_DEV_URL="$1"
admin_user="$2"
admin_password="$3"
project_name="$4"
automation_repo_dir="$5"
target_environment="${6:-}"
debug="${7:-}"

# Backward compatibility: the original signature used argument 6 for debug.
if [[ "$target_environment" == "debug" || "$target_environment" == "trace" ]]; then
  debug="$target_environment"
  target_environment=""
fi

if [[ "$debug" != "debug" && "$debug" != "trace" ]]; then
  debug=""
fi

for required in LOCAL_DEV_URL admin_user admin_password project_name automation_repo_dir; do
  [ -z "${!required}" ] && echo "Missing template parameter ${required}" >&2 && exit 1
done

function echod() {
  if [[ "$debug" == "debug" || "$debug" == "trace" ]]; then
    echo "$@" >&2
  fi
}

project_config="${automation_repo_dir}/project-config.yml"
scaffolding_dir="${automation_repo_dir}/assets/dada/config/scaffolding"
package_metadata="${automation_repo_dir}/assets/dada/config/imported-package-metadata.yml"
branch_mapping_file="${automation_repo_dir}/assets/dada/config/imported-package-branches.yml"
external_mode=""
if [ -f "$project_config" ]; then
  has_external_mode=$(yq e '.project."external-git" | has("enabled")' "$project_config")
  if [ "$has_external_mode" = "true" ]; then
    external_mode=$(yq e '.project."external-git".enabled' "$project_config")
  else
    external_mode=$(yq e '.project.dada.enabled // ""' "$project_config")
  fi
fi

scaffolding_files=()
while IFS= read -r scaffolding_path; do
  scaffolding_files+=("$scaffolding_path")
done < <([ -d "$scaffolding_dir" ] && find "$scaffolding_dir" -maxdepth 1 -type f \
  -name '*.yml' ! -name 'projectmapping.yml' -print)

if [ "$external_mode" = "true" ]; then
  if [ "${#scaffolding_files[@]}" -eq 0 ]; then
    if [ -f "$package_metadata" ] || [ -f "$branch_mapping_file" ] || \
       [ -f "${scaffolding_dir}/projectmapping.yml" ]; then
      echo "External-Git project scaffolding is missing while DADA metadata is present." >&2
      exit 1
    fi
    echod "External-Git project has no imported-package metadata; skipping package import."
    exit 0
  fi
  [ "${#scaffolding_files[@]}" -ne 1 ] && echo "Expected one DADA project scaffolding file, found ${#scaffolding_files[@]}." >&2 && exit 1
  package_source_file="${scaffolding_files[0]}"
  project_package_name="$(basename "$package_source_file" .yml)"
elif [ "$external_mode" = "false" ]; then
  if [ ! -f "$package_metadata" ]; then
    echod "Internal-Git project has no imported-package metadata; skipping package import."
    exit 0
  fi
  package_source_file="$package_metadata"
  project_package_name=""
else
  # Backward compatibility for exports created before project mode was recorded.
  if [ "${#scaffolding_files[@]}" -eq 1 ]; then
    package_source_file="${scaffolding_files[0]}"
    project_package_name="$(basename "$package_source_file" .yml)"
  elif [ -f "$package_metadata" ]; then
    package_source_file="$package_metadata"
    project_package_name=""
  elif [ "${#scaffolding_files[@]}" -gt 1 ]; then
    echo "Expected one DADA project scaffolding file, found ${#scaffolding_files[@]}." >&2
    exit 1
  else
    echod "No imported-package metadata found; skipping package import."
    exit 0
  fi
fi

if ! yq e '.' "$package_source_file" >/dev/null 2>&1; then
  echo "Imported-package metadata is not valid YAML: ${package_source_file}" >&2
  exit 1
fi

branch_mapping_json='{}'
if [ -f "$branch_mapping_file" ]; then
  if ! yq e '.' "$branch_mapping_file" >/dev/null 2>&1; then
    echo "Imported-package branch mapping is not valid YAML: ${branch_mapping_file}" >&2
    exit 1
  fi
  branch_mapping_json=$(yq -o=json e '.' "$branch_mapping_file")
fi

packages_json=$(yq -o=json e '.packages // []' "$package_source_file" | jq -c \
  --arg projectPackage "$project_package_name" \
  --arg targetEnvironment "$target_environment" \
  --argjson branchMapping "$branch_mapping_json" \
  --arg mappingPresent "$([ -f "$branch_mapping_file" ] && echo true || echo false)" '
    [ .[]
      | select(.name != $projectPackage)
      | {
          packageName: .name,
          gitUrl: .gitUrl,
          gitServerName: .gitServerName,
          gitUserName: .gitUsername,
          gitBranch: (
            if $targetEnvironment == "" then .gitBranch
            elif $mappingPresent == "true" then
              ($branchMapping.packages[.name].branches[$targetEnvironment] // "")
            else $targetEnvironment
            end
          ),
          sourceBranch: .gitBranch
        }
    ]
  ')

package_count=$(jq -r 'length' <<< "$packages_json")
if [ "$package_count" -eq 0 ]; then
  echod "Scaffolding contains no external packages; skipping package import."
  exit 0
fi

if ! jq -e 'all(.[];
  (.packageName | type == "string" and length > 0) and
  (.gitUrl | type == "string" and length > 0) and
  (.gitServerName | type == "string" and length > 0) and
  (.gitUserName | type == "string" and length > 0) and
  (.gitBranch | type == "string" and length > 0) and
  (.sourceBranch | type == "string" and length > 0))' <<< "$packages_json" >/dev/null; then
  echo "One or more external package entries have incomplete Git details." >&2
  if [ -f "$branch_mapping_file" ] && [ -n "$target_environment" ]; then
    echo "Ensure every imported package defines a branch for environment '${target_environment}' in ${branch_mapping_file}." >&2
  fi
  exit 1
fi

import_url="${LOCAL_DEV_URL}/apis/v1/rest/projects/${project_name}/configurations/packages"
response_file=$(mktemp)
trap 'rm -f "$response_file"' EXIT

echod "Importing ${package_count} external package(s) from destination-branch metadata."
while IFS= read -r package_payload; do
  package_name=$(jq -r '.packageName' <<< "$package_payload")
  package_branch=$(jq -r '.gitBranch' <<< "$package_payload")
  source_branch=$(jq -r '.sourceBranch' <<< "$package_payload")
  request_payload=$(jq -c 'del(.sourceBranch)' <<< "$package_payload")

  echod "Importing dependent package '${package_name}': recorded branch '${source_branch}', target branch '${package_branch}'."
  http_status=$(curl --silent --show-error --location \
    --output "$response_file" --write-out '%{http_code}' \
    --request POST "$import_url" \
    --header 'Content-Type: application/json' \
    --header 'Accept: application/json' \
    --user "${admin_user}:${admin_password}" \
    --data-raw "$request_payload") || {
      echo "External package '${package_name}' import request failed." >&2
      exit 1
    }

  if [[ ! "$http_status" =~ ^2[0-9][0-9]$ ]]; then
    echo "External package '${package_name}' import failed with HTTP ${http_status}: $(cat "$response_file")" >&2
    exit 1
  fi

  if [ -s "$response_file" ] && jq -e '.error? != null' "$response_file" >/dev/null 2>&1; then
    echo "External package '${package_name}' import returned an error: $(cat "$response_file")" >&2
    exit 1
  fi
done < <(jq -c '.[]' <<< "$packages_json")

echod "External package import completed successfully."
