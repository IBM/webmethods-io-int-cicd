#!/bin/bash

#############################################################################
# Validate and resolve portable DADA initialization settings.               #
#############################################################################

repo_user="$1"
PAT="$2"
project_name="$3"
dada_enabled=$(echo "${4:-false}" | tr '[:upper:]' '[:lower:]')
dada_git_account_alias="${5:-}"
debug="${@: -1}"

for required in repo_user PAT project_name; do
  [ -z "${!required}" ] && echo "Missing template parameter ${required}" >&2 && exit 1
done

if [ "$dada_enabled" != "true" ]; then
  jq -n '{enabled: false, gitAccountAlias: "", repository: "", branch: "dev"}'
  exit 0
fi

if [ -z "$dada_git_account_alias" ]; then
  echo "DADA Git connection alias is required when DADA initialization is enabled." >&2
  exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! dada_repository=$("${script_dir}/github/validateDadaRepo.sh" \
  "$repo_user" "$PAT" "$project_name" "$debug"); then
  echo "DADA repository preflight failed. Repository initialization and project creation have been stopped." >&2
  exit 1
fi

jq -n \
  --arg alias "$dada_git_account_alias" \
  --arg repository "$dada_repository" \
  '{enabled: true, gitAccountAlias: $alias, repository: $repository, branch: "dev"}'

