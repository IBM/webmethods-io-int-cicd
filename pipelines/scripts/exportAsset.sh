#!/bin/bash
#############################################################################
##                                                                           #
##exportAsset.sh : Export asset from a project                              #
##                                                                          #
#############################################################################

LOCAL_DEV_URL=$1
admin_user=$2
admin_password=$3
repoName=$4
assetIDList=$5
assetTypeList=$6
HOME_DIR=$7
synchProject=$8
source_type=$9
includeAllReferenceData=${10}
envTypes=${11}
repoUser=${12}
PAT=${13}
provider=${14}
vaultName=${15}
resourceGroup=${16}
location=${17}           # e.g. westeurope
azure_tenant_id=${18}        # Azure AD tenant ID
sp_app_id=${19}              # Service Principal App ID (aka client_id)
sp_password=${20}            # Service Principal password (aka client_secret)
access_object_id=${21}
debug=${@: -1}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/secretManager.sh"
source "${SCRIPT_DIR}/configPerEnv.sh"

# Validate required inputs
[ -z "$LOCAL_DEV_URL" ] && echo "Missing template parameter LOCAL_DEV_URL" >&2 && exit 1
[ -z "$admin_user" ] && echo "Missing template parameter admin_user" >&2 && exit 1
[ -z "$admin_password" ] && echo "Missing template parameter admin_password" >&2 && exit 1
[ -z "$repoName" ] && echo "Missing template parameter repoName" >&2 && exit 1
[ -z "$assetIDList" ] && echo "Missing template parameter assetIDList" >&2 && exit 1
[ -z "$assetTypeList" ] && echo "Missing template parameter assetTypeList" >&2 && exit 1
[ -z "$HOME_DIR" ] && echo "Missing template parameter HOME_DIR" >&2 && exit 1
[ -z "$synchProject" ] && echo "Missing template parameter synchProject" >&2 && exit 1
[ -z "$source_type" ] && echo "Missing template parameter source_type" >&2 && exit 1
[ -z "$includeAllReferenceData" ] && echo "Missing template parameter includeAllReferenceData" >&2 && exit 1
[ -z "$envTypes" ] && echo "Missing template parameter envTypes" >&2 && exit 1
[ -z "$repoUser" ] && echo "Missing template parameter repoUser" >&2 && exit 1
[ -z "$PAT" ] && echo "Missing template parameter PAT" >&2 && exit 1
[ -z "$provider" ] && echo "Missing template parameter provider" >&2 && exit 1
[ -z "$vaultName" ] && echo "Missing template parameter vaultName" >&2 && exit 1
[ -z "$resourceGroup" ] && echo "Missing template parameter resourceGroup" >&2 && exit 1
[ -z "$location" ] && echo "Missing template parameter location" >&2 && exit 1#
[ -z "$azure_tenant_id" ] && echo "Missing template parameter azure_tenant_id" >&2 && exit 1
[ -z "$sp_app_id" ] && echo "Missing template parameter sp_app_id" >&2 && exit 1
[ -z "$sp_password" ] && echo "Missing template parameter sp_password" >&2 && exit 1
[ -z "$access_object_id" ] && echo "Missing template parameter access_object_id" >&2 && exit 1

PROJECT_CONFIG_FILE="${HOME_DIR}/${repoName}/project-config.yml"

# Debug mode
if [ "$debug" == "debug" ]; then
  echo "......Running in Debug mode ......" >&2
  set -x
fi

function echod() {
  echo "$@" >&2
}

