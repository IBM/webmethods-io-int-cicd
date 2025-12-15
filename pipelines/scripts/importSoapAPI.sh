################################################################################################################################################################
# Summary:
#   Imports a SOAP API asset (or recipe) into a given project repository by uploading the corresponding ZIP file to the platform.
#   It supports conditional handling for SOAP APIs and other asset types, including validation of the import status.
#
# Usage:
#   importSOAPAsset <LOCAL_DEV_URL> <admin_user> <admin_password> <repoName> <assetID> <assetType> <HOME_DIR>
#
# Mandatory Fields:
#   LOCAL_DEV_URL   - Base URL of the local dev environment (e.g., http://localhost:5555)
#   admin_user      - Admin username for authentication
#   admin_password  - Admin password for authentication
#   repoName        - Name of the repository/project where the asset will be imported
#   assetID         - ID of the asset to be imported (corresponds to the ZIP filename)
#   assetType       - Type of the asset (e.g., soap_api, recipe)
#   HOME_DIR        - Path to the base working directory
################################################################################################################################################################



function importSOAPAsset() {
  LOCAL_DEV_URL=$1
  admin_user=$2
  admin_password=$3
  repoName=$4
  assetID=$5
  assetType=$6
  HOME_DIR=$7

  echo "Current directory: $(pwd)"
  ls -ltr
  echo "AssetType: $assetType"

  if [[ $assetType = soap_api* ]]; then
    IMPORT_URL=${LOCAL_DEV_URL}/apis/v1/rest/project-import
    cd ${HOME_DIR}/${repoName}/assets/soap_api
    echo "SOAP API Import: ${IMPORT_URL}"
    ls -ltr
  fi

  echo "Import URL: ${IMPORT_URL}"
  echo "Working Dir: ${PWD}"

  FILE=./${assetID}.zip
  if [[ $assetType = soap_api* ]]; then
    formKey="project=@${FILE}"
  else
    formKey="recipe=@${FILE}"
  fi

  overwriteKey="overwrite=true"
  echo "Form key: ${formKey}"

  if [ -f "$FILE" ]; then
    echo "$FILE exists. Importing ..."
    importedName=$(curl --location --request POST ${IMPORT_URL} \
      --header 'Content-Type: multipart/form-data' \
      --header 'Accept: application/json' \
      --form ${formKey} --form ${overwriteKey} \
      -u ${admin_user}:${admin_password})

    if [[ $assetType = soap_api* ]]; then
      name=$(echo "$importedName" | jq -r '.output.message // empty')
      success="IMPORT_SUCCESS"
      if [ "$name" == "$success" ]; then
        echo "Import Succeeded: ${importedName}"
      else
        echo "Import Failed: ${importedName}"
      fi
    else
      name=$(echo "$importedName" | jq -r '.output.name // empty')
      if [ -z "$name" ]; then
        echo "Import failed: ${importedName}"
      else
        echo "Import Succeeded: ${importedName}"
      fi
    fi
  else
    echo "$FILE does not exist, Nothing to import"
  fi

  cd ${HOME_DIR}/${repoName}
}