#!/bin/bash

#############################################################################
# Read and export product-managed DADA metadata without modifying its repo.  #
#############################################################################

LOCAL_DEV_URL="$1"
admin_user="$2"
admin_password="$3"
project_name="$4"
automation_repo_dir="$5"
repo_user="$6"
PAT="$7"
debug="${@: -1}"

if [[ "$debug" != "debug" && "$debug" != "trace" ]]; then
  debug=""
fi

for required in LOCAL_DEV_URL admin_user admin_password project_name automation_repo_dir repo_user PAT; do
  [ -z "${!required}" ] && echo "Missing template parameter ${required}" >&2 && exit 1
done

function echod() {
  if [[ "$debug" == "debug" || "$debug" == "trace" ]]; then
    echo "$@" >&2
  fi
}

config_url="${LOCAL_DEV_URL}/apis/v2/rest/projects/${project_name}/configurations"
response_file=$(mktemp)
temp_dir=$(mktemp -d)
trap 'rm -f "$response_file"; rm -rf "$temp_dir"' EXIT

http_status=$(curl --silent --show-error --location \
  --output "$response_file" --write-out '%{http_code}' \
  --header 'Accept: application/json' \
  --user "${admin_user}:${admin_password}" \
  "$config_url") || {
    echo "Failed to query project configurations for '${project_name}'." >&2
    exit 1
  }

if [[ ! "$http_status" =~ ^2[0-9][0-9]$ ]]; then
  echo "Project configuration API failed with HTTP ${http_status}: $(cat "$response_file")" >&2
  exit 1
fi

if ! jq empty "$response_file" >/dev/null 2>&1; then
  echo "Project configuration API returned invalid JSON." >&2
  exit 1
fi

if ! jq -e '.configurations.packages | type == "array"' "$response_file" >/dev/null 2>&1; then
  echo "Project configuration response does not contain a configurations.packages array." >&2
  exit 1
fi

package_count=$(jq -r '.configurations.packages | length' "$response_file")
destination="${automation_repo_dir}/assets/dada/config/scaffolding"

if [ "$package_count" -eq 0 ]; then
  echod "No imported packages detected; skipping DADA metadata export."
  if [ -d "${automation_repo_dir}/assets/dada" ]; then
    rm -rf "${automation_repo_dir}/assets/dada"
  fi
  exit 0
fi

dada_repository=$(yq e '.project.dada.repository // ""' "${automation_repo_dir}/project-config.yml")
dada_branch=$(yq e '.project.dada.branch // "dev"' "${automation_repo_dir}/project-config.yml")
if [ -z "$dada_repository" ]; then
  dada_repo_name="${project_name^}Project"
  dada_repository="${repo_user}/${dada_repo_name}"
fi

echod "Detected ${package_count} imported package(s); reading DADA metadata from ${dada_repository}:${dada_branch}."
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! bash "${script_dir}/github/cloneRepository.sh" \
  "$repo_user" "$PAT" "$dada_repository" "$dada_branch" "${temp_dir}/dada-repository"; then
  echo "Unable to read DADA repository '${dada_repository}' branch '${dada_branch}'." >&2
  exit 1
fi

dada_repo_name="${dada_repository##*/}"
source_scaffolding="${temp_dir}/dada-repository/config/scaffolding/${dada_repo_name}.yml"
source_mapping="${temp_dir}/dada-repository/config/scaffolding/projectmapping.yml"

if [ ! -f "$source_scaffolding" ]; then
  echo "Required DADA scaffolding file 'config/scaffolding/${dada_repo_name}.yml' was not found." >&2
  exit 1
fi

mkdir -p "$destination"
cp "$source_scaffolding" "$destination/"
echod "Copied DADA scaffolding without modification."

if [ -f "$source_mapping" ]; then
  cp "$source_mapping" "$destination/"
  echod "Copied DADA project mapping without modification."
else
  rm -f "${destination}/projectmapping.yml"
  echod "No DADA project mapping exists; no runtime assignments were exported."
fi