function exportSingleReferenceData () {
  LOCAL_DEV_URL=$1
  admin_user=$2
  admin_password=$3
  repoName=$4
  assetID=$5
  assetType=$6
  HOME_DIR=$7
  projectID=$8
  rdName=$assetID
  

  cd ${HOME_DIR}/${repoName}
  mkdir -p ./assets/projectConfigs/referenceData
  cd ./assets/projectConfigs/referenceData
  REF_DATA_URL=${LOCAL_DEV_URL}/apis/v1/rest/projects/${repoName}/referencedata/${rdName}
  rdJson=$(curl --location --request GET ${REF_DATA_URL}  \
  --header 'Content-Type: application/json' \
  --header 'Accept: application/json' \
  -u ${admin_user}:${admin_password})
  rdExport=$(echo "$rdJson" | jq '.output // empty')
  if [ -z "$rdExport" ];   then
    echod "Empty reference data defined for the name:" ${rdName}
  else
    columnDelimiter=$(echo "$rdJson" | jq -c -r '.output.columnDelimiter')
    rdExport=$(echo "$rdJson" | jq -c -r '.output.dataRecords')
    if [[ "$columnDelimiter" == "," ]]; then
      datajson=$(echo "$rdExport" | jq -c -r '(map(keys) | add | unique) as $cols | map(. as $row | $cols | map($row[.])) as $rows | $cols, $rows[] | @csv')
    else
      datajson=$(echo "$rdExport" | jq -c -r '(map(keys) | add | unique) as $cols | map(. as $row | $cols | map($row[.])) as $rows | $cols, $rows[] | @csv' | sed "s/\",\"/\"${columnDelimiter}\"/g")
    fi

    echod "${datajson}"
    mkdir -p ${rdName}
    cd ${rdName}
    
    metadataJson=$(echo "$rdJson" | jq -c -r '.output')
    metadataJson=$(echo "$metadataJson"| jq 'del(.columnNames, .dataRecords, .revisionData)')
    echo "$metadataJson" > metadata.json
    echo "$datajson" > ${source_type}.csv
    configPerEnv . ${envTypes} "referenceData" ${source_type}.csv
    cd -
  fi
  cd ${HOME_DIR}/${repoName}
}

function exportConnection(){
  LOCAL_DEV_URL=$1
  admin_user=$2
  admin_password=$3
  repoName=$4
  assetID=$5
  assetType=$6
  HOME_DIR=$7
  cd ${HOME_DIR}/${repoName}

  CONN_LIST_URL=${LOCAL_DEV_URL}/apis/v1/rest/projects/${repoName}/configurations/connections

  connListJson=$(curl  --location --request GET ${CONN_LIST_URL} \
      --header 'Content-Type: application/json' \
      --header 'Accept: application/json' \
      -u ${admin_user}:${admin_password})

      connexport=$(echo "$connListJson" | jq -r -c '.output[].name // empty')

        if [ -z "$connexport" ];   then
            echod "No connections defined for the project" 
        else
          # Setup Azure Key Vault
          if [ ${provider} == "azure" ]; then
            $HOME_DIR/self/pipelines/scripts/secrets/vault/azure/setupAzureKeyVault.sh ${vaultName} ${resourceGroup} ${location} ${azure_tenant_id} ${sp_app_id} ${sp_password} ${access_object_id} debug
          fi
          mkdir -p ./assets/connections
          cd ./assets/connections
          echo "$connListJson" | jq -c '.output[]' | while read -r item; do
            name=$(echo "$item" | jq -r '.name')
            mkdir -p ./$name
            cd $name
maskedJson=$(maskFieldsInJson "$item" "$name" "$repoName" "$source_type" "$provider" "$vaultName" "$HOME_DIR" "$envTypes")

            echo "$maskedJson" > ${name}-${source_type}.json
            configPerEnv . ${envTypes} "connection" ${name}-${source_type}.json $name
            echod "✅ Saved ${name}_${source_type}.json"
            cd ..
          done
        fi
  cd ${HOME_DIR}/${repoName}
}

