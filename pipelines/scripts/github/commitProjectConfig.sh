#!/bin/bash

#################################################################################
#                                                                               #
#  commitProjectConfig.sh : Commit Project Config Yaml to Feature Branch        #
#                                                                               #
#################################################################################


repoName=$1
configName=$2
configPath=$3
configValue=$4
HOME_DIR=$5
commitFlag=$6
devUser=$7
featureBranchName=$8
debug=${@: -1}


# Validate required inputs
[ -z "$repoName" ] && echo "Missing template parameter repoName" >&2 && exit 1
[ -z "$configName" ] && echo "Missing template parameter configName" >&2 && exit 1
[ -z "$configPath" ] && echo "Missing template parameter configPath" >&2 && exit 1
[ -z "$configValue" ] && echo "Missing template parameter configValue" >&2 && exit 1
[ -z "$HOME_DIR" ] && echo "Missing template parameter HOME_DIR" >&2 && exit 1
[ -z "$commitFlag" ] && echo "Missing template parameter commitFlag" >&2 && exit 1


   
# Debug mode
if [ "$debug" == "debug" ]; then
  echo "......Running in Debug mode ......" >&2
  set -x
fi

function echod() {
  echo "$@" >&2
}

# Ensure directory exists
mkdir -p ${HOME_DIR}/${repoName}
cd ${HOME_DIR}/${repoName}
config_file="$configName".yml

# Create the file if it doesn't exist
touch "$config_file"

# Update the YAML using yq
yq -i "$configPath = \"$configValue\"" "$config_file"

echod "✅ Updated $configPath with '$configValue' in $config_file"

if [ ${commitFlag} == "true" ]; then

    [ -z "$featureBranchName" ] && echo "Missing template parameter featureBranchName" >&2 && exit 1
    [ -z "$devUser" ] && echo "Missing template parameter devUser" >&2 && exit 1

    git config user.email "noemail.com"
    git config user.name "${devUser}"
    git add .
    git commit -m "Initialize: push the project config to repository."
    git push origin HEAD:${featureBranchName}
fi
set +x