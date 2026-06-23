#!/bin/bash

set -e

direnv allow

(
  echo "Installing Ruby LSP dependencies..."
  cd .devcontainer
  bundle install

  echo "Verifying the installation..."
  rdbg -v
  ruby-lsp -v
)

(
  echo "Installing project dependencies..."
  cd src/bosh_azure_cpi
  sudo ./bin/check-ruby-version

  bundle config set --local path vendor/package
  bundle config set --local with "development:test"
  bundle install --jobs 20 --retry 2
)

source .devcontainer/devcontainer.env

envsubst < .devcontainer/templates/cpi.cfg.tpl > .devcontainer/cpi.cfg

if [[ ! -d .devcontainer/infra ]]; then
    mkdir -p .devcontainer/infra

    pushd .devcontainer/infra
        envsubst < ../templates/variables.tfvars.tpl > variables.tfvars
        envsubst < ../templates/manifest.tf.tpl > manifest.tf

        terraform init

        # terraform plan -var-file=variables.tfvars
    popd
fi

echo "--------------"
echo "Run the following commands to prepare your infrastructure:"
echo
echo "  \$ cd .devcontainer/infra"
echo "  \$ terraform apply -var-file=variables.tfvars -auto-approve"
echo
echo "Run the following commands to execute the integration tests:"
echo "  \$ cd src/bosh_azure_cpi"
echo "  \$ bundle exec rspec spec/integration"
echo
echo "To clean up the infrastructure, run the following command:"
echo "  \$ terraform destroy -var-file=variables.tfvars -auto-approve"
echo
echo "--------------"
echo "To start the cpi console, run the following command:"
echo "  \$ cd src/bosh_azure_cpi"
echo "  \$ bundle exec bin/bosh_azure_console -c ../../.devcontainer/cpi.cfg"
echo
echo "Debugger"
echo "  \$ rdbg --open --command -- bundle exec rspec /workspaces/bosh-azure-cpi-release/src/bosh_azure_cpi/spec/unit/stemcell_manager2_spec.rb --tag focus"
echo
echo "Done!"
