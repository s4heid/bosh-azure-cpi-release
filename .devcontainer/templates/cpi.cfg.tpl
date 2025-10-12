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