function exportReferenceData (){ 
  LOCAL_DEV_URL=$1
  admin_user=$2
  admin_password=$3
  repoName=$4
  assetID=$5
  assetType=$6
  HOME_DIR=$7
  cd ${HOME_DIR}/${repoName}

  PROJECT_ID_URL=${LOCAL_DEV_URL}/apis/v1/rest/projects/${repoName}

  projectJson=$(curl  --location --request GET ${PROJECT_ID_URL} \
      --header 'Content-Type: application/json' \
      --header 'Accept: application/json' \
      -u ${admin_user}:${admin_password})


  projectID=$(echo "$projectJson" | jq -r -c '.output.uid // empty')

  if [ -z "$projectID" ];   then
      echod "Incorrect Project/Repo name"
      exit 1
  fi


  echod "ProjectID:" ${projectID}

  PROJECT_REF_DATA_LIST_URL=${LOCAL_DEV_URL}/apis/v1/rest/projects/${repoName}/referencedata

  rdListJson=$(curl --location --request GET ${PROJECT_REF_DATA_LIST_URL}  \
  --header 'Content-Type: application/json' \
  --header 'Accept: application/json' \
  -u ${admin_user}:${admin_password})
  
  rdListExport=$(echo "$rdListJson" | jq -r -c '.output[].name // empty')

  if [ -z "$rdListExport" ];   then
            echod "No reference data defined for the project" 
  else
      for item in $(jq -r '.output[] | .name' <<< "$rdListJson"); do
        echod "Inside Ref Data Loop:" "$item"
        rdName=${item}
        exportSingleReferenceData ${LOCAL_DEV_URL} ${admin_user} ${admin_password} ${repoName} ${rdName} ${assetType} ${HOME_DIR} ${projectID}
      done
    echod "Reference Data export Succeeded"
  fi

  cd ${HOME_DIR}/${repoName}
} 

