# NetValue deployment

Terraform manages Azure infrastructure for [NetValue](https://github.com/JeffCousineau/NetValue) in Canada Central. Azure CLI is used for login and read-only diagnostics. Application package deployment, EF schema migrations, and restoring financial data remain application operations.

## Cost and access constraints

- Linux App Service F1 Free, Always On disabled. Free quotas and idle shutdowns can cause downtime.
- Azure SQL free offer, 32 GB maximum data, local backup redundancy, `useFreeLimit=true`, and `AutoPause` when the free allowance is exhausted. No paid fallback.
- Private Standard Hot/LRS Blob storage for Terraform state. This small paid component is expected to cost cents with light usage; this is not a billing guarantee.
- No Key Vault, monitoring workspace, private endpoints, or container registry. Managed identity for SQL; GitHub OIDC for deployment; Terraform generates the sign-in client secret.
- Exact App Service possible outbound IPs for SQL access. One exact temporary owner/runner IP is allowed only while managing SQL permissions or migrating schema. No broad AllowAzureServices rule.
- GitHub identity has Contributor only on the app resource group and Blob Data Contributor only on the state container. Owner-only stacks manage identities, RBAC, and the subscription budget.

The subscription budget is 20 CAD/month with French actual-spend alerts at 0.20, 1, 10, and 20 CAD, plus a 20 CAD forecast alert. Budgets notify; they do not stop spending. Cost data can be delayed 8–24 hours and budgets are evaluated daily.

## Terraform stacks

| Directory | Resources | State / operator |
|---|---|---|
| `bootstrap/` | Resource-provider registrations, state resource group/account/container, owner Blob access | Private local state; subscription owner |
| `foundation/` | App resource group, sign-in and deployment applications/service principals, GitHub OIDC, scoped RBAC, redirects, generated sign-in credential | `netvalue.foundation.tfstate`; owner with Entra application permissions |
| `terraform/` | F1 plan/app, managed identity, Entra-only SQL server/free database, app settings including sign-in credential | `netvalue.terraform.tfstate`; owner or GitHub deployment identity |
| `app-access/` | Exact possible App Service outbound-IP SQL rules | `netvalue.app-access.tfstate`; owner or GitHub deployment identity |
| `runner-access/` | One temporary exact-IP firewall rule | Ephemeral local state; owner or GitHub deployment identity |
| `sql-access/` | App/deployment SQL users and database-role memberships | `netvalue.sql-access.tfstate`; SQL Entra administrator |
| `cost-alerts/` | Subscription budget and five notifications | `netvalue.cost-alerts.tfstate`; subscription budget administrator |

The running infrastructure has been imported into these stacks. Import blocks are not retained in the source: a fresh rebuild creates resources instead of attempting to import deleted ones. The SQL stack pins the community `muecahit94/mssql` provider to 1.5.0 and uses explicit service-principal **client IDs** for SQL SIDs. It does not require granting Directory Readers to the SQL server.

## Rebuild using Terraform

Install Terraform 1.10 or later and Azure CLI, then sign in as the owner. Check Azure SQL free-offer eligibility, F1 availability, and .NET 10 support before proceeding; do not substitute paid tiers.

```powershell
az login --tenant e099407c-b3b3-45aa-868e-cc901f513dc5
az account set --subscription 0bc9dd71-16c4-428e-8160-8a90c7c892f5
terraform '-chdir=bootstrap' init
terraform '-chdir=bootstrap' plan '-out=reviewed.tfplan'
terraform '-chdir=bootstrap' apply reviewed.tfplan

terraform '-chdir=foundation' init '-backend-config=backend.example.hcl'
terraform '-chdir=foundation' plan '-out=reviewed.tfplan'
terraform '-chdir=foundation' apply reviewed.tfplan

terraform '-chdir=terraform' init '-backend-config=backend.example.hcl'
terraform '-chdir=terraform' plan '-var=free_offer_verified=true' '-out=reviewed.tfplan'
terraform '-chdir=terraform' apply reviewed.tfplan

terraform '-chdir=app-access' init '-backend-config=backend.example.hcl'
terraform '-chdir=app-access' plan '-out=reviewed.tfplan'
terraform '-chdir=app-access' apply reviewed.tfplan
```

Review every saved plan before applying. Wait for new Blob RBAC assignments to propagate if Azure initially rejects access, then retry Terraform. Foundation secrets and IDs flow into app configuration through private remote state; no portal redirect changes or client-secret setup script is required.

To create database users, temporarily allow the workstation's public IPv4 (replace the example), apply SQL access as the configured owner, then remove the temporary rule. These commands manage permissions, not financial data or EF schema:

```powershell
$env:TF_VAR_runner_ip = 'YOUR_PUBLIC_IPV4'
terraform '-chdir=runner-access' init
terraform '-chdir=runner-access' plan '-out=reviewed.tfplan'
terraform '-chdir=runner-access' apply reviewed.tfplan
terraform '-chdir=sql-access' init '-backend-config=backend.example.hcl'
terraform '-chdir=sql-access' plan '-out=reviewed.tfplan'
terraform '-chdir=sql-access' apply reviewed.tfplan
# Always remove temporary access, including after an unsuccessful SQL operation.
terraform '-chdir=runner-access' destroy
Remove-Item Env:TF_VAR_runner_ip
```

Configure the budget recipients privately. Create an ignored `cost-alerts/private.auto.tfvars.json` with `contact_emails` as an array of recipient addresses; optionally set `budget_start` and `budget_end` for the desired current validity period. Its existing private variables are preserved locally. Never put recipient addresses into public source.

```powershell
terraform '-chdir=cost-alerts' init '-backend-config=backend.example.hcl'
terraform '-chdir=cost-alerts' plan '-out=reviewed.tfplan'
terraform '-chdir=cost-alerts' apply reviewed.tfplan
```

## GitHub configuration and app deployment

### Microsoft self-service sign-in

The owner-run `foundation` stack configures the sign-in registration for `AzureADandPersonalMicrosoftAccount` and access token version 2. Apply its reviewed plan first, then apply the app stack and deploy the matching NetValue application changes. The app uses `Authentication__SelfServiceEnabled=true` to accept personal and work/school Microsoft accounts and offer household creation to new users. No database schema migration is required for this feature; existing users retain their tenant/Object ID mappings and memberships. Free-tier, SQL auto-pause, firewall, and budget settings remain unchanged. Validate both an existing owner login and a new personal Microsoft account after deployment.

Use the existing `production` environment in `JeffCousineau/NetValue-deployment`, restricted to main. Workflows are manual; pushes and PRs do not deploy. Keep GitHub Actions paid overages disabled.

Set `AZURE_CLIENT_ID` from `terraform -chdir=foundation output -raw deployment_client_id`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `TF_STATE_ACCOUNT` from bootstrap, `AZURE_WEB_APP_NAME`, and `SQL_SERVER_NAME` from app outputs. Set `FREE_OFFER_VERIFIED=true` after eligibility review and `SQL_ACCESS_READY=true` after SQL access succeeds. Refresh client IDs in GitHub and local development configuration if rebuilding the Entra registrations generates new IDs. The old GitHub `ENTRA_CLIENT_SECRET` is no longer used; Terraform manages the Azure sign-in credential.

The production federated subject uses immutable owner/repository IDs: `repo:JeffCousineau@8643172/NetValue-deployment@1403790853:environment:production`. Update foundation configuration when recreating or transferring the repository changes these IDs.

**Infrastructure** reviews/applies the app stack and synchronizes app firewall rules with Terraform after apply. Broader owner-only stacks run locally. **Deploy NetValue** checks the selected source ref, runs application checks, publishes .NET 10 without private App_Data, synchronizes app access with Terraform, creates a temporary runner firewall rule with Terraform, migrates the EF schema, removes runner access with Terraform in an always-run step, and deploys the tested package. It does not set secrets or create infrastructure through Azure CLI. A forcibly terminated job may leave a runner rule; recreate its local runner-access state using Terraform import and remove it with Terraform destroy.

App Service must be Running for package deployment. If stopped, use Terraform to reconcile the app resource. F1 quota exhaustion requires waiting for the reset; do not upgrade tiers. Free SQL resumption and App Service startup may be slow.

Deploy the application after recreating infrastructure, then sign in and restore the financial backup through Settings. For multiple household identities, follow the application's database migration documentation. Terraform cannot recover financial data from a deleted database.

## Private state, rotation, and deliberate teardown

Private state and plans can contain generated credentials and recipient information. Never commit them, publish them as workflow artifacts, or enable detailed debug logs. Blob state uses AzureAD authentication and lease locking; account keys and public access are disabled. The bootstrap backend stores local state outside both repositories at `../NetValue-private/bootstrap.tfstate` (relative to the deployment repository). Keep this directory private. This state and all backups must be stored privately and protected, ideally on an encrypted disk. Keep a backup outside the state storage account before teardown.

Before the managed sign-in credential expires (one year), increment `signin_secret_version`, apply foundation, then immediately apply application infrastructure. Terraform creates the replacement before deleting its previous managed credential; apply both stacks in the same maintenance session. Local development using the old manually created credential continues to use its own secret until you intentionally update it.

Database/server, resource groups, state storage/container, provider registrations, and SQL users have `prevent_destroy` guards. A full teardown is deliberately not an ordinary apply. First export financial data and privately back up every Terraform state and private variables. Remove the relevant guards only in an explicitly reviewed destructive change. Destroy in reverse dependency order: SQL access (while temporary owner access exists), app access, app infrastructure, foundation, then bootstrap last. The budget is subscription-scoped and can be kept; remove its guard and destroy its stack only if intentionally deleting alerts. Do not unregister providers while any other subscription resources use them. If deleting state storage, restore empty/appropriately reconciled states for a new build; do not point Terraform at stale records of deleted resources. Preserve the bootstrap local state until teardown has finished.

Verification of this migration imports and reconciles the running resources. It does not destroy and recreate the live financial database as a test.

References: [Azure SQL free offer](https://learn.microsoft.com/en-us/azure/azure-sql/database/free-offer), [Azure budget notifications](https://learn.microsoft.com/en-us/azure/cost-management-billing/costs/tutorial-acm-create-budgets), [Terraform AzureAD backend](https://developer.hashicorp.com/terraform/language/backend/azurerm).

## Repository and publishing protection

FTP and SCM/WebDeploy basic publishing authentication are disabled by the application Terraform stack. Deployments use the existing Entra/OIDC identity.

Credential-free PR/push workflows provide `Application checks` and `Terraform checks`. Both main branches require a pull request, the matching GitHub Actions check, an up-to-date branch, and resolved review conversations. Administrators are subject to these rules; force pushes and branch deletion are blocked. No second reviewer is required while there is only one maintainer.

The owner-run `github-security/` stack manages these branch protections and the existing production environment. Production runs require explicit approval from JeffCousineau, retain the main-only deployment restriction, and disallow administrator bypass. Self-review is allowed so the sole maintainer can approve their own workflow. Approval is a human step; automation must not approve its own production run.

To recreate/update these GitHub settings, authenticate Azure CLI for the existing private Blob backend and provide a GitHub token through the `GITHUB_TOKEN` environment variable with repository administration and environment-management permissions. Never commit the token or place it in a Terraform variable file. Run `terraform -chdir=github-security init -backend-config=backend.example.hcl`, review `terraform -chdir=github-security plan -out=reviewed.tfplan`, then apply that plan. This stack uses `netvalue.github-security.tfstate`; it does not grant Azure privileges. Import an existing environment and its branch policy before managing them in a new state.
