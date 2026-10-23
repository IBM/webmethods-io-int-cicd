#!/bin/bash

#############################################################################
#                                                                           #
# prepareImportProject.sh : Decides whether import needs explicit project   #
#                           creation before assets are imported             #
#                                                                           #
#############################################################################

LOCAL_DEV_URL="$1"
admin_user="$2"
admin_password="$3"
repoName="$4"
projectRepoDir="$5"
inuid="$6"
synchProject="$7"
assetTypeList="$8"
debug="${@: -1}"

[ -z "$LOCAL_DEV_URL" ] && echo "Missing template parameter LOCAL_DEV_URL" >&2 && exit 1
[ -z "$admin_user" ] && echo "Missing template parameter admin_user" >&2 && exit 1
[ -z "$admin_password" ] && echo "Missing template parameter admin_password" >&2 && exit 1
[ -z "$repoName" ] && echo "Missing template parameter repoName" >&2 && exit 1
[ -z "$projectRepoDir" ] && echo "Missing template parameter projectRepoDir" >&2 && exit 1
[ -z "$synchProject" ] && echo "Missing template parameter synchProject" >&2 && exit 1

if [[ "$debug" != "debug" && "$debug" != "trace" ]]; then
  debug=""
fi

if [ "$debug" = "trace" ]; then
  echo "......Running in Trace mode ......" >&2
  set -x
elif [ "$debug" = "debug" ]; then
  echo "......Running in Debug mode ......" >&2
fi

function echod() {
  if [ "$debug" = "debug" ] || [ "$debug" = "trace" ]; then
    echo "$@" >&2
  fi
}

apiImportCreatesProject="false"

if [ "$synchProject" = "true" ]; then
  if compgen -G "${projectRepoDir}/assets/rest_api/*.zip" >/dev/null || \
     compgen -G "${projectRepoDir}/assets/soap_api/*.zip" >/dev/null; then
    apiImportCreatesProject="true"
  fi
else
  normalizedAssetTypes=$(printf '%s' "$assetTypeList" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  if printf '%s\n' "$normalizedAssetTypes" | grep -E '^(rest_api|soap_api)$' >/dev/null 2>&1; then
    apiImportCreatesProject="true"
  fi
fi

if [ "$apiImportCreatesProject" = "true" ]; then
  echod "REST or SOAP API import is selected and will create the project if it does not exist."
  exit 0
fi

echod "No REST or SOAP API import will create the project. Ensuring the project exists before asset import."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"${SCRIPT_DIR}/createProject.sh" \
  "$LOCAL_DEV_URL" \
  "$admin_user" \
  "$admin_password" \
  "$repoName" \
  "$inuid" \
  "$debug"
