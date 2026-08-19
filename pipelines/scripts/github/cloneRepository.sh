#!/bin/bash

#############################################################################
# Clone a GitHub repository without embedding credentials in the clone URL. #
#############################################################################

repo_user="$1"
PAT="$2"
repository="$3"
branch="$4"
destination="$5"

for required in repo_user PAT repository branch destination; do
  [ -z "${!required}" ] && echo "Missing template parameter ${required}" >&2 && exit 1
done

clone_url="https://github.com/${repository}.git"
git_auth=$(printf '%s' "${repo_user}:${PAT}" | base64 | tr -d '\n')

git -c "http.extraHeader=Authorization: Basic ${git_auth}" clone \
  --quiet --depth 1 --branch "$branch" "$clone_url" "$destination"

