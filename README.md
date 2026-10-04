# NetValue deployment

Infrastructure and deployment configuration for [NetValue](https://github.com/JeffCousineau/NetValue).

This repository will contain Terraform and GitHub Actions workflows for Azure App Service, Azure SQL, managed identity, and Key Vault. Application source and database migrations belong in the NetValue repository.

Store secret values in Azure Key Vault or GitHub environment secrets, never in Git. Use GitHub OIDC for Azure deployment authentication. Keep Terraform state in a protected Azure Storage backend; local state, variable files, plan files, credentials, and certificates are excluded from this repository. Commit .terraform.lock.hcl when providers are configured.

Infrastructure and pipelines have not been implemented yet.
