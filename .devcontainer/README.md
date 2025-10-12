# Devcontainer

1. Adapt the `.devcontainer.env` file and fill in your credentials
2. Start the devcontainer

## Unit Tests

```sh
cd src/bosh_azure_cpi
bundle exec rspec spec/unit
```

## Integration Tests

Apply the terraform resources:

```sh
cd .devcontainer/infra
terraform apply -var-file=variables.tfvars -auto-approve
```

Run the integration specs with the following command:

```sh
cd src/bosh_azure_cpi
bundle exec rspec spec/integration
```
