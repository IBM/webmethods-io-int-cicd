#!/bin/bash

#############################################################################
# Maintain explicit environment-to-branch policy for imported DADA packages. #
#############################################################################

automation_repo_dir="$1"
scaffolding_file="$2"
environment_config_dir="$3"
debug="${4:-}"

if [[ "$debug" != "debug" && "$debug" != "trace" ]]; then
  debug=""
fi

for required in automation_repo_dir scaffolding_file environment_config_dir; do
  [ -z "${!required}" ] && echo "Missing template parameter ${required}" >&2 && exit 1
done

[ ! -f "$scaffolding_file" ] && echo "Scaffolding file does not exist: ${scaffolding_file}" >&2 && exit 1
[ ! -d "$environment_config_dir" ] && echo "Environment configuration directory does not exist: ${environment_config_dir}" >&2 && exit 1

project_package_name="$(basename "$scaffolding_file" .yml)"
packages_json=$(yq -o=json e '.packages // []' "$scaffolding_file" | jq -c \
  --arg projectPackage "$project_package_name" \
  '[.[] | select(.name != $projectPackage) | {name: .name, branch: .gitBranch}]
   | unique_by(.name)')

if ! jq -e 'type == "array" and all(.[];
  (.name | type == "string" and length > 0) and
  (.branch | type == "string" and length > 0))' <<< "$packages_json" >/dev/null; then
  echo "Scaffolding contains an invalid imported-package name or branch." >&2
  exit 1
fi

environment_values=()
while IFS= read -r environment_file; do
  environment_type=$(yq e '.tenant.type // ""' "$environment_file")
  [ -z "$environment_type" ] && echo "Missing tenant.type in ${environment_file}." >&2 && exit 1
  environment_values+=("$environment_type")
done < <(find "$environment_config_dir" -maxdepth 1 -type f -name '*.yml' -print | sort)

if [ "${#environment_values[@]}" -eq 0 ]; then
  echo "No environment configuration files found in ${environment_config_dir}." >&2
  exit 1
fi

environments_json=$(printf '%s\n' "${environment_values[@]}" | jq -Rsc '
  split("\n") |
  map(select(length > 0)) |
  unique |
  sort_by(
    if . == "play" then 0
    elif . == "dev" or . == "development" then 1
    elif . == "qa" then 2
    elif . == "preprod" then 3
    elif . == "prod" or . == "production" then 4
    else 5
    end
  )
')
source_environment=$(jq -r '
  if index("play") then "play"
  elif index("development") then "development"
  elif index("dev") then "dev"
  else .[0] // ""
  end
' <<< "$environments_json")
[ -z "$source_environment" ] && echo "Unable to determine source environment from ${environment_config_dir}." >&2 && exit 1
mapping_file="${automation_repo_dir}/assets/dada/config/imported-package-branches.yml"
mkdir -p "$(dirname "$mapping_file")"

if [ -f "$mapping_file" ]; then
  if ! yq e '.' "$mapping_file" >/dev/null 2>&1; then
    echo "Imported-package branch mapping is not valid YAML: ${mapping_file}" >&2
    exit 1
  fi
  existing_json=$(yq -o=json e '.' "$mapping_file")
else
  existing_json='{}'
fi

updated_json=$(jq -c \
  --argjson packages "$packages_json" \
  --argjson environments "$environments_json" \
  --arg sourceEnvironment "$source_environment" '
    .version = (.version // "1.0") |
    .packages = (.packages // {}) |
    reduce $packages[] as $package (.;
      .packages[$package.name] = (.packages[$package.name] // {}) |
      .packages[$package.name].branches = (.packages[$package.name].branches // {}) |
      .packages[$package.name].branches as $existingBranches |
      .packages[$package.name].branches = (
        (reduce $environments[] as $environment ({};
          .[$environment] = (
            if $environment == $sourceEnvironment then $package.branch
            else ($existingBranches[$environment] // $environment)
            end
          )
        )) + $existingBranches
        | .[$sourceEnvironment] = $package.branch
      )
    )
  ' <<< "$existing_json") || exit 1

temporary_file=$(mktemp)
trap 'rm -f "$temporary_file"' EXIT
printf '%s\n' "$updated_json" | yq -P e '.' - > "$temporary_file"
mv "$temporary_file" "$mapping_file"
trap - EXIT

if [ -n "$debug" ]; then
  echo "Updated imported-package branch mapping: ${mapping_file}" >&2
fi
