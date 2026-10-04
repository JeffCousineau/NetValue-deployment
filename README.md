# NetValue deployment

Deployment configuration for [NetValue](https://github.com/JeffCousineau/NetValue), targeting subscription `0bc9dd71-16c4-428e-8160-8a90c7c892f5` in **Canada Central**.

## Cost choices

- Linux App Service **F1 Free**, with Always On disabled. Limited CPU time and five concurrent WebSocket connections; idle shutdowns/reconnects are expected.
- Azure SQL free offer: `useFreeLimit=true`, `freeLimitExhaustionBehavior=AutoPause`, 32 GB maximum data, local backup redundancy. Free compute exhaustion makes the database unavailable until next month. There is no paid SKU fallback.
- Standard Hot/LRS Blob Storage for a private Terraform state file. This is the one intentionally paid component; light usage is expected to cost a few cents per month, not a guaranteed billing cap.
- GitHub repository/environment secrets for the Entra sign-in client secret. Azure deployment uses OIDC; SQL uses managed identity. No Key Vault, Application Insights, Log Analytics, private endpoints, Redis, or Azure Container Registry.

Cost monitoring is a future task. Budget alerts do not stop spending. Verify free-offer eligibility, existing free-database region restrictions, F1 capacity, and .NET 10 runtime availability in Canada Central before applying. Stop if unavailable; do not upgrade to a paid tier. Terraform state is private and may contain secret app settings when the Azure provider refreshes the app. Never commit, upload as a workflow artifact, or expose state/plan files in public logs. Leave detailed debug logging off.

References: [SQL free offer](https://learn.microsoft.com/en-us/azure/azure-sql/database/free-offer), [App Service pricing](https://azure.microsoft.com/en-us/pricing/details/app-service/linux/), [Blob pricing](https://azure.microsoft.com/en-ca/pricing/details/storage/blobs/).

## 1. Sign in to Azure and bootstrap state/access

Install Azure CLI locally, or use an ephemeral Azure Cloud Shell session. On Windows/PowerShell, use the native PowerShell bootstrap to avoid mixing Bash and Windows temporary-file paths:

```powershell
az login --tenant e099407c-b3b3-45aa-868e-cc901f513dc5
.\scripts\bootstrap-azure.ps1
```

In Linux Bash/Cloud Shell:

```bash
az login --tenant e099407c-b3b3-45aa-868e-cc901f513dc5
bash scripts/bootstrap-azure.sh
```

The script **creates resources**: two resource groups, a small StorageV2 account/private `tfstate` container, a separate Entra deployment app/service principal, and scoped RBAC assignments. Shared-key and anonymous blob access are disabled. It registers Storage, Web, and SQL resource providers. Run as an Azure owner with permission to create Entra app registrations and assign roles. Reruns reuse the named resources; storage charges begin when used. State-storage bootstrap resources are intentionally outside the application Terraform state so applying/destroying the app cannot delete its own backend. Preserve them and their access configuration.

Bootstrap prints the non-secret GitHub variable values; it does not create a deployment client secret. It grants the deployment identity Contributor on `rg-netvalue-free` and Storage Blob Data Contributor on only the state container. Your account also gets state access. No subscription-wide Contributor grant is needed.

## 2. GitHub production environment

In **JeffCousineau/NetValue-deployment**, Settings → Environments → create `production`. Restrict deployment branches to `main` and configure a required reviewer where supported. Keep the Actions spending budget at zero/no paid overages and use standard Ubuntu runners. Workflows only run through **Run workflow** on `main`; pushes and PRs do not deploy.

Add environment variables from the bootstrap output:

| Variable | Value |
|---|---|
| AZURE_CLIENT_ID | New deployment application's client ID, NOT NetValue's sign-in application ID |
| AZURE_TENANT_ID | e099407c-b3b3-45aa-868e-cc901f513dc5 |
| AZURE_SUBSCRIPTION_ID | 0bc9dd71-16c4-428e-8160-8a90c7c892f5 |
| TF_STATE_ACCOUNT | Bootstrap storage account name |
| AZURE_WEB_APP_NAME | Bootstrap app name |
| SQL_SERVER_NAME | Bootstrap SQL server name |
| FREE_OFFER_VERIFIED | `true` only after confirming subscription/region eligibility |
| SQL_ACCESS_READY | Leave unset until completing SQL access below |

Add **ENTRA_CLIENT_SECRET** as a production environment secret: the secret VALUE from the existing NetValue sign-in app registration (`209f8009-5376-440d-8d26-f7316be55321`). Enter it directly in GitHub; do not paste it into chat, files, or command history. GitHub injects it into the App Service configuration, not Terraform variables. It can still appear in private Terraform state on provider refresh.

Bootstrap creates or updates the production federated credential, so rerunning it repairs the previous name-only subject. This repository uses GitHub's [immutable OIDC subject format](https://docs.github.com/en/actions/reference/security/oidc#immutable-subject-claims), including owner ID `8643172` and repository ID `1403790853`. Update the scripts if recreating or transferring this repository changes its subject.

The deployment app's federated credential is bound to `repo:JeffCousineau@8643172/NetValue-deployment@1403790853:environment:production`, issuer `https://token.actions.githubusercontent.com`, audience `api://AzureADTokenExchange`.

## 3. Review and create application infrastructure

Run **Infrastructure** with operation `plan`. Review that the only app plan is F1, SQL has `useFreeLimit=true` and `AutoPause`, and no additional paid services are included. Then run with operation `apply` after review. Both operations require free-offer confirmation. Apply generates a fresh saved plan and applies that exact file; no state or plans are published as artifacts. Azure may reject capacity/eligibility; the workflow stops rather than provisioning a paid alternative.

Save the output URL, SQL host, app principal ID, and outbound IP list. The SQL server uses Entra-only authentication and your configured owner Object ID as SQL administrator. Initially no SQL firewall rules are opened.

For manual Terraform execution, copy `terraform/backend.example.hcl` to an ignored `terraform/backend.hcl`, fill the storage account name, then run:

```bash
terraform -chdir=terraform init -backend-config=backend.hcl
terraform -chdir=terraform plan -var='free_offer_verified=true'
```

Local runs use `az login`; GitHub uses OIDC. The remote backend uses Entra data-plane access and native Blob lease locking, not account keys. Do not run `terraform init -migrate-state` unless moving an existing backend deliberately. Database deletion is protected with `prevent_destroy`; no destroy workflow is provided.

## 4. SQL access and Entra redirects

Run `bash scripts/allow-app-sql.sh <web-app-name> <sql-server-name>` to allow only the app's exact outbound IPv4 addresses. Keep these rules aligned if Azure changes outbound addresses. No broad AllowAzureServices firewall rule is enabled.

Temporarily add your own workstation IPv4 to the SQL firewall in the Azure portal. Connect to the `NetValue` database with Microsoft Entra authentication as the configured owner/admin, using SSMS or another SQL client. Replace the two GUID placeholders in `scripts/sql-access.sql` with the **web app principal ID** from Terraform and **deployment principal ID** from bootstrap, then execute it. The app gets read/write roles. The deployment identity additionally gets schema-change permissions for EF migrations. These database roles are separate from Azure RBAC. Remove your workstation rule when finished.

In the existing NetValue Entra app registration → Authentication → Web, add:

- `https://<web-app-name>.azurewebsites.net/signin-oidc`
- `https://<web-app-name>.azurewebsites.net/signout-callback-oidc`

Keep localhost redirect URIs for local development. Set the GitHub environment variable `SQL_ACCESS_READY=true` once SQL roles/firewall and redirects are ready. The app's forwarded-headers setting handles the Azure HTTPS proxy. Validate HTTPS redirects and persisted data-protection keys on the first cloud run before relying on sessions across restarts.

## 5. Deploy and import your data

Run **Deploy NetValue**, preferably choosing the reviewed application commit SHA as `source_ref`. It checks out the public NetValue repository, runs all checks, publishes .NET 10 without App_Data, signs in through OIDC, temporarily allows the runner's exact IPv4 to SQL, applies EF schema migrations, removes the temporary rule, sets the Entra secret without printing it, and deploys the tested package. If a runner is forcibly killed, remove any leftover `github-<run-id>` firewall rule manually. Failed migrations stop deployment. No automatic paid upgrades, database imports, or fallback schemas are performed.

Open the HTTPS app URL and sign in as the configured owner. For your current single-household setup, download a financial backup from the local app and restore it in Azure through Settings; Azure bootstrap creates your owner membership, and restore preserves it. Existing local JSON/SQLite files remain private and are never deployed. If moving multiple household identities later, use the offline operator import from the application database documentation **before first sign-in**, into an empty schema.

Verify account balances, monthly progress, export, sign-out/sign-in, and recovery backups. SQL idle resumption and free App Service startup can be slow. Free quota exhaustion causes downtime instead of SQL overage charges. No live Azure deployment or free-tier capacity check has been performed merely by writing these files.
