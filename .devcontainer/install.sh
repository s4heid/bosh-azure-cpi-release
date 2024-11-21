#!/bin/bash

set -e

direnv allow

(
  echo "Installing project dependencies..."
  cd src/bosh_azure_cpi
  sudo ./bin/check-ruby-version

  sudo gem install ruby-lsp debug rubocop

  bundle config set --local path vendor/package
  bundle config set --local with "development:test"
  bundle install
)

cat <<EOF > ci/assets/terraform/integration/variables.tfvars
azure_client_id       = "${BOSH_AZURE_CLIENT_ID}"
azure_client_secret   = "${BOSH_AZURE_CLIENT_SECRET}"
azure_subscription_id = "${BOSH_AZURE_SUBSCRIPTION_ID}"
azure_tenant_id       = "${BOSH_AZURE_TENANT_ID}"
location              = "${BOSH_AZURE_LOCATION}"
azure_environment     = "${BOSH_AZURE_ENVIRONMENT}"
env_name              = "${ENVIRONMENT_NAME}"
resource_group_prefix = "${ENVIRONMENT_PREFIX}"
EOF

mkdir -p .local
if [ ! -f .local/cpi.cfg ]; then
  cat <<EOF > .local/cpi.cfg
---
azure:
  environment: ${BOSH_AZURE_ENVIRONMENT}
  subscription_id: ${BOSH_AZURE_SUBSCRIPTION_ID}
  storage_account_name: ${ENVIRONMENT_NAME}
  resource_group_name: ${ENVIRONMENT_PREFIX}${ENVIRONMENT_NAME}-default-rg
  tenant_id: ${BOSH_AZURE_TENANT_ID}
  client_id: ${BOSH_AZURE_CLIENT_ID}
  client_secret: ${BOSH_AZURE_CLIENT_SECRET}
  ssh_user: vcap
  ssh_public_key: ${BOSH_AZURE_SSH_PUBLIC_KEY}
  default_security_group: azure_bosh_nsg
  debug_mode: false
  use_managed_disks: true
registry:
  endpoint: http://127.0.0.1:25695
  user: admin
  password: admin
EOF
fi

echo "--------------"
echo "Please run the following commands to prepare your infrastructure for the integration tests:"
echo
echo "  \$ cd ci/assets/terraform/integration"
echo "  \$ terraform init"
echo "  \$ terraform apply -var-file=variables.tfvars -auto-approve"
echo
echo "Then run the following commands to run the integration tests:"
echo "  \$ cd src/bosh_azure_cpi"
echo "  \$ bundle exec rspec spec/integration"
echo
echo "To clean up the infrastructure, run the following command:"
echo "  \$ terraform destroy -var-file=variables.tfvars -auto-approve"
echo
echo "VsCode Plugins:"
echo "  >SimpleCov: Apply Coverage"
echo "  >SimpleCov: Remove Coverage"
echo "  >Tasks: Run Test Task"
echo "  >Ruby LSP: Start"

# git apply .devcontainer/tf.patch