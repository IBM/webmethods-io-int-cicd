#!/bin/bash

#################################################################################
#                                                                               #
# createFeatureFromProdBranch.sh : Create Feature Branch from Production Branch #
#                                                                               #
#################################################################################

devUser=$1
buildNumber=$2
featureBranchName=$3
HOME_DIR=$3
debug=${@: -1}

if [[ "$debug" != "debug" && "$debug" != "trace" ]]; then
  debug=""
fi



    if [ -z "$devUser" ]; then
      echo "Missing template parameter devUser"
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

    if [ -z "$HOME_DIR" ]; then
      echo "Missing template parameter HOME_DIR"
      exit 1
    fi
   
    if [ "$debug" == "trace" ]; then
      echo "......Running in Trace mode ......" >&2
      set -x
    elif [ "$debug" == "debug" ]; then
      echo "......Running in Debug mode ......"
    fi
function echod(){
  
  if [ "$debug" == "debug" ] || [ "$debug" == "trace" ]; then
    echo "$@" 
  fi

}


    git config user.email "noemail.com"
    git config user.name "${devUser}"
    git add .
    git commit -m "push the export repository from pipeline. Build: ${buildNumber}"
    git push origin HEAD:${featureBranchName}
set +x
