#!/bin/bash

#############################################################################
# validateDadaRepo.sh : Validates the empty GitHub repository required by a #
# DADA project before webMethods Integration initializes it.                #
#############################################################################

repo_user="$1"
PAT="$2"
project_name="$3"
debug="${4:-}"

if [[ "$debug" != "debug" && "$debug" != "trace" ]]; then
  debug=""
fi

[ -z "$repo_user" ] && echo "Missing template parameter repo_user" >&2 && exit 1
[ -z "$PAT" ] && echo "Missing template parameter PAT" >&2 && exit 1
[ -z "$project_name" ] && echo "Missing template parameter project_name" >&2 && exit 1

dada_repo_name="${project_name}Project"
dada_repo_url="https://github.com/${repo_user}/${dada_repo_name}.git"
api_url="https://api.github.com/repos/${repo_user}/${dada_repo_name}"

if [[ "$debug" == "debug" || "$debug" == "trace" ]]; then
  echo "Validating DADA repository: ${repo_user}/${dada_repo_name}" >&2
fi

status=$(curl --silent --output /dev/null --write-out "%{http_code}" \
  --user "${repo_user}:${PAT}" \
  --header 'Accept: application/vnd.github+json' \
  --header 'X-GitHub-Api-Version: 2022-11-28' \
  "$api_url")

case "$status" in
  200)
    ;;
  401|403)
    echo "Unable to access DADA repository '${repo_user}/${dada_repo_name}'. Check the GitHub PAT and repository permissions." >&2
    exit 1
    ;;
  404)
    echo "DADA repository '${repo_user}/${dada_repo_name}' does not exist. Create an empty repository and rerun initialization." >&2
    exit 1
    ;;
  *)
    echo "Unable to validate DADA repository '${repo_user}/${dada_repo_name}'. GitHub returned HTTP ${status}." >&2
    exit 1
    ;;
esac

# A DADA repository must not contain commits before the product links it.
remote_refs=$(git ls-remote "https://${repo_user}:${PAT}@github.com/${repo_user}/${dada_repo_name}.git" 2>/dev/null)
if [ -n "$remote_refs" ]; then
  echo "DADA repository '${repo_user}/${dada_repo_name}' is not empty. The product requires a repository without commits or branches." >&2
  exit 1
fi

echo "$dada_repo_url"