function exportAsset(){

  LOCAL_DEV_URL=$1
  admin_user=$2
  admin_password=$3
  repoName=$4
  assetID=$5
  assetType=$6
  HOME_DIR=$7
  synchProject=$8
  includeAllReferenceData=$9


    # Single assetType
    if [[ $assetType = referenceData* ]]; then
      PROJECT_ID_URL=${LOCAL_DEV_URL}/apis/v1/rest/projects/${repoName}

      projectJson=$(curl  --location --request GET ${PROJECT_ID_URL} \
          --header 'Content-Type: application/json' \
          --header 'Accept: application/json' \
          -u ${admin_user}:${admin_password})


      projectID=$(echo "$projectJson" | jq -r -c '.output.uid // empty')

      if [ -z "$projectID" ];   then
          echo "Incorrect Project/Repo name"
          exit 1
      fi

      echod "ProjectID:" ${projectID}
      exportSingleReferenceData ${LOCAL_DEV_URL} ${admin_user} ${admin_password} ${repoName} ${assetID} ${assetType} ${HOME_DIR} ${projectID}
    else
      if [[ $assetType = rest_api* ]]; then
          echod $assetType
          EXPORT_URL=${LOCAL_DEV_URL}/apis/v1/rest/projects/${repoName}/export
          rest_api_json='{ "rest_api": ["'${assetID}'"] }'
          cd ${HOME_DIR}/${repoName}
          mkdir -p ./assets/rest_api
          cd ./assets/rest_api
          echod "Rest_API Export:" ${EXPORT_URL} "with JSON: "${rest_api_json}
          echod $(ls -ltr)
      else
        if [[ $assetType = project_parameter* ]]; then
          echod $assetType
          exportProjectParameters ${LOCAL_DEV_URL} ${admin_user} ${admin_password} ${repoName} ${assetID} ${assetType} ${HOME_DIR} ${synchProject} ${includeAllReferenceData}
          return
        else
          if [[ $assetType = workflow* ]]; then
            echod $assetType
            EXPORT_URL=${LOCAL_DEV_URL}/apis/v1/rest/projects/${repoName}/workflows/${assetID}/export
            cd ${HOME_DIR}/${repoName}
            mkdir -p ./assets/workflows
            cd ./assets/workflows
            echod "Workflow Export:" ${EXPORT_URL}
            echod $(ls -ltr)
          else
            if [[ $assetType = flowservice* ]]; then
              EXPORT_URL=${LOCAL_DEV_URL}/apis/v1/rest/projects/${repoName}/flows/${assetID}/export
              cd ${HOME_DIR}/${repoName}
              mkdir -p ./assets/flowservices
              cd ./assets/flowservices
              echo "Flowservice Export:" ${EXPORT_URL}
              echod $(ls -ltr)
            else
              if [[ $assetType = dafservice* ]]; then
                EXPORT_URL=${LOCAL_DEV_URL}/apis/v1/rest/projects/${repoName}/flows/${assetID}/export
                cd ${HOME_DIR}/${repoName}
                mkdir -p ./assets/dafservices
                cd ./assets/dafservices
                echo "DAFservice Export:" ${EXPORT_URL}
                echod $(ls -ltr)
              else
                if [[ $assetType = soap_api* ]]; then
                  EXPORT_URL=${LOCAL_DEV_URL}/apis/v1/rest/projects/${repoName}/export
                  soap_api_json="{\"soap_api\": [\"${assetID}\"]}"
                  cd ${HOME_DIR}/${repoName}
                  mkdir -p ./assets/soap_api
                  cd ./assets/soap_api
                  echod "SOAP_API Export:" ${EXPORT_URL} "with JSON: "${soap_api_json}
                  echod $(ls -ltr)
                else
                  if [[ $assetType = Scheduler* ]]; then
                    echo "Calling another script"
                    echod "SCHEDULER Export Process is Start"
                    ../self/pipelines/scripts/exportSchedulersList.sh "$LOCAL_DEV_URL" "$admin_user" "$admin_password" "$repoName" "$HOME_DIR" "$assetID" "$envTypes" "$source_type" "$debug"
                    echod "SCHEDULER Export Process is End"
                    echod $(ls -ltr)
                    return
                  else
                    if [[ $assetType = project_configuration* ]]; then
                      echo "Calling project configuration script"
                      echod "Project Configuration Export Process is Start"
                      ../self/pipelines/scripts/exportProjectConfiguration.sh "$LOCAL_DEV_URL" "$admin_user" "$admin_password" "$repoName" "$HOME_DIR" "$assetID"
                      echod "project configuration Export Process is End"
                      echod $(ls -ltr)
                      return
                    else
                      if [[ $assetType = project_variable* ]]; then
                        echo "Calling project variable script"
                        echod "Project variable Export Process is Start"
                        ../self/pipelines/scripts/exportProjectVariable.sh "$LOCAL_DEV_URL" "$admin_user" "$admin_password" "$repoName" "$HOME_DIR" "$assetID"
                        echod "project variable Export Process is End"
                        echod $(ls -ltr)
                        return
                      else
                        if [[ $assetType = certificate* ]]; then
                          echo "Calling project Certificate script"
                          echod "Project Certificate Export Process is Start"
                          ../self/pipelines/scripts/exportCertificatesList.sh "$LOCAL_DEV_URL" "$admin_user" "$admin_password" "$repoName" "$HOME_DIR" "$assetID"
                          echod "project Certificate Export Process is End"
                          echod $(ls -ltr)
                          return
                        fi
                      fi
                    fi
                  fi
                fi	
              fi
            fi
          fi
        fi
      fi
      if [[ $assetType = rest_api* ]]; then
        linkJson=$(curl  --location --request POST ${EXPORT_URL} \
        --header 'Content-Type: application/json' \
        --header 'Accept: application/json' \
        --data-raw "$rest_api_json" -u ${admin_user}:${admin_password})
		else
			if [[ $assetType = soap_api* ]]; then
			linkJson=$(curl  --location --request POST ${EXPORT_URL} \
			--header 'Content-Type: application/json' \
			--header 'Accept: application/json' \
			--data-raw "$soap_api_json" -u ${admin_user}:${admin_password})
		else     
			linkJson=$(curl  --location --request POST ${EXPORT_URL} \
			--header 'Content-Type: application/json' \
			--header 'Accept: application/json' \
			-u ${admin_user}:${admin_password})
          fi
        fi
	  fi
     if [ -n "$linkJson" ] && [ "$linkJson" != "null" ]; then
      downloadURL=$(echo "$linkJson" | jq -r '.output.download_link')
      
      regex='(https?|ftp|file)://[-[:alnum:]\+&@#/%?=~_|!:,.;]*[-[:alnum:]\+&@#/%=~_|]'
      
      if [[ $downloadURL =~ $regex ]]; then 
        echod "Valid Download link retreived:"${downloadURL}
      else
          echo "Download link retreival Failed:" ${linkJson}
          exit 1
      fi
      downloadJson=$(curl --location --request GET "${downloadURL}" --output ${assetID}.zip)

        FILE=./${assetID}.zip
        if [ -f "$FILE" ]; then
          echo "Download succeeded:" ls -ltr ./${assetID}.zip
      else
          echo "Download failed:"${downloadJson}
      fi

      # For Single assetType Flowservice Export Reference Data
      if [ ${synchProject} != true ]; then
        if [[ $assetType = flowservice* ]]; then
          if [ ${includeAllReferenceData} == true ]; then
            exportReferenceData ${LOCAL_DEV_URL} ${admin_user} ${admin_password} ${repoName} ${assetID} ${assetType} ${HOME_DIR}
          fi
        fi
      fi 
    fi   
  cd ${HOME_DIR}/${repoName}

}  
function splitAndExportAssets() {

  LOCAL_DEV_URL=$1
  admin_user=$2
  admin_password=$3
  repoName=$4
  assetID=$5
  assetType=$6
  HOME_DIR=$7
  synchProject=$8
  includeAllReferenceData=$9
  local assetNameList="$5"
  local assetTypeList="$6"

  # Desired processing order
  local desiredOrder=("referenceData" "rest_api" "soap_api" "project_parameter" "workflow" "flowservice" "dafservice" "Scheduler" "project_configuration" "project_variable" "certificate" "account" "connection" "vault_variables")

  # Normalize input: remove spaces around commas
  assetNameList=$(echo "$assetNameList" | sed 's/ *, */,/g')
  assetTypeList=$(echo "$assetTypeList" | sed 's/ *, */,/g')

  # Convert to arrays
  IFS=',' read -ra assetNames <<< "$assetNameList"
  IFS=',' read -ra assetTypes <<< "$assetTypeList"

  # Trim whitespace from each element
  for i in "${!assetNames[@]}"; do
    assetNames[$i]=$(echo "${assetNames[$i]}" | xargs)
  done
  for i in "${!assetTypes[@]}"; do
    assetTypes[$i]=$(echo "${assetTypes[$i]}" | xargs)
  done

  # Length check
  local lenNames=${#assetNames[@]}
  local lenTypes=${#assetTypes[@]}
  if [ "$lenNames" -ne "$lenTypes" ]; then
    echo "Error: Mismatch in number of items. assetNameList has $lenNames, assetTypeList has $lenTypes."
    return 1
  fi

  # Validate asset types
  for type in "${assetTypes[@]}"; do
    local found=false
    for valid in "${desiredOrder[@]}"; do
      if [ "$type" == "$valid" ]; then
        found=true
        break
      fi
    done
    if ! $found; then
      echo "Error: Unsupported asset type '$type'."
      return 1
    fi
  done

  # Rearranged processing
  echo "== Processing in Desired Order =="
  for orderType in "${desiredOrder[@]}"; do
    for (( i=0; i<$lenNames; i++ )); do
      if [ "${assetTypes[$i]}" == "$orderType" ]; then
        echo "Processing ${assetNames[$i]} of type ${assetTypes[$i]}"
        exportAsset ${LOCAL_DEV_URL} ${admin_user} ${admin_password} ${repoName} ${assetNames[$i]} ${assetTypes[$i]} ${HOME_DIR} ${synchProject} ${includeAllReferenceData}
      fi
    done
  done
}
function exportProjectParameters(){

    LOCAL_DEV_URL=$1
    admin_user=$2
    admin_password=$3
    repoName=$4
    assetID=$5
    assetType=$6
    HOME_DIR=$7
    synchProject=$8
    includeAllReferenceData=$9
    cd ${HOME_DIR}/${repoName}

    if [ ${synchProject} == true ]; then
      PROJECT_PARAM_GET_URL=${LOCAL_DEV_URL}/apis/v1/rest/projects/${repoName}/params
    else
      PROJECT_PARAM_GET_URL=${LOCAL_DEV_URL}/apis/v1/rest/projects/${repoName}/params/${assetID}
    fi

    ppListJson=$(curl --location --request GET ${PROJECT_PARAM_GET_URL}  \
    --header 'Content-Type: application/json' \
    --header 'Accept: application/json' \
    -u ${admin_user}:${admin_password})

    ppListExport=$(echo "$ppListJson" | jq '. // empty')

    if [ -z "$ppListExport" ];   then
              echo "No Project Parameters retreived:" ${ppListJson}
          else
              mkdir -p ./assets/projectConfigs/parameters
              cd ./assets/projectConfigs/parameters
              if [ ${synchProject} != true ]; then
                parameterUID=$(jq -r '.output.uid' <<< "$ppListJson")
                  mkdir -p ./${parameterUID}
                  cd ./${parameterUID}
                  data=$(jq -r '.output.param' <<< "$ppListJson")
                  key=$(jq -r '.output.param.key' <<< "$ppListJson")
                  metadataJson='{ "uid":"'${parameterUID}'" }'
                  echo ${metadataJson} > ./metadata.json
                  echo ${data} > ./${key}-${source_type}.json
                  configPerEnv . ${envTypes} "project_parameter" ${key}-${source_type}.json ${key}
                  cd ..
              else 
                for item in $(jq  -c -r '.output[]' <<< "$ppListJson"); do
                  echod "Inside Parameters Loop"
                  parameterUID=$(jq -r '.uid' <<< "$item")
                  mkdir -p ./${parameterUID}
                  cd ./${parameterUID}
                  data=$(jq -r '.param' <<< "$item")
                  key=$(jq -r '.param.key' <<< "$item")
                  metadataJson='{ "uid":"'${parameterUID}'" }'
                  echo ${metadataJson} > ./metadata.json
                  echo ${data} > ./${key}-${source_type}.json
                  configPerEnv . ${envTypes} "project_parameter" ${key}-${source_type}.json ${key}
                  cd ..
                done
              fi
            echo "Project Parameters export Succeeded"
          fi
    cd ${HOME_DIR}/${repoName}
}  


if [ ${synchProject} == true ]; then
  echod "Listing All Assets"
  echod $assetType
  PROJECT_LIST_URL=${LOCAL_DEV_URL}/apis/v1/rest/projects/${repoName}/assets

  projectListJson=$(curl  --location --request GET ${PROJECT_LIST_URL} \
    --header 'Content-Type: application/json' \
    --header 'Accept: application/json' \
    -u ${admin_user}:${admin_password})
  
  # Exporting APIs
  for item in $(jq  -c -r '.output.rest_api[]' <<< "$projectListJson"); do
    echod "Inside REST_API Loop"
    assetID=$item
    assetType=rest_api
    echod $assetID
    exportAsset ${LOCAL_DEV_URL} ${admin_user} ${admin_password} ${repoName} ${assetID} ${assetType} ${HOME_DIR} ${synchProject} ${includeAllReferenceData}
  done

  # Exporting Workflows
  for item in $(jq  -c -r '.output.workflows[]' <<< "$projectListJson"); do
    echod "Inside Workflow Loop"
    assetID=$item
    assetType=workflow
    echod $assetID
    exportAsset ${LOCAL_DEV_URL} ${admin_user} ${admin_password} ${repoName} ${assetID} ${assetType} ${HOME_DIR} ${synchProject} ${includeAllReferenceData}
  done
  # Exporting Flows
  for item in $(jq  -c -r '.output.flows[]' <<< "$projectListJson"); do
    echod "Inside FS Loop"
    assetID=$item
    assetType=flowservice
    echod $assetID
    exportAsset ${LOCAL_DEV_URL} ${admin_user} ${admin_password} ${repoName} ${assetID} ${assetType} ${HOME_DIR} ${synchProject} ${includeAllReferenceData}
  done
   # Exporting DAF Flows
  for item in $(jq  -c -r '.output.dafflows[]' <<< "$projectListJson"); do
    echod "Inside FS Loop"
    assetID=$item
    assetType=dafservice
    echod $assetID
    exportAsset ${LOCAL_DEV_URL} ${admin_user} ${admin_password} ${repoName} ${assetID} ${assetType} ${HOME_DIR} ${synchProject} ${includeAllReferenceData}
  done
  # Exporting Soap APIs
  for item in $(jq  -c -r '.output.soap_api[]' <<< "$projectListJson"); do
    echod "Inside SOAP_API Loop"
    assetID=$item
    assetType=soap_api
    echod $assetID
    exportAsset ${LOCAL_DEV_URL} ${admin_user} ${admin_password} ${repoName} ${assetID} ${assetType} ${HOME_DIR} ${synchProject} ${includeAllReferenceData}
  done
  
  #Expoting Accounts
  ACCOUNT_LIST_URL=${LOCAL_DEV_URL}/apis/v1/rest/projects/${repoName}/accounts

  accountListJson=$(curl  --location --request GET ${ACCOUNT_LIST_URL} \
      --header 'Content-Type: application/json' \
      --header 'Accept: application/json' \
      -u ${admin_user}:${admin_password})


      accountexport=$(echo "$accountListJson" | jq '. // empty')
        if [ -z "$accountexport" ];   then
            echo "Account export failed:" ${accountListJson}
        else
            
            mkdir -p ./assets/accounts
            cd ./assets/accounts
            echo "$accountListJson" > user_accounts.json
            echo "Account export Succeeded"
        fi
  
  #Expoting Connections
  assetID=${assetIDList}
  assetType=connection
  exportConnection ${LOCAL_DEV_URL} ${admin_user} ${admin_password} ${repoName} ${assetID} ${assetType} ${HOME_DIR}

  cd ${HOME_DIR}/${repoName}


  # Exporting Project Referencedata
  assetID=${assetIDList}
  assetType=referenceData
  exportReferenceData ${LOCAL_DEV_URL} ${admin_user} ${admin_password} ${repoName} ${assetID} ${assetType} ${HOME_DIR} 
  # Exporting Project Parameters
  #PP Export
  assetType=project_parameter
  exportAsset ${LOCAL_DEV_URL} ${admin_user} ${admin_password} ${repoName} ${assetID} ${assetType} ${HOME_DIR} ${synchProject} ${includeAllReferenceData}
  
  # For Export Scheduler
  assetID=${assetIDList}
  assetType=Scheduler
  exportAsset ${LOCAL_DEV_URL} ${admin_user} ${admin_password} ${repoName} ${assetID} ${assetType} ${HOME_DIR} ${synchProject} ${includeAllReferenceData}
        
  # For Export Project Configuration
  assetID=${assetIDList}
  assetType=project_configuration
  exportAsset ${LOCAL_DEV_URL} ${admin_user} ${admin_password} ${repoName} ${assetID} ${assetType} ${HOME_DIR} ${synchProject} ${includeAllReferenceData}
  
  # For Export Project Variable
  assetID=${assetIDList}
  assetType=project_variable
  exportAsset ${LOCAL_DEV_URL} ${admin_user} ${admin_password} ${repoName} ${assetID} ${assetType} ${HOME_DIR} ${synchProject} ${includeAllReferenceData}
  
  # For Export Certificate
  assetID=${assetIDList}
  assetType=certificate
  exportAsset ${LOCAL_DEV_URL} ${admin_user} ${admin_password} ${repoName} ${assetID} ${assetType} ${HOME_DIR} ${synchProject} ${includeAllReferenceData}
  
else

# Input variables
#assetIDList=" AssetX ,AssetY , AssetZ,AssetA,AssetB ,AssetC "
#assetTypeList="flowservice , workflow, referenceData,dafservice, project_parameter , rest_api "
assetIDList=$(echo "$assetIDList" | sed 's/ *, */,/g')
assetTypeList=$(echo "$assetTypeList" | sed 's/ *, */,/g')
splitAndExportAssets ${LOCAL_DEV_URL} ${admin_user} ${admin_password} ${repoName} "$assetIDList" "$assetTypeList" ${HOME_DIR} ${synchProject} ${includeAllReferenceData}
fi  
