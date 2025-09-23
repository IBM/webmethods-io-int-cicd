#!/bin/bash

#############################################################################
#                                                                           #
# importAsset.sh : Import asset into a project                              #
#                                                                           #
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
provider=${11}
vaultName=${12}
resourceGroup=${13}
location=${14}           # e.g. westeurope
azure_tenant_id=${15}        # Azure AD tenant ID
sp_app_id=${16}              # Service Principal App ID (aka client_id)
sp_password=${17}            # Service Principal password (aka client_secret)
access_object_id=${18}
debug=${@: -1}



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
function importAsset() {
  LOCAL_DEV_URL=$1
  admin_user=$2
  admin_password=$3
  repoName=$4
  assetID=$5
  assetType=$6
  HOME_DIR=$7
  synchProject=$8
  includeAllReferenceData=$9

  echod $(pwd)
  echod $(ls -ltr)
  echod "AssetType:" $assetType
  if [[ $assetType = referenceData* ]]; then
    #Importing Reference Data
    DIR="./assets/projectConfigs/referenceData/"
    if [ -d "$DIR" ]; then
        echod "Project referenceData needs to be synched"
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
        cd ./assets/projectConfigs/referenceData/
        importSingleRefData ${LOCAL_DEV_URL} ${admin_user} ${admin_password} ${repoName} ${assetID} ${assetType} ${HOME_DIR} ${synchProject} ${source_type} ${projectID}
    fi
  else
    if [[ $assetType = rest_api* ]]; then
        IMPORT_URL=${LOCAL_DEV_URL}/apis/v1/rest/project-import
        cd ${HOME_DIR}/${repoName}/assets/rest_api
        echod "REST API Import:" ${IMPORT_URL}
        echod $(ls -ltr)
    else
      if [[ $assetType = workflow* ]]; then
          IMPORT_URL=${LOCAL_DEV_URL}/apis/v1/rest/projects/${repoName}/workflow-import
          cd ${HOME_DIR}/${repoName}/assets/workflows
          echod "Workflow Import:" ${IMPORT_URL}
          echod $(ls -ltr)
      else
        if [[ $assetType = project_parameter* ]]; then
          echod "Project Parameter Import:" ${assetID}
          importSingleProjectParameters ${LOCAL_DEV_URL} ${admin_user} ${admin_password} ${repoName} ${assetID} ${assetType} ${HOME_DIR} ${synchProject} ${source_type} ${projectID}
          return
        else
          if [[ $assetType = flowservice* ]]; then
            IMPORT_URL=${LOCAL_DEV_URL}/apis/v1/rest/projects/${repoName}/flow-import
            cd ${HOME_DIR}/${repoName}/assets/flowservices
            echod "Flowservice Import:" ${IMPORT_URL}
            echod $(ls -ltr)
          else
            if [[ $assetType = dafservice* ]]; then
              IMPORT_URL=${LOCAL_DEV_URL}/apis/v1/rest/projects/${repoName}/flow-import
              cd ${HOME_DIR}/${repoName}/assets/dafservices
              echod "DAFservice Import:" ${IMPORT_URL}
              echod $(ls -ltr)
            fi
          fi
        fi
      fi
     fi     
        echod ${IMPORT_URL}
        echod ${PWD}
    FILE=./${assetID}.zip
    if [[ $assetType = rest_api* ]]; then
      formKey="project=@"${FILE}
    else
      formKey="recipe=@"${FILE}
    fi
    overwriteKey="overwrite=true"
    echod ${formKey}
    if [ -f "$FILE" ]; then
     ####### Check if asset with this name exist

        echod "$FILE exists. Importing ..."
        importedName=$(curl --location --request POST ${IMPORT_URL} \
                    --header 'Content-Type: multipart/form-data' \
                    --header 'Accept: application/json' \
                    --form ${formKey} --form ${overwriteKey} -u ${admin_user}:${admin_password})    

        if [[ $assetType = rest_api* ]]; then
          name=$(echo "$importedName" | jq '.output.message // empty')
          success='"IMPORT_SUCCESS"'
          if [ "$name" == "$success" ];   then
            echod "Import Succeeded:" ${importedName}
          else
            echod "Import Failed:" ${importedName}
          fi
        else
          name=$(echo "$importedName" | jq '.output.name // empty')
          if [ -z "$name" ];   then
            echod "Import failed:" ${importedName}
          else
            echod "Import Succeeded:" ${importedName}
          fi
        fi
    else
      echod "$FILE does not exists, Nothing to import"
    fi

    if [ ${synchProject} != true ]; then
      if [[ $assetType = flowservice* ]]; then
        if [ ${includeAllReferenceData} == true ]; then
          importRefData ${LOCAL_DEV_URL} ${admin_user} ${admin_password} ${repoName} ${assetID} ${assetType} ${HOME_DIR} ${synchProject} ${source_type}
      fi
      fi
    fi
  fi
 cd ${HOME_DIR}/${repoName}
}

