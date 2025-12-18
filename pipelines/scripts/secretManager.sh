#!/bin/bash
# Centralized secret management (Azure default) with provider-based field masking

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

YQ_BIN="${YQ_BIN:-$(command -v yq 2>/dev/null || true)}"
if [ -z "$YQ_BIN" ]; then
  echo "❌ yq not found on PATH; please install yq v4" >&2
  exit 1
fi

function echod() {
  if [ "$debug" == "debug" ]; then
    echo "$@" >&2
  fi
}

# Build secret name based on provider (Azure default: hyphenated, lowercase)
function buildSecretName() {
  local provider="$1"
  local wmioProject="$2"
  local accountName="$3"
  local fieldName="$4"
  local envName="$5"

  wmioProject=$(echo "${wmioProject}" | xargs | tr -d '"' | tr -d "'")
  accountName=$(echo "${accountName}" | xargs | tr -d '"' | tr -d "'")
  fieldName=$(echo "${fieldName}" | xargs | tr -d '"' | tr -d "'")
  envName=$(echo "${envName}" | xargs | tr -d '"' | tr -d "'")

  case "$provider" in
    azure|*)
      local base="Project-${wmioProject}-Account-${accountName}-Field-${fieldName}-Env-${envName}"
      echo "$base" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g'
      ;;
  esac
}

function storeSecret() {
  local provider="$1"
  local wmioProject="$2"
  local accountName="$3"
  local fieldName="$4"
  local envName="$5"
  local secretValue="$6"
  local vaultName="$7"
  local HOME_DIR="$8"

  local secretName
  secretName=$(buildSecretName "$provider" "$wmioProject" "$accountName" "$fieldName" "$envName")
  "${SCRIPT_DIR}/putSecrets.sh" "$provider" "$secretName" "$secretValue" "$vaultName" unused unused "$HOME_DIR" debug
}

function getSecret() {
  local provider="$1"
  local wmioProject="$2"
  local accountName="$3"
  local fieldName="$4"
  local envName="$5"
  local vaultName="$6"
  local HOME_DIR="$7"

  local secretName
  secretName=$(buildSecretName "$provider" "$wmioProject" "$accountName" "$fieldName" "$envName")
  "${SCRIPT_DIR}/getSecret.sh" "$provider" "$secretName" "$vaultName" "$HOME_DIR" "$debug"
}

# Mask sensitive fields in JSON and store secrets
function maskFieldsInJson() {
  local json_input="$1"
  local accountName="$2"
  local wmioProject="$3"
  local sourceEnv="$4"
  local provider="$5"
  local vaultName="$6"
  local HOME_DIR="$7"
  local envTypes="$8"

  local PROJECT_CONFIG_FILE="${HOME_DIR}/${wmioProject}/project-config.yml"
  local masked_json="$json_input"
  local fields=()

  local acct_type
  acct_type="$(echo "$json_input" | jq -r '.sourceMetadata.providerName // .sourceMetadata.connectorType // .type // empty')"
  case "$acct_type" in
    google_sheet|oauth2|WmSalesforceRESTProvider|WmSalesforceBulkProvider)
      fields=(client_id client_secret access_token refresh_token)
      ;;
    WmRESTProvider|CustomREST)
      fields=("oauth.consumerId" "oauth.consumerSecret" "oauth.accessToken" "oauth_v20.refreshToken")
      ;;
    WmHTTPProvider)
      fields=("cr.user" "cr.password" "client_secret" "access_token" "refresh_token")
      ;;
    WmJDBCAdapter)
      fields=("user" "username" "password")
      ;;
    WmSFTPProvider)
      fields=("userName" "username" "password" "privateKeyPassphrase")
      ;;
    sftp-v5)
      fields=("userName" "username" "password" "privateKey" "privateKeyPassphrase")
      ;;
    WmMessagingProvider)
      fields=()
      ;;
    *)
      fields=()
      ;;
  esac

  for field in "${fields[@]}"; do
    mapfile -t paths < <(echo "$masked_json" | jq -r "paths | select( (.[-1]|type)==\"string\" and (.[-1] == \"$field\") ) | @json")
    if [[ ${#paths[@]} -eq 0 ]]; then
      echod "🔍 Field '$field' not found, skipping..."
      continue
    fi

    for path in "${paths[@]}"; do
      value=$(echo "$masked_json" | jq -r "getpath($path)")
      IFS=, read -ra envs <<< "$envTypes"
      for env in "${envs[@]}"; do
        env=$(echo "$env" | xargs | tr -d '"' | tr -d "'")
        storeSecret "$provider" "$wmioProject" "$accountName" "$field" "$env" "$value" "$vaultName" "$HOME_DIR"
        if [ -f "$PROJECT_CONFIG_FILE" ]; then
          "$YQ_BIN" eval -i \
            ".project.accounts.\"${accountName}\".secrets = ((.project.accounts.\"${accountName}\".secrets // []) + [\"${field}\"] | unique)" \
            "$PROJECT_CONFIG_FILE"
        fi
      done
      masked_json=$(echo "$masked_json" | jq "setpath($path; \"****MASKED****\")")
    done
  done

  echo "$masked_json"
}

# Unmask sensitive fields in JSON by retrieving secrets
function unmaskFieldsInJson() {
  local json_input="$1"
  local accountName="$2"
  local wmioProject="$3"
  local targetEnv="$4"
  local provider="$5"
  local vaultName="$6"
  local HOME_DIR="$7"

  local PROJECT_CONFIG_FILE="${HOME_DIR}/${wmioProject}/project-config.yml"
  local unmasked_json="$json_input"

  if [ ! -f "$PROJECT_CONFIG_FILE" ]; then
    echod "⚠️  Project config file not found: $PROJECT_CONFIG_FILE"
    echo "$unmasked_json"
    return 0
  fi

  mapfile -t fields < <("$YQ_BIN" eval ".project.accounts.\"${accountName}\".secrets[]" "$PROJECT_CONFIG_FILE" 2>/dev/null || true)

  for field in "${fields[@]}"; do
    field=$(echo "$field" | xargs)
    secret_value=$(getSecret "$provider" "$wmioProject" "$accountName" "$field" "$targetEnv" "$vaultName" "$HOME_DIR")
    if [[ -z "$secret_value" || "$secret_value" == "null" ]]; then
      echod "⚠️  Secret not found for $accountName/$field/$targetEnv. Skipping."
      continue
    fi

    unmasked_json=$(echo "$unmasked_json" | jq --arg field "$field" --arg secret "$secret_value" '
      walk(
        if type == "object" and has($field) and .[$field] == "****MASKED****"
        then .[$field] = $secret
        else .
        end
      )
    ')
  done

  echo "$unmasked_json"
}
