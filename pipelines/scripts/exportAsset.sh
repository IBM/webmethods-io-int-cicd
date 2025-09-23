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

function maskFieldsInJson() {
  local json_input="$1"   # full account JSON
  local key="$2"          # account name (for secret naming)
  shift 2
  local fields_override=("$@")  # optional: explicit fields for this call

  local masked_json="$json_input"

  # --- Detect provider / type from JSON ----------------------------
  local providerName
  providerName="$(echo "$json_input" | jq -r '.sourceMetadata.providerName // .sourceMetadata.connectorType // .type // empty')"

  # --- Build the allow-list (Pass 1) -------------------------------
  # If caller provided explicit fields, use them; else use per-provider map.
  local exact_fields=()
  if [[ ${#fields_override[@]} -gt 0 ]]; then
    exact_fields=("${fields_override[@]}")
  else
    case "$providerName" in
      google_sheet|google_sheet_oauth|oauth2)
        # JSON has "data.client_id" etc.
        exact_fields=( "data.client_id" "data.client_secret" "data.access_token" "data.refresh_token" )
        ;;
      WmRESTProvider|CustomREST)
        # JSON has dotted keys inside data.*
        exact_fields=( "data.oauth.accessToken" "data.oauth.consumerSecret" "data.oauth_v20.refreshToken" "data.oauth.consumerId" )
        ;;
      *)
        exact_fields=()  # unknown → fallback only
        ;;
    esac
  fi

  # Helper: add paths to a bash array from jq
  _collect_paths() {
    local input_json="$1"; shift
    local -a endswith_list=("$@")
    if [[ ${#endswith_list[@]} -eq 0 ]]; then return 0; fi
    # Build JSON array of patterns
    local wants; wants="$(printf '%s\n' "${endswith_list[@]}" | jq -R . | jq -s .)"
    echo "$input_json" | jq -r --argjson W "$wants" '
      paths(strings) as $p
      | ( $p | map(tostring) | join(".") ) as $jp
      | select( any($W[]; $jp | endswith(.)) )
      | @json
    '
  }

  # Pass 1: exact fields (by suffix match on the full dotted path)
  mapfile -t p1_paths < <(_collect_paths "$masked_json" "${exact_fields[@]}")

  # --- Pass 2: generic suffixes with exclusions --------------------
  # Normalize to last-key-only suffix; exclude things like token_type, *RefreshURL, *Request, etc.
  mapfile -t p2_paths < <(
    echo "$masked_json" | jq -r '
      paths(strings)
      | select((.[-1]|type)=="string")
      | . as $p
      | (.[-1] | ascii_downcase | gsub("[^a-z0-9]"; "")) as $last
      | select(
          # include when the last key ends with one of these:
          ($last | test("(clientid|clientsecret|password|secret|accesstoken|refreshtoken|apikey)$"))
          and
          # but NOT these endings (exclusions):
          ($last | test("(tokentype|refreshurl|refreshurlrequest|customesbservice|authorizationheader|expiry|expiresin)$") | not)
        )
      | @json
    '
  )

  # Merge paths (p1 first, then p2), unique by JSON text
  declare -A seen=()
  local all_paths=()
  for x in "${p1_paths[@]}" "${p2_paths[@]}"; do
    [[ -z "$x" ]] && continue
    if [[ -z "${seen[$x]:-}" ]]; then
      seen[$x]=1
      all_paths+=("$x")
    fi
  done

  # Nothing to mask? return as-is
  if [[ ${#all_paths[@]} -eq 0 ]]; then
    echod "🔍 No sensitive fields matched for '$key' (provider: ${providerName:-unknown})"
    echo "$masked_json"
    return 0
  fi

  # --- Apply masking + secret storage ---------------------------------------
  for path in "${all_paths[@]}"; do
    # Actual key name and value at the path
    local found_key value
    found_key="$(jq -r --argjson p "$path" '$p | .[-1]' <<< 'null')"
    value="$(echo "$masked_json" | jq -r --argjson p "$path" 'getpath($p)')"

    # Skip empties/nulls
    [[ -z "$value" || "$value" == "null" ]] && continue

    # Persist secret per env
    IFS=, read -ra envs <<< "$envTypes"
    for v in "${envs[@]}"; do
      local fullSecretName="Project-${repoName}-Account-${key}-Field-${found_key}-Env-${v}"
      fullSecretName="$(echo "$fullSecretName" | sed 's/[_.]/-/g')"

      if [ "$provider" == "azure" ]; then
        "$HOME_DIR/self/pipelines/scripts/putSecrets.sh" "$provider" "$fullSecretName" "$value" "$vaultName" unused unused "$HOME_DIR" debug
      else
        "$HOME_DIR/self/pipelines/scripts/putSecrets.sh" "$provider" "$fullSecretName" "$value" "$repoUser" "$repoName" "$PAT" "$HOME_DIR" debug
      fi

      # Update YAML with the exact key name that was masked
      yq eval -i \
        ".project.accounts.\"${key}\".secrets = ((.project.accounts.\"${key}\".secrets // []) + [\"${found_key}\"] | unique)" \
        "$PROJECT_CONFIG_FILE"
    done

    # Mask it in the JSON
    masked_json="$(echo "$masked_json" | jq --argjson p "$path" 'setpath($p; "****MASKED****")')"
  done

  echo "$masked_json"
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
            #maskedJson=$(maskFieldsInJson "$item" "$name" client_id client_secret access_token refresh_token)
            maskedJson=$(maskFieldsInJson "$item" "$name")
            echo "$maskedJson" > ${name}_${source_type}.json
            configPerEnv . ${envTypes} "connection" ${name}_${source_type}.json $name
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

function configPerEnv(){
  localtion=$1
  envTypes=$2
  configType=$3
  sourceFile=$4
  key=$5

  IFS=, read -ra values <<< "$envTypes"
  for v in "${values[@]}"
  do
     # things with "$v"
     if [ ${configType} == "referenceData" ]; then
        cp ./$sourceFile ./$v.csv
     else
        if [[ "$configType" == "project_parameter" || "$configType" == "connection" ]]; then
            cp ./$sourceFile ./${key}-${v}.json
         fi
      fi
  done

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
        linkJson=$(curl  --location --request POST ${EXPORT_URL} \
        --header 'Content-Type: application/json' \
        --header 'Accept: application/json' \
        -u ${admin_user}:${admin_password})
      fi
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
  local desiredOrder=("referenceData" "rest_api" "project_parameter" "workflow" "flowservice" "dafservice")

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
                  echo ${data} > ./${key}_${source_type}.json
                  configPerEnv . ${envTypes} "project_parameter" ${key}_${source_type}.json ${key}
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
                  echo ${data} > ./${key}_${source_type}.json
                  configPerEnv . ${envTypes} "project_parameter" ${key}_${source_type}.json ${key}
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
  
else

# Input variables
#assetIDList=" AssetX ,AssetY , AssetZ,AssetA,AssetB ,AssetC "
#assetTypeList="flowservice , workflow, referenceData,dafservice, project_parameter , rest_api "
assetIDList=$(echo "$assetIDList" | sed 's/ *, */,/g')
assetTypeList=$(echo "$assetTypeList" | sed 's/ *, */,/g')
splitAndExportAssets ${LOCAL_DEV_URL} ${admin_user} ${admin_password} ${repoName} "$assetIDList" "$assetTypeList" ${HOME_DIR} ${synchProject} ${includeAllReferenceData}
fi  