function importSingleProjectParameters(){
  LOCAL_DEV_URL=$1
  admin_user=$2
  admin_password=$3
  repoName=$4
  assetID=$5
  assetType=$6
  HOME_DIR=$7
  synchProject=$8
  source_type=$9
  projectID=${10}
  d=$assetID

  cd ${HOME_DIR}/${repoName}
  #Importing Reference Data
  DIR="./assets/projectConfigs/parameters/"
  if [ -d "$DIR" ]; then
    echo "Project parameters needs to be synched"
    echod "ProjectID:" ${projectID}
    cd ./assets/projectConfigs/parameters/
    if [ -d "$d" ]; then
      echod "$d"
      cd "$d"
      if [ ! -f ./metadata.json ]; then
        echo "Metadata not found!"
        exit 1
      fi
      parameterUID=`jq -r '.uid' ./metadata.json | tr -d '\n\t'`
      echod "Picked from Metadata: "$parameterUID

      PROJECT_PARAM_GET_URL=${LOCAL_DEV_URL}/apis/v1/rest/projects/${repoName}/params/${parameterUID}
      echod ${PROJECT_PARAM_GET_URL}
      ppListJson=$(curl --location --request GET ${PROJECT_PARAM_GET_URL}  \
        --header 'Content-Type: application/json' \
        --header 'Accept: application/json' \
        -u ${admin_user}:${admin_password})

      # CHANGE 1: use -r so ppExport is not quoted
      ppExport=$(echo "$ppListJson" | jq -r '.output.uid // empty')
      echod ${ppExport}

      if [ -z "$ppExport" ]; then
        echo "Project parameters does not exists, creating ..:"
        PROJECT_PARAM_CREATE_URL=${LOCAL_DEV_URL}/apis/v1/rest/projects/${repoName}/params
        echod ${PROJECT_PARAM_CREATE_URL}
        parameterJSON=`jq -c '.' ./*_${source_type}.json`

        echod "Param JSON: "${parameterJSON}
        echod "curl --location --request POST ${PROJECT_PARAM_CREATE_URL}  \
        --header 'Content-Type: application/json' \
        --header 'Accept: application/json' \
        --data-raw "$parameterJSON" -u ${admin_user}:${admin_password})"
        
        ppCreateJson=$(curl --location --request POST ${PROJECT_PARAM_CREATE_URL}  \
          --header 'Content-Type: application/json' \
          --header 'Accept: application/json' \
          --data-raw "$parameterJSON" -u ${admin_user}:${admin_password})
        ppCreatedJson=$(echo "$ppCreateJson" | jq '.output.uid // empty')
        if [ -z "$ppCreatedJson" ]; then
          echo "Project Paraters Creation failed:" ${ppCreateJson}
        else
          echo "Project Paraters Creation Succeeded, UID:" ${ppCreatedJson}
        fi
      else
        echo "Project parameters does exists, updating ..:"
        PROJECT_PARAM_UPDATE_URL=${LOCAL_DEV_URL}/apis/v1/rest/projects/${repoName}/params/${parameterUID}
        echod ${PROJECT_PARAM_UPDATE_URL}

        # CHANGE 2: replace the hanging 'jq -c .' with a safe, piped debug
        echo "$ppListJson" | jq -c .
        echod "Files here: $(ls -1)"
        # prefer env-specific file; else use the first *.json
        if compgen -G "./*_${source_type}.json" > /dev/null; then
          param_file="$(ls -1 ./*_"$source_type".json | head -n1)"
        else
          param_file="$(ls -1 ./*.json | head -n1)"
        fi

        if [ -z "$param_file" ]; then
          echo "Param JSON not found (looked for ./*_${source_type}.json then ./*.json)"
          exit 1
        fi

        echod "Using Param file: $param_file"
        parameterJSON="$(jq -c '.' "$param_file")"


        echod "Param: "${parameterJSON}
        ppUpdateJson=$(curl --location --request PUT ${PROJECT_PARAM_UPDATE_URL}  \
          --header 'Content-Type: application/json' \
          --header 'Accept: application/json' \
          -d ${parameterJSON} -u ${admin_user}:${admin_password})
        ppUpdatedJson=$(echo "$ppUpdateJson" | jq '.output.uid // empty')
        if [ -z "$ppUpdatedJson" ]; then
          echo "Project Paraters Update failed:" ${ppUpdateJson}
        else
          echo "Project Paraters Update Succeeded, UID:" ${ppUpdatedJson}
        fi       
      fi
    else
      echo "Invalid Project Parameter / Asset Id to import."
    fi
  else 
    echo "No Project Parameters to import."
  fi 
}


