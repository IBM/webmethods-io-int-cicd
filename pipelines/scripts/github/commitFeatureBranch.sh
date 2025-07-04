#!/bin/bash

#################################################################################
#                                                                               #
# createFeatureFromProdBranch.sh : Create Feature Branch from Production Branch #
#                                                                               #
#################################################################################

GITHUB_USER=$1
buildNumber=$2
featureBranchName=$3
#HOME_DIR=$3
GITHUB_TOKEN=$4
WMIO_PROJECT_GIT_URL=$5
debug=${@: -1}
WMIO_PROJECT_GIT_URL_PUSH="https://${GITHUB_TOKEN}@${WMIO_PROJECT_GIT_URL#https://}"

echo $WMIO_PROJECT_GIT_URL_PUSH



    if [ -z "$GITHUB_USER" ]; then
      echo "Missing template parameter GITHUB_USER"
      exit 1
    fi

    if [ -z "$buildNumber" ]; then
      echo "Missing template parameter buildNumber"
      exit 1
    fi

    if [ -z "$featureBranchName" ]; then
      echo "Missing template parameter featureBranchName"
      exit 1
    fi

    if [ -z "$WMIO_PROJECT_GIT_URL" ]; then
      echo "Missing template parameter HOME_DIR"
      exit 1
    fi

    if [ -z "$GITHUB_TOKEN" ]; then
      echo "Missing template parameter featureBranchName"
      exit 1
    fi
   
    if [ "$debug" == "debug" ]; then
      echo "......Running in Debug mode ......"
    fi
    

set -x
function echod(){
  
  if [ "$debug" == "debug" ]; then
    echo $1
    
  fi

}


   # git config user.email "sample@mail.com"
    git config user.name "${GITHUB_USER}"
    git add .
    git commit -m "push the export repository from pipeline. Build: ${buildNumber}"
    git push ${WMIO_PROJECT_GIT_URL_PUSH} HEAD:${featureBranchName}

set +x