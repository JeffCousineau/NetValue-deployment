[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$azureCommand = 'az'
if (!(Get-Command az -ErrorAction SilentlyContinue)) { $azureCommand = 'C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd' }
$account = (& $azureCommand account show --output json) | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or $account.id -ne '0bc9dd71-16c4-428e-8160-8a90c7c892f5' -or $account.tenantId -ne 'e099407c-b3b3-45aa-868e-cc901f513dc5') { throw 'Sign in to the expected Azure subscription and directory.' }
$budget = (& $azureCommand rest --method get --url 'https://management.azure.com/subscriptions/0bc9dd71-16c4-428e-8160-8a90c7c892f5/providers/Microsoft.Consumption/budgets/Monthly_NetValue?api-version=2024-08-01' --output json) | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) { throw 'Cannot read the existing cost budget.' }
$recipient = $budget.properties.notifications.actual_GreaterThan_50_Percent
if (!$recipient.contactEmails.Count) { throw 'The existing budget must have a configured email recipient.' }
if ($budget.properties.category -ne 'Cost' -or $budget.properties.timeGrain -ne 'Monthly' -or @($budget.properties.filter.PSObject.Properties).Count -ne 0) { throw 'Review budget scope before importing: expected an unfiltered monthly subscription cost budget.' }
$directory = Join-Path (Split-Path -Parent $PSScriptRoot) 'cost-alerts'
$variables = @{
    contact_emails = @($recipient.contactEmails); contact_roles = @($recipient.contactRoles); contact_groups = @($recipient.contactGroups)
    budget_amount = $budget.properties.amount
    budget_start = ([DateTimeOffset]$budget.properties.timePeriod.startDate).ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
    budget_end = ([DateTimeOffset]$budget.properties.timePeriod.endDate).ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
} | ConvertTo-Json -Depth 5
[IO.File]::WriteAllText((Join-Path $directory 'private.auto.tfvars.json'), $variables, [Text.UTF8Encoding]::new($false))
$backend = @('resource_group_name = "rg-netvalue-state"', 'storage_account_name = "nvstate0620db8f"', 'container_name = "tfstate"', 'key = "netvalue.cost-alerts.tfstate"', 'use_azuread_auth = true') -join "`n"
[IO.File]::WriteAllText((Join-Path $directory 'backend.hcl'), $backend, [Text.UTF8Encoding]::new($false))
Write-Output 'Prepared ignored private variables and backend configuration. No Azure resources were changed.'