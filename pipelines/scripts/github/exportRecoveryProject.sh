#!/bin/bash

#############################################################################
# GitHub/Master adapter used by the shared recovery-snapshot lifecycle.      #
#############################################################################

repo_dir="$1"
LOCAL_DEV_URL="$2"
admin_user="$3"
admin_password="$4"
repo_name="$5"
home_dir="$6"
source_type="$7"
env_types="$8"
repo_user="$9"
PAT="${10}"
provider="${11}"
vault_name="${12}"
resource_group="${13}"
location="${14}"
azure_tenant_id="${15}"
azure_client_id="${16}"
azure_client_secret="${17}"
azure_access_object_id="${18}"
debug="${19}"

for required in repo_dir LOCAL_DEV_URL admin_user admin_password repo_name \
  home_dir source_type env_types repo_user PAT provider vault_name \
  resource_group location azure_tenant_id azure_client_id \
  azure_client_secret azure_access_object_id; do
  [ -z "${!required}" ] && echo "Missing template parameter ${required}" >&2 && exit 1
done

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
common_scripts_dir="$(cd "${script_dir}/.." && pwd)"

if ! "${common_scripts_dir}/exportAsset.sh" \
  "$LOCAL_DEV_URL" "$admin_user" "$admin_password" "$repo_name" \
  "NA" "NA" "$home_dir" true "$source_type" true "$env_types" \
  "$repo_user" "$PAT" "$provider" "$vault_name" "$resource_group" \
  "$location" "$azure_tenant_id" "$azure_client_id" \
  "$azure_client_secret" "$azure_access_object_id" false "$debug"; then
  echo "Recovery asset export failed." >&2
  exit 1
fi

echo "Exporting imported-package scaffolding and project mapping to recovery."
if ! "${common_scripts_dir}/exportDadaMetadata.sh" \
  "$LOCAL_DEV_URL" "$admin_user" "$admin_password" "$repo_name" \
  "$repo_dir" "$repo_user" "$PAT" "$debug"; then
  echo "Recovery external-Git metadata export failed." >&2
  exit 1
fi
