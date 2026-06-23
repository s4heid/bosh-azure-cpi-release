#!/usr/bin/env bash
set -eu -o pipefail

# Uploads the heavy stemcell at .devcontainer/stemcell.tgz to the integration
# test storage account and exports BOSH_AZURE_STEMCELL_ID for rspec runs.
#
# Requires the BOSH_AZURE_* env vars from ci/tasks/run-integration.sh to be
# exported (subscription, tenant, client, storage account, default rg, ...).
#
# Usage:
#   source .devcontainer/upload-stemcell.sh

: "${BOSH_AZURE_ENVIRONMENT:?}"
: "${BOSH_AZURE_TENANT_ID:?}"
: "${BOSH_AZURE_SUBSCRIPTION_ID:?}"
: "${BOSH_AZURE_CLIENT_ID:?}"
: "${BOSH_AZURE_CLIENT_SECRET:?}"
: "${BOSH_AZURE_DEFAULT_RESOURCE_GROUP_NAME:?}"
: "${BOSH_AZURE_STORAGE_ACCOUNT_NAME:?}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STEMCELL_TGZ="${STEMCELL_TGZ:-${SCRIPT_DIR}/stemcell.tgz}"

if [ ! -f "${STEMCELL_TGZ}" ]; then
  echo "Stemcell tarball not found at ${STEMCELL_TGZ}" >&2
  exit 1
fi

az cloud set --name "${BOSH_AZURE_ENVIRONMENT}"
az login --service-principal \
  -u "${BOSH_AZURE_CLIENT_ID}" \
  -p "${BOSH_AZURE_CLIENT_SECRET}" \
  --tenant "${BOSH_AZURE_TENANT_ID}" >/dev/null
az account set -s "${BOSH_AZURE_SUBSCRIPTION_ID}"

account_name="${BOSH_AZURE_STORAGE_ACCOUNT_NAME}"
account_key=$(az storage account keys list \
  --account-name "${account_name}" \
  --resource-group "${BOSH_AZURE_DEFAULT_RESOURCE_GROUP_NAME}" \
  | jq -r '.[0].value')

stemcell_id="bosh-stemcell-00000000-0000-0000-0000-0AZURECPICI0"
echo "Using heavy stemcell: '${stemcell_id}'"

work_dir=$(mktemp -d)
trap 'rm -rf "${work_dir}"' EXIT

tar -xf "${STEMCELL_TGZ}" -C "${work_dir}"
tar -xf "${work_dir}/image" -C "${work_dir}"

az storage blob upload \
  --file "${work_dir}/root.vhd" \
  --container-name stemcell \
  --name "${stemcell_id}.vhd" \
  --type page \
  --account-name "${account_name}" \
  --account-key "${account_key}" \
  --overwrite

export BOSH_AZURE_STEMCELL_ID="${stemcell_id}"
echo "Exported BOSH_AZURE_STEMCELL_ID=${BOSH_AZURE_STEMCELL_ID}"
