#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/azure-cli.sh"
# Run once as an Azure owner who can create app registrations and assign RBAC.
subscription="0bc9dd71-16c4-428e-8160-8a90c7c892f5"
tenant="e099407c-b3b3-45aa-868e-cc901f513dc5"
suffix=$(printf '%s' "$subscription" | sha256sum | cut -c1-8)
state_account="nvstate${suffix}"
app_name="netvalue-${suffix}"
az account set --subscription "$subscription"
actual_tenant=$(az account show --query tenantId -o tsv)
if [[ "$actual_tenant" != "$tenant" ]]; then
  printf 'Azure directory mismatch. Expected: %s; actual: %s\n' "$tenant" "$actual_tenant" >&2
  exit 1
fi
for provider in Microsoft.Storage Microsoft.Web Microsoft.Sql; do
  az provider register --namespace "$provider" --wait --output none
done
az group create --name rg-netvalue-state --location canadacentral --output none
az group create --name rg-netvalue-free --location canadacentral --output none
if ! az storage account show --resource-group rg-netvalue-state --name "$state_account" --output none 2>/dev/null; then
  az storage account create --name "$state_account" --resource-group rg-netvalue-state --location canadacentral --sku Standard_LRS --kind StorageV2 --access-tier Hot --https-only true --min-tls-version TLS1_2 --allow-blob-public-access false --allow-shared-key-access false --output none
fi
state_id=$(az storage account show -g rg-netvalue-state -n "$state_account" --query id -o tsv)
owner_id=$(az ad signed-in-user show --query id -o tsv)
az role assignment create --assignee-object-id "$owner_id" --assignee-principal-type User --role 'Storage Blob Data Contributor' --scope "$state_id" --output none
container_ready=false
for attempt in $(seq 1 24); do
  if az storage container create --account-name "$state_account" --name tfstate --auth-mode login --public-access off --output none 2>/dev/null; then container_ready=true; break; fi
  sleep 5
done
[[ "$container_ready" == true ]] || { echo 'RBAC propagation incomplete. Rerun this script later.'; exit 1; }
identity_name="NetValue GitHub deployment ${suffix}"
app_count=$(az ad app list --display-name "$identity_name" --query 'length(@)' -o tsv)
[[ "$app_count" -le 1 ]] || { echo 'Duplicate deployment identities; resolve them before continuing.'; exit 1; }
if [[ "$app_count" == 0 ]]; then
  client_id=$(az ad app create --display-name "$identity_name" --query appId -o tsv)
  az ad sp create --id "$client_id" --output none
else client_id=$(az ad app list --display-name "$identity_name" --query '[0].appId' -o tsv); fi
principal_id=$(az ad sp show --id "$client_id" --query id -o tsv)
# Repository-bound immutable subject verified against GitHub's production OIDC token.
credential_file=$(mktemp)
trap 'rm -f "$credential_file"' EXIT
credential_path=$(azure_cli_path "$credential_file")
if az ad app federated-credential show --id "$client_id" --federated-credential-id github-production --output none 2>/dev/null; then
  printf '%s' '{"issuer":"https://token.actions.githubusercontent.com","subject":"repo:JeffCousineau@8643172/NetValue-deployment@1403790853:environment:production","audiences":["api://AzureADTokenExchange"]}' > "$credential_file"
  az ad app federated-credential update --id "$client_id" --federated-credential-id github-production --parameters "@$credential_path" --output none
else
  printf '%s' '{"name":"github-production","issuer":"https://token.actions.githubusercontent.com","subject":"repo:JeffCousineau@8643172/NetValue-deployment@1403790853:environment:production","audiences":["api://AzureADTokenExchange"]}' > "$credential_file"
  az ad app federated-credential create --id "$client_id" --parameters "@$credential_path" --output none
fi
az role assignment create --assignee-object-id "$principal_id" --assignee-principal-type ServicePrincipal --role Contributor --scope "/subscriptions/$subscription/resourceGroups/rg-netvalue-free" --output none
az role assignment create --assignee-object-id "$principal_id" --assignee-principal-type ServicePrincipal --role 'Storage Blob Data Contributor' --scope "$state_id/blobServices/default/containers/tfstate" --output none
printf '\nGitHub production environment variables:\nAZURE_CLIENT_ID=%s\nAZURE_TENANT_ID=%s\nAZURE_SUBSCRIPTION_ID=%s\nTF_STATE_ACCOUNT=%s\nAZURE_WEB_APP_NAME=%s\nSQL_SERVER_NAME=%s-sql\nDEPLOYMENT_PRINCIPAL_ID=%s\n' "$client_id" "$tenant" "$subscription" "$state_account" "$app_name" "$app_name" "$principal_id"