function importSingleRefData(){
  LOCAL_DEV_URL=$1
  admin_user=$2
  admin_password=$3
  repoName=$4
  assetID=$5
  assetType=$6
  HOME_DIR=$7
  synchProject=$8
  source_type=$9
  projectID=${10}
  d=$assetID

  cd ${HOME_DIR}/${repoName}
  #Importing Reference Data
  DIR="./assets/projectConfigs/referenceData/"
  if [ -d "$DIR" ]; then
    echod "Project referenceData needs to be synched"
    echod "ProjectID:" ${projectID}
    cd ./assets/projectConfigs/referenceData/
    if [ -d "$d" ]; then
      refDataName="$d"
      echod "$d"
      cd "$d"
      description=$(jq -r .description metadata.json)
      columnDelimiter=$(jq -r .columnDelimiter metadata.json)
      encodingType=$(jq -r .encodingType metadata.json)
      releaseCharacter=$(jq -r .releaseCharacter metadata.json)
      FILE=./${source_type}.csv
      formKey="file=@"${FILE}
      echod ${formKey} 
      REF_DATA_URL=${LOCAL_DEV_URL}/apis/v1/rest/projects/${repoName}/referencedata/${refDataName}
      
      rdJson=$(curl --location --request GET ${REF_DATA_URL}  \
        --header 'Content-Type: application/json' \
        --header 'Accept: application/json' \
        -u ${admin_user}:${admin_password})
        rdExport=$(echo "$rdJson" | jq '.output // empty')
        if [ -z "$rdExport" ];   then
          echod "Refrence Data does not exists, Creating ....:" ${refDataName}
          POST_REF_DATA_URL=${LOCAL_DEV_URL}/apis/v1/rest/projects/${repoName}/referencedata
          method="POST"               
        else
          echod "Refrence Data exists, Updating ....:" ${refDataName}
          POST_REF_DATA_URL=${LOCAL_DEV_URL}/apis/v1/rest/projects/${repoName}/referencedata/${refDataName}
          method="PUT"   
        fi
        projectPostJson=$(curl --location --request ${method} ${POST_REF_DATA_URL} \
            --header 'Accept: application/json' \
            --form 'name='"$refDataName" \
            --form 'description='"$description" \
            --form 'field_separator='"$columnDelimiter" \
            --form 'text_qualifier='"$releaseCharacter" \
            --form 'file_encoding='"$encodingType" \
            --form ${formKey} -u ${admin_user}:${admin_password})  
        refDataOutput=$(echo "$projectPostJson" | jq -r -c '.integration.message.description')
        if [ "$refDataOutput"=="Success" ];   then
          echod "Reference Data created/updated successfully"
        else
          echod "Reference Data failed:" ${projectPostJson}
        fi
      cd -
    fi
  fi
  cd ${HOME_DIR}/${repoName}

}

