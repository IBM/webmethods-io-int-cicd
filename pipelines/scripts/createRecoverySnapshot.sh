#!/bin/bash

#############################################################################
# Export the live development project to a recovery branch and verify that  #
# its content matches production before destructive reinitialization.       #
#############################################################################

repo_name="$1"
home_dir="$2"
dev_user="$3"
build_number="$4"
recovery_branch="$5"
production_branch="$6"
export_adapter="$7"
debug="$8"
shift 8
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
snapshot_comparator="${script_dir}/compareRecoverySnapshot.py"

for required in repo_name home_dir dev_user build_number recovery_branch \
  production_branch export_adapter; do
  [ -z "${!required}" ] && echo "Missing template parameter ${required}" >&2 && exit 1
done

[ ! -x "$export_adapter" ] && echo "Recovery export adapter is not executable: ${export_adapter}" >&2 && exit 1
[ ! -f "$snapshot_comparator" ] && echo "Recovery snapshot comparator was not found: ${snapshot_comparator}" >&2 && exit 1

repo_dir="${home_dir%/}/${repo_name}"
if [ ! -d "$repo_dir/.git" ]; then
  echo "Recovery snapshot repository is invalid: ${repo_dir}" >&2
  exit 1
fi

cd "$repo_dir" || exit 1
repo_dir="$(pwd -P)"
repository_root="$(git rev-parse --show-toplevel)"
if [ "$repository_root" != "$repo_dir" ]; then
  echo "Refusing recovery cleanup because '${repo_dir}' is not the Git repository root." >&2
  exit 1
fi

if ! git check-ref-format --branch "$recovery_branch" >/dev/null 2>&1; then
  echo "Invalid recovery branch name: ${recovery_branch}" >&2
  exit 1
fi

if ! git fetch --quiet origin \
  "+refs/heads/${production_branch}:refs/remotes/origin/${production_branch}"; then
  echo "Unable to fetch production branch '${production_branch}'." >&2
  exit 1
fi

production_ref="origin/${production_branch}"
if ! git rev-parse --verify --quiet "${production_ref}^{commit}" >/dev/null; then
  echo "Production branch '${production_branch}' does not exist on origin." >&2
  exit 1
fi

if git ls-remote --exit-code --heads origin "$recovery_branch" >/dev/null 2>&1; then
  echo "Recovery branch '${recovery_branch}' already exists. Use a unique build identifier." >&2
  exit 1
fi

git checkout --detach "$production_ref" >/dev/null || exit 1
git checkout -b "$recovery_branch" >/dev/null || exit 1

# A full recovery export must not retain assets that are absent from the live
# tenant. The validated target is the assets directory of this temporary clone.
if [ -d "$repo_dir/assets" ]; then
  rm -rf -- "$repo_dir/assets"
fi

echo "Exporting the live development project to recovery branch '${recovery_branch}'."
if ! "$export_adapter" "$repo_dir" "$@"; then
  echo "Recovery export failed. No project content will be imported." >&2
  exit 1
fi

git config user.email "noemail.com"
git config user.name "$dev_user"
git add -A
if ! git diff --cached --quiet; then
  git commit -m "Recovery snapshot before initialization. Build: ${build_number}" >/dev/null || exit 1
fi

if ! git push origin "HEAD:refs/heads/${recovery_branch}"; then
  echo "Unable to push recovery branch '${recovery_branch}'. No project content will be imported." >&2
  exit 1
fi

comparison_output="$(mktemp)"
trap 'rm -f "$comparison_output"' EXIT
comparison_status=0
python3 "$snapshot_comparator" "$production_ref" HEAD >"$comparison_output" || comparison_status=$?
if [ "$comparison_status" -eq 0 ]; then
  echo "Live development content matches production. Recovery preflight succeeded."
  exit 0
fi

if [ "$comparison_status" -ne 1 ]; then
  echo "Recovery snapshot comparison failed unexpectedly (exit code ${comparison_status})." >&2
  echo "No project content will be imported." >&2
  exit "$comparison_status"
fi

echo "Initialization stopped: the live development project contains content that is not in production." >&2
echo "The recovery snapshot is preserved in branch '${recovery_branch}'." >&2
echo "No feature branch was created and no project content was imported." >&2
echo >&2
echo "Files differing between production and the recovery snapshot:" >&2
cat "$comparison_output" >&2

exit 1
