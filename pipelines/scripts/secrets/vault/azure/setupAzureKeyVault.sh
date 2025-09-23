#!/bin/bash
#############################################################################
# setupAzureKeyVault.sh : Initializes Azure Key Vault.
#############################################################################

# ---- Safety & sane defaults ------------------------------------------------
set -Eeuo pipefail
trap 'echo "ERROR at line $LINENO" >&2' ERR
export AZURE_CORE_COLLECT_TELEMETRY=false
export AZURE_HTTP_USER_AGENT="wmio-devops/ci"

# ---- Input parameters ------------------------------------------------------
VAULT_NAME=$1             # e.g. kv-myproject
RESOURCE_GROUP=$2         # e.g. my-rg
LOCATION=$3               # e.g. westeurope
TENANT_ID=$4              # Azure AD tenant ID
SP_APP_ID=$5              # Service Principal App ID (client_id)
SP_PASSWORD=$6            # Service Principal password (client_secret)
ACCESS_OBJECT_ID=${7:-}   # Optional: Object ID to grant access
DEBUG="${@: -1}"          # Optional: "debug" or "true" enables verbose logs

# ---- Debug handling (avoid leaking secrets) --------------------------------
# We will NOT keep xtrace on around az login to prevent echoing the secret.
DEBUG_XTRACE=0
if [[ "$DEBUG" == "debug" || "$DEBUG" == "true" ]]; then
  echo "🔍 Running in debug mode" >&2
  set -x
  DEBUG_XTRACE=1
fi

echod() { echo "$@" >&2; }

# ---- Validation ------------------------------------------------------------
if [[ -z "${VAULT_NAME:-}" || -z "${RESOURCE_GROUP:-}" || -z "${LOCATION:-}" || -z "${TENANT_ID:-}" || -z "${SP_APP_ID:-}" || -z "${SP_PASSWORD:-}" ]]; then
  echod "❌ Missing required parameters."
  echod "Usage: ./setupAzureKeyVault.sh <vault_name> <resource_group> <location> <tenant_id> <sp_app_id> <sp_password> [access_object_id] [debug]"
  exit 1
fi

# ---- Trim inputs -----------------------------------------------------------
SP_APP_ID="$(echo "$SP_APP_ID" | xargs)"
ACCESS_OBJECT_ID="$(echo "${ACCESS_OBJECT_ID:-}" | xargs)"
TENANT_ID="$(echo "$TENANT_ID" | xargs)"

# ---- Heartbeat to keep logs alive ------------------------------------------
( while :; do echo "[hb] $(date -Is) setupAzureKeyVault.sh"; sleep 20; done ) & HB=$!

# ---- Retry helper ----------------------------------------------------------
retry() {
  # usage: retry <cmd...>
  local n=0 max=5 delay=2
  until "$@"; do
    n=$((n+1))
    if (( n >= max )); then
      return 1
    fi
    echod "⏳ Retry $n/$max in ${delay}s..."
    sleep "$delay"
    delay=$(( delay * 2 ))
  done
}

# ---- Ensure Azure CLI exists (Microsoft-hosted agents usually have it) -----
if ! command -v az &>/dev/null; then
  echod "📦 Installing Azure CLI..."
  curl -sL https://aka.ms/InstallAzureCLIDeb | bash >/dev/null
fi

# ---- Cloud context (fast no-op if already set) -----------------------------
retry timeout 15s az cloud set --name AzureCloud >/dev/null 2>&1 || true

# ---- Login (no xtrace here to avoid leaking the secret) --------------------
echod "🔐 Logging into Azure..."
if (( DEBUG_XTRACE )); then set +x; fi
if ! retry timeout 60s az login --service-principal \
      -u "$SP_APP_ID" \
      -p "$SP_PASSWORD" \
      --tenant "$TENANT_ID" \
      --allow-no-subscriptions \
      --output none --only-show-errors; then
  echod "❌ Azure login failed."
  (( DEBUG_XTRACE )) && set -x
  kill "$HB" 2>/dev/null || true
  exit 1
fi
(( DEBUG_XTRACE )) && set -x

# ---- Pin subscription if provided (speeds up everything) -------------------
if [[ -n "${SUBSCRIPTION_ID:-}" ]]; then
  retry timeout 20s az account set --subscription "$SUBSCRIPTION_ID" --only-show-errors >/dev/null
fi

# Quick sanity (and warms the token cache)
retry timeout 20s az account show -o none --only-show-errors

# ---- Resource Group --------------------------------------------------------
echod "📁 Checking resource group '$RESOURCE_GROUP'..."
if ! timeout 30s az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
  echod "📁 Resource group not found, creating..."
  retry timeout 90s az group create \
    --name "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --only-show-errors >/dev/null
fi

# ---- Key Vault -------------------------------------------------------------
echod "🔐 Checking key vault '$VAULT_NAME'..."
if ! timeout 30s az keyvault show --name "$VAULT_NAME" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
  echod "🚀 Creating key vault '$VAULT_NAME'..."
  retry timeout 120s az keyvault create \
    --name "$VAULT_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --enable-rbac-authorization true \
    --only-show-errors >/dev/null
else
  echod "✅ Key vault '$VAULT_NAME' already exists."
fi

# ---- RBAC Role Assignment (optional) ---------------------------------------
if [[ -n "${ACCESS_OBJECT_ID:-}" ]]; then
  VAULT_SCOPE="/subscriptions/$(timeout 15s az account show --query id -o tsv)/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.KeyVault/vaults/$VAULT_NAME"

  echod "🔐 Assigning 'Key Vault Secrets Officer' at:"
  echod "   $VAULT_SCOPE"
  echod "   to objectId: $ACCESS_OBJECT_ID"

  if ! retry timeout 60s az role assignment create \
        --assignee-object-id "$ACCESS_OBJECT_ID" \
        --role "Key Vault Secrets Officer" \
        --scope "$VAULT_SCOPE" \
        --only-show-errors >/dev/null; then
    echod "❌ RBAC role assignment failed."
    echod "   The calling principal must have 'User Access Administrator' or 'Owner' on this scope."
    timeout 10s az account show --query "{signedInAs:user.name,subscription:id}" -o tsv 2>/dev/null \
      | xargs -I{} echod "   Context: {}"
    kill "$HB" 2>/devnull || true
    exit 1
  fi

  echod "✅ RBAC role assignment complete."
fi

kill "$HB" 2>/dev/null || true
echod "🎉 Azure Key Vault '$VAULT_NAME' is ready to use!"