function importRefData(){ 
  LOCAL_DEV_URL=$1
  admin_user=$2
  admin_password=$3
  repoName=$4
  assetID=$5
  assetType=$6
  HOME_DIR=$7
  synchProject=$8
  source_type=$9
  
  cd ${HOME_DIR}/${repoName}
  ls -ltr

  #Importing Reference Data
  DIR="./assets/projectConfigs/referenceData/"
  if [ -d "$DIR" ]; then
      echo "Project referenceData needs to be synched"
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
      cd ./assets/projectConfigs/referenceData/
      for d in * ; do
        importSingleRefData ${LOCAL_DEV_URL} ${admin_user} ${admin_password} ${repoName} ${d} ${assetType} ${HOME_DIR} ${synchProject} ${source_type} ${projectID}
        done
  fi
 cd ${HOME_DIR}/${repoName}

}

function importConnections(){ 
  LOCAL_DEV_URL=$1
  admin_user=$2
  admin_password=$3
  repoName=$4
  assetID=$5
  assetType=$6
  HOME_DIR=$7
  synchProject=$8
  source_type=$9
  
  cd "${HOME_DIR}/${repoName}" || exit 1
  ls -ltr

  # Importing Connections
  DIR="./assets/connections/"
  connection_folders=("$DIR"*/)

  if [ ${#connection_folders[@]} -gt 0 ]; then
    # Setup Azure Key Vault (only once)
    if [ "$provider" == "azure" ]; then
      "$HOME_DIR/self/pipelines/scripts/secrets/vault/azure/setupAzureKeyVault.sh" "$vaultName" "$resourceGroup" "$location" "$azure_tenant_id" "$sp_app_id" "$sp_password" "$access_object_id" debug
    fi

    for folder in "$DIR"*/; do 
        account_name="$(basename "$folder")"
        matching_file=$(find "$folder" -type f -name "*-${source_type}.json" | head -n 1)

        if [ -n "$matching_file" ]; then
          base_name=$(basename "$matching_file" .json)
          echod "📦 Importing connection: $base_name from account folder: $account_name"
          
          importSingleConnection "$LOCAL_DEV_URL" "$admin_user" "$admin_password" "$repoName" "$account_name" "$assetType" "$HOME_DIR" "$synchProject" "$source_type"
        else
          echod "⚠️  No file found for env '$source_type' in account '$account_name'"
        fi
    done
  else
    echod "No connections to import"
  fi

  cd "${HOME_DIR}/${repoName}" || exit 1
}

function unmaskFieldsInJson() {
  local json_input="$1"
  local account_name="$2"
  local repo_name="$3"
  local env="$4"
  local HOME_DIR="$5"
  local provider="$6"
  local vaultName="$7"   # Vault name (Azure) or repoUser (GitHub/Bitbucket)

  local project_config_file="$HOME_DIR/$repo_name/project-config.yml"
  local unmasked_json="$json_input"

  # Read secrets list for this account from YAML
  mapfile -t fields < <(yq eval ".project.accounts.\"$account_name\".secrets[]" "$project_config_file")

  for field in "${fields[@]}"; do
    fullSecretName="Project-${repo_name}-Account-${account_name}-Field-${field}-Env-${env}"
    fullSecretName=$(echo "$fullSecretName" | sed 's/_/-/g')

    secret_value=$("$HOME_DIR/self/pipelines/scripts/getSecret.sh" "$provider" "$fullSecretName" "$vaultName" "$HOME_DIR" "$debug")

    if [[ -z "$secret_value" || "$secret_value" == "null" ]]; then
      echo "⚠️  Secret not found for $fullSecretName. Skipping."
      continue
    fi

    unmasked_json=$(echo "$unmasked_json" | jq --arg field "$field" --arg secret "$secret_value" '
      (.. | objects | select(has($field)) | select(.[ $field ] == "****MASKED****"))[$field] |= $secret
    ')
  done

  echo "$unmasked_json"
}


function importSingleConnection(){
  LOCAL_DEV_URL=$1
  admin_user=$2
  admin_password=$3
  repoName=$4
  assetID=$5
  assetType=$6
  HOME_DIR=$7
  synchProject=$8
  source_type=$9
  folder=$assetID

  cd ${HOME_DIR}/${repoName}
  #Importing Reference Data
  folder="./assets/connections/$folder"
  account_name="$(basename "$folder")"
  echod "Importing Connection $account_name from $folder"
  # Find JSON file for target environment
  matching_file=$(find "$folder" -type f -name "*-${source_type}.json" | head -n 1)
  if [ -n "$matching_file" ]; then
    base_name=$(basename "$matching_file" .json)
    echod "📦 Importing connection: $base_name from account folder: $account_name"
    # 🛡️ Unmask the JSON before import
    unmasked_json=$(unmaskFieldsInJson "$(cat "$matching_file")" "$account_name" "${repoName}" "${source_type}" "${HOME_DIR}" "$provider" "$vaultName")

    CONN_GET_URL=${LOCAL_DEV_URL}/apis/v1/rest/projects/${repoName}/configurations/connections
    getresponse=$(curl --silent --location --request GET "$CONN_GET_URL" \
        --header 'Content-Type: application/json' \
        --header 'Accept: application/json' \
        -u "${admin_user}:${admin_password}")


    #Logic to check if ${account_name}
    account_exists=$(echo "$getresponse" | jq -r ".output[]?.name" | grep -Fx "$account_name" || true)

    if [ -n "$account_exists" ]; then
      echod "🔄 Account '$account_name' exists. Using PUT to update."
      createMethod=PUT
    else
      echod "➕ Account '$account_name' does not exist. Using POST to create."
      createMethod=POST
    fi

    CONN_CREATE_URL=${LOCAL_DEV_URL}/apis/v1/rest/projects/${repoName}/configurations/connections/${account_name}
    # Import using PUT
    response=$(curl --silent --location --request "$createMethod" "$CONN_CREATE_URL" \
        --header 'Content-Type: application/json' \
        --header 'Accept: application/json' \
        -u "${admin_user}:${admin_password}" \
        --data-raw "$unmasked_json")

    connimport=$(echo "$response" | jq -r -c '.output.name // empty')
    if [ -z "$connimport" ];   then
      echod "❌ Connection '$account_name' could not be imported. Response: $response"
    else
      echod "✅ Import successful for '$account_name'"
    fi

  else
    echod "⚠️  No file found for env '$source_type' in account '$account_name'"
  fi
  cd - >/dev/null
  cd ${HOME_DIR}/${repoName}
}

function projectParameters(){
 # Importing Project Parameters
  LOCAL_DEV_URL=$1
  admin_user=$2
  admin_password=$3
  repoName=$4
  assetID=$5
  assetType=$6
  HOME_DIR=$7
  synchProject=$8
  source_type=$9
  echod $(pwd)
  echod $(ls -ltr)

  DIR="./assets/projectConfigs/parameters/"
  if [ -d "$DIR" ]; then
      echo "Project Parameters needs to be synched"
      cd ./assets/projectConfigs/parameters/
      for d in * ; do
        importSingleProjectParameters ${LOCAL_DEV_URL} ${admin_user} ${admin_password} ${repoName} ${d} ${assetType} ${HOME_DIR} ${synchProject} ${source_type} ${projectID}
      done
  else 
      echo "No Project Parameters to import."
  fi
  cd ${HOME_DIR}/${repoName}

}

function splitAndImportAssets() {

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
  local desiredOrder=(  )

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
        importAsset ${LOCAL_DEV_URL} ${admin_user} ${admin_password} ${repoName} ${assetNames[$i]} ${assetTypes[$i]} ${HOME_DIR} ${synchProject} ${includeAllReferenceData}
      fi
    done
  done
}

cd ${HOME_DIR}/${repoName}


if [ ${synchProject} == true ]; then

  # Connections import
  assetID=${assetIDList}
  assetType=Connection
  importConnections ${LOCAL_DEV_URL} ${admin_user} ${admin_password} ${repoName} ${assetID} ${assetType} ${HOME_DIR} ${synchProject} ${source_type}

  # APIs import
  echod "Listing files"
  shopt -s nullglob dotglob
  api_files=(./assets/rest_api/*.zip)
  if [ ${#api_files[@]} -gt 0 ]; then
    for filename in ./assets/rest_api/*.zip; do 
        base_name=${filename##*/}
        parent_name="$(basename "$(dirname "$filename")")"
        base_name=${base_name%.*}
        echod $base_name${filename%.*}
        echod $parent_name
        importAsset ${LOCAL_DEV_URL} ${admin_user} ${admin_password} ${repoName} ${base_name} ${parent_name} ${HOME_DIR} ${synchProject} ${includeAllReferenceData}
    done
  else
    echod "No rest apis to import"
  fi

  # Workflows import
  shopt -s nullglob dotglob
  wf_files=(./assets/workflows/*.zip)
  if [ ${#wf_files[@]} -gt 0 ]; then
    for filename in ./assets/workflows/*.zip; do 
        base_name=${filename##*/}
        parent_name="$(basename "$(dirname "$filename")")"
        base_name=${base_name%.*}
        echod $base_name${filename%.*}
        echod $parent_name
        importAsset ${LOCAL_DEV_URL} ${admin_user} ${admin_password} ${repoName} ${base_name} ${parent_name} ${HOME_DIR} ${synchProject} ${includeAllReferenceData}
    done
  else
    echod "No workflows to import"
  fi

  # Flowservices Import
  shopt -s nullglob dotglob
  fs_files=(./assets/flowservices/*.zip)
  if [ ${#fs_files[@]} -gt 0 ]; then
    for filename in ./assets/flowservices/*.zip; do 
        base_name=${filename##*/}
        parent_name="$(basename "$(dirname "$filename")")"
        base_name=${base_name%.*}
        echod $base_name${filename%.*}
        echod $parent_name
        importAsset ${LOCAL_DEV_URL} ${admin_user} ${admin_password} ${repoName} ${base_name} ${parent_name} ${HOME_DIR} ${synchProject} ${includeAllReferenceData}
    done
  else
    echod "No flowservices to import"
  fi

  # DAFServices import
  shopt -s nullglob dotglob
  fs_files=(./assets/dafservices/*.zip)
  if [ ${#fs_files[@]} -gt 0 ]; then
    for filename in ./assets/dafservices/*.zip; do 
        base_name=${filename##*/}
        parent_name="$(basename "$(dirname "$filename")")"
        base_name=${base_name%.*}
        echod $base_name${filename%.*}
        echod $parent_name
        importAsset ${LOCAL_DEV_URL} ${admin_user} ${admin_password} ${repoName} ${base_name} ${parent_name} ${HOME_DIR} ${synchProject} ${includeAllReferenceData}
    done
  else
    echod "No DAFservices to import"
  fi
  assetID=${assetIDList}
  assetType=referenceData
  importRefData ${LOCAL_DEV_URL} ${admin_user} ${admin_password} ${repoName} ${assetID} ${assetType} ${HOME_DIR} ${synchProject} ${source_type}
  assetType=project_parameter
  projectParameters ${LOCAL_DEV_URL} ${admin_user} ${admin_password} ${repoName} ${assetID} ${assetType} ${HOME_DIR} ${synchProject} ${source_type}

else
  #importAsset ${LOCAL_DEV_URL} ${admin_user} ${admin_password} ${repoName} ${assetID} ${assetType} ${HOME_DIR} ${synchProject} ${includeAllReferenceData}
  # Clean it (remove spaces around commas)
  assetIDList=$(echo "$assetIDList" | sed 's/ *, */,/g')
  assetTypeList=$(echo "$assetTypeList" | sed 's/ *, */,/g')
  splitAndImportAssets ${LOCAL_DEV_URL} ${admin_user} ${admin_password} ${repoName} "$assetIDList" "$assetTypeList" ${HOME_DIR} ${synchProject} ${includeAllReferenceData}
fi 
set +x