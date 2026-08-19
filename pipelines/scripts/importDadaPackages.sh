#!/bin/bash

#############################################################################
# Import external packages declared by the destination branch scaffolding.  #
#############################################################################

LOCAL_DEV_URL="$1"
admin_user="$2"
admin_password="$3"
project_name="$4"
automation_repo_dir="$5"
debug="${@: -1}"

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

scaffolding_dir="${automation_repo_dir}/assets/dada/config/scaffolding"
if [ ! -d "$scaffolding_dir" ]; then
  echod "No DADA scaffolding directory found; skipping external package import."
  exit 0
fi

mapfile -t scaffolding_files < <(find "$scaffolding_dir" -maxdepth 1 -type f \
  -name '*.yml' ! -name 'projectmapping.yml' -print)

if [ "${#scaffolding_files[@]}" -eq 0 ]; then
  echo "DADA metadata exists, but the project scaffolding file is missing." >&2
  exit 1
fi
if [ "${#scaffolding_files[@]}" -ne 1 ]; then
  echo "Expected one DADA project scaffolding file, found ${#scaffolding_files[@]}." >&2
  exit 1
fi

scaffolding_file="${scaffolding_files[0]}"
project_package_name="$(basename "$scaffolding_file" .yml)"

if ! yq e '.' "$scaffolding_file" >/dev/null 2>&1; then
  echo "DADA scaffolding is not valid YAML: ${scaffolding_file}" >&2
  exit 1
fi

packages_json=$(yq -o=json e '.packages // []' "$scaffolding_file" | jq -c \
  --arg projectPackage "$project_package_name" '
    [ .[]
      | select(.name != $projectPackage)
      | {
          packageName: .name,
          gitUrl: .gitUrl,
          gitServerName: .gitServerName,
          gitUserName: .gitUsername,
          gitBranch: .gitBranch
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
  (.gitBranch | type == "string" and length > 0))' <<< "$packages_json" >/dev/null; then
  echo "One or more external package entries have incomplete Git details." >&2
  exit 1
fi

payload=$(jq -n --argjson packages "$packages_json" '{packages: $packages}')
import_url="${LOCAL_DEV_URL}/apis/v1/rest/projects/${project_name}/configurations/packages/import"
response_file=$(mktemp)
trap 'rm -f "$response_file"' EXIT

echod "Importing ${package_count} external package(s) from destination-branch scaffolding."
http_status=$(curl --silent --show-error --location \
  --output "$response_file" --write-out '%{http_code}' \
  --request PUT "$import_url" \
  --header 'Content-Type: application/json' \
  --header 'Accept: application/json' \
  --user "${admin_user}:${admin_password}" \
  --data-raw "$payload") || {
    echo "External package import request failed." >&2
    exit 1
  }

if [[ ! "$http_status" =~ ^2[0-9][0-9]$ ]]; then
  echo "External package import API failed with HTTP ${http_status}: $(cat "$response_file")" >&2
  exit 1
fi

if ! jq empty "$response_file" >/dev/null 2>&1; then
  echo "External package import API returned invalid JSON." >&2
  exit 1
fi

results=$(jq -c '.packages // .output.packages // empty' "$response_file")
if [ -z "$results" ] || [ "$results" = "null" ]; then
  echo "External package import response did not contain package results." >&2
  exit 1
fi

failed=$(jq -c '[.[] | select((.status | ascii_downcase) != "success")]' <<< "$results")
if [ "$(jq -r 'length' <<< "$failed")" -gt 0 ]; then
  echo "External package import failed: ${failed}" >&2
  exit 1
fi

echod "External package import completed successfully."

