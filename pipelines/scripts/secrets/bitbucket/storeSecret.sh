#!/bin/bash

#############################################################################
#                                                                           #
# storeSecret.sh : Stores the secret in BITBUCKET.                      #
#                                                                           #
#############################################################################

 secretName=$1
 secretValue=$2
 repo_user=$3
 repoName=$4
 PAT=$5
 HOME_DIR=$6
 debug=${@: -1}

if [[ "$debug" != "debug" && "$debug" != "trace" ]]; then
  debug=""
fi

# Validate required inputs
[ -z "$secretName" ] && echo "Missing template parameter secretName" >&2 && exit 1
[ -z "$secretValue" ] && echo "Missing template parameter secretValue" >&2 && exit 1
[ -z "$repo_user" ] && echo "Missing template parameter repo_user" >&2 && exit 1
[ -z "$repoName" ] && echo "Missing template parameter repoName" >&2 && exit 1
[ -z "$PAT" ] && echo "Missing template parameter PAT" >&2 && exit 1
[ -z "$HOME_DIR" ] && echo "Missing template parameter HOME_DIR" >&2 && exit 1


# Debug mode
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
