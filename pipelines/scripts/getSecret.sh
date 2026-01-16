#!/bin/bash

#############################################################################
##                                                                          #
##getSecret.sh : Retrieves a secret from the specified provider.           #
##                                                                          #
#############################################################################


provider="$1"         # github | bitbucket | azure
secretName="$2"
repoUser="$3"         # For Azure: Vault Name
repoName="$4"         # Optional, for future use
PAT="$5"              # Optional, for future use
HOME_DIR="$6"         # Optional, for future use
debug="${@: -1}"

if [[ "$debug" != "debug" && "$debug" != "trace" ]]; then
  debug=""
fi

# Validate required inputs
[ -z "$provider" ] && echo "Missing provider" >&2 && exit 1
[ -z "$secretName" ] && echo "Missing secretName" >&2 && exit 1
[ -z "$repoUser" ] && echo "Missing vault name or repo user" >&2 && exit 1

if [ "$debug" == "trace" ]; then
  echo "......Running in Trace mode ......" >&2
  set -x
elif [ "$debug" == "debug" ]; then
  echo "......Running in Debug mode ......" >&2
fi

function echod() {
  if [ "$debug" == "debug" ] || [ "$debug" == "trace" ]; then
    echo "$@" >&2
  fi
}

case "$provider" in
  azure)
    VAULT_NAME="$repoUser"
    secret_value=$(az keyvault secret show --vault-name "$VAULT_NAME" --name "$secretName" --query "value" -o tsv 2>/dev/null)

    if [[ -z "$secret_value" || "$secret_value" == "null" ]]; then
      echod "❌ Secret '$secretName' not found in vault '$VAULT_NAME'."
      exit 1
    fi

    echo "$secret_value"
    ;;

  *)
    echod "❌ Unknown provider '$provider'"
    exit 1
    ;;
esac
