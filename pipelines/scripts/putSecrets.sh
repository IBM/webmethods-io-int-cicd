#!/bin/bash

#############################################################################
##                                                                          #
##putSecrets.sh : Stores secrets depending on the provider                  #
##                                                                          #
#############################################################################


provider="$1"         # github | bitbucket | vault
secretName="$2"
secretValue="$3"
repoUser="$4"
repoName="$5"
PAT="$6"
HOME_DIR="$7"
debug="${@: -1}"

# Validate required inputs
[ -z "$provider" ] && echo "Missing template parameter provider" >&2 && exit 1
[ -z "$secretName" ] && echo "Missing template parameter secretName" >&2 && exit 11
[ -z "$repoUser" ] && echo "Missing template parameter repoUser" >&2 && exit 1
[ -z "$repoName" ] && echo "Missing template parameter repoName" >&2 && exit 1
[ -z "$PAT" ] && echo "Missing template parameter PAT" >&2 && exit 1
[ -z "$HOME_DIR" ] && echo "Missing template parameter HOME_DIR" >&2 && exit 1



# Debug mode
if [ "$debug" == "debug" ]; then
  echo "......Running in Debug mode ......" >&2
  set -x
fi


function echod() {
  echo "$@" >&2
}

# Default SECRET_VALUE if empty
if [[ -z "$secretValue" ]]; then
  secretValue="PLEASE FILL IN"
  echod "⚠️ Defaulting the value as it is empty"
fi

case "$provider" in
  github)
    "$HOME_DIR/self/pipelines/scripts/secrets/github/storeSecret.sh" "$secretName" "$secretValue" "$repoUser" "$repoName" "$PAT" "$HOME_DIR" "$debug"
    ;;
  bitbucket)
    "$HOME_DIR/self/pipelines/scripts/secrets/bitbucket/storeSecret.sh" "$secretName" "$secretValue" "$repoUser" "$repoName" "$PAT" "$HOME_DIR" "$debug"
    ;;
  azure)
    VAULT_NAME="$repoUser"   # Pass vault name as repoUser for Azure
    "$HOME_DIR/self/pipelines/scripts/secrets/vault/azure/storeAzureSecret.sh" "$VAULT_NAME" "$secretName" "$secretValue" "$debug"
    ;;
  *)
    echod "❌ Unknown provider '$provider'"
    exit 1
    ;;
esac
