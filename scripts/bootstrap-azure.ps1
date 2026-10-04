[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'

function Invoke-NetValueAzure {
    param([string[]] $Arguments, [switch] $AllowFailure)
    if ($AllowFailure) { $result = & az @Arguments 2>$null }
    else { $result = & az @Arguments }
    if ($LASTEXITCODE -ne 0) {
        if ($AllowFailure) { return $null }
        throw "Azure CLI failed (exit $LASTEXITCODE): $($Arguments -join ' ')"
    }
    return ($result -join "`n").Trim()
}

$subscriptionId = '0bc9dd71-16c4-428e-8160-8a90c7c892f5'
$tenantId = 'e099407c-b3b3-45aa-868e-cc901f513dc5'
$hasher = [Security.Cryptography.SHA256]::Create()
try { $nameSuffix = [BitConverter]::ToString($hasher.ComputeHash([Text.Encoding]::UTF8.GetBytes($subscriptionId))).Replace('-', '').ToLowerInvariant().Substring(0, 8) }
finally { $hasher.Dispose() }
$stateAccount = "nvstate$nameSuffix"
$appName = "netvalue-$nameSuffix"

Invoke-NetValueAzure -Arguments @('account', 'set', '--subscription', $subscriptionId) | Out-Null
$actualTenant = Invoke-NetValueAzure -Arguments @('account', 'show', '--query', 'tenantId', '-o', 'tsv')
if ($actualTenant -ne $tenantId) { throw "Azure directory mismatch. Expected: $tenantId; actual: $actualTenant" }

Write-Output 'Registering Azure resource providers...'
foreach ($provider in @('Microsoft.Storage', 'Microsoft.Web', 'Microsoft.Sql')) {
    Invoke-NetValueAzure -Arguments @('provider', 'register', '--namespace', $provider, '--wait', '--output', 'none') | Out-Null
}
Write-Output 'Ensuring resource groups and private Terraform state storage...'
foreach ($group in @('rg-netvalue-state', 'rg-netvalue-free')) {
    Invoke-NetValueAzure -Arguments @('group', 'create', '--name', $group, '--location', 'canadacentral', '--output', 'none') | Out-Null
}
$stateId = Invoke-NetValueAzure -Arguments @('storage', 'account', 'show', '--resource-group', 'rg-netvalue-state', '--name', $stateAccount, '--query', 'id', '-o', 'tsv') -AllowFailure
if (!$stateId) {
    Invoke-NetValueAzure -Arguments @('storage', 'account', 'create', '--name', $stateAccount, '--resource-group', 'rg-netvalue-state', '--location', 'canadacentral', '--sku', 'Standard_LRS', '--kind', 'StorageV2', '--access-tier', 'Hot', '--https-only', 'true', '--min-tls-version', 'TLS1_2', '--allow-blob-public-access', 'false', '--allow-shared-key-access', 'false', '--output', 'none') | Out-Null
    $stateId = Invoke-NetValueAzure -Arguments @('storage', 'account', 'show', '-g', 'rg-netvalue-state', '-n', $stateAccount, '--query', 'id', '-o', 'tsv')
}
$ownerId = Invoke-NetValueAzure -Arguments @('ad', 'signed-in-user', 'show', '--query', 'id', '-o', 'tsv')
Invoke-NetValueAzure -Arguments @('role', 'assignment', 'create', '--assignee-object-id', $ownerId, '--assignee-principal-type', 'User', '--role', 'Storage Blob Data Contributor', '--scope', $stateId, '--output', 'none') | Out-Null
Write-Output 'Waiting for state-container permissions...'
$containerReady = $false
for ($attempt = 0; $attempt -lt 24; $attempt++) {
    $containerResult = Invoke-NetValueAzure -Arguments @('storage', 'container', 'create', '--account-name', $stateAccount, '--name', 'tfstate', '--auth-mode', 'login', '--public-access', 'off', '--output', 'none') -AllowFailure
    if ($null -ne $containerResult) { $containerReady = $true; break }
    Start-Sleep -Seconds 5
}
if (!$containerReady) { throw 'State-container access is not ready. Rerun after RBAC propagation.' }

Write-Output 'Ensuring the GitHub deployment identity and federated credential...'
$identityName = "NetValue GitHub deployment $nameSuffix"
# Avoid shell metacharacters in JMESPath expressions passed through Windows az.cmd.
$applications = @(Invoke-NetValueAzure -Arguments @('ad', 'app', 'list', '--display-name', $identityName, '--output', 'json') | ConvertFrom-Json | Where-Object { $_.displayName -eq $identityName })
$appCount = $applications.Count
if ($appCount -gt 1) { throw 'Duplicate deployment identities; resolve them before continuing.' }
if ($appCount -eq 0) {
    $clientId = Invoke-NetValueAzure -Arguments @('ad', 'app', 'create', '--display-name', $identityName, '--query', 'appId', '-o', 'tsv')
} else {
    $clientId = $applications[0].appId
}
$principalId = Invoke-NetValueAzure -Arguments @('ad', 'sp', 'show', '--id', $clientId, '--query', 'id', '-o', 'tsv') -AllowFailure
if (!$principalId) {
    $principalId = Invoke-NetValueAzure -Arguments @('ad', 'sp', 'create', '--id', $clientId, '--query', 'id', '-o', 'tsv')
}
$federatedCredentials = @(Invoke-NetValueAzure -Arguments @('ad', 'app', 'federated-credential', 'list', '--id', $clientId, '--output', 'json') | ConvertFrom-Json | Where-Object { $_.name -eq 'github-production' })
$credentialCount = $federatedCredentials.Count
if ($credentialCount -eq 0) {
    # PowerShell and az use the same native filesystem path; no Bash /tmp translation.
    $credentialFile = [IO.Path]::GetTempFileName()
    try {
        $credential = @{
            name = 'github-production'
            issuer = 'https://token.actions.githubusercontent.com'
            subject = 'repo:JeffCousineau/NetValue-deployment:environment:production'
            audiences = @('api://AzureADTokenExchange')
        } | ConvertTo-Json -Compress
        [IO.File]::WriteAllText($credentialFile, $credential, [Text.UTF8Encoding]::new($false))
        Invoke-NetValueAzure -Arguments @('ad', 'app', 'federated-credential', 'create', '--id', $clientId, '--parameters', "@$credentialFile", '--output', 'none') | Out-Null
    } finally { Remove-Item -LiteralPath $credentialFile -Force -ErrorAction SilentlyContinue }
}
Write-Output 'Ensuring deployment permissions...'
Invoke-NetValueAzure -Arguments @('role', 'assignment', 'create', '--assignee-object-id', $principalId, '--assignee-principal-type', 'ServicePrincipal', '--role', 'Contributor', '--scope', "/subscriptions/$subscriptionId/resourceGroups/rg-netvalue-free", '--output', 'none') | Out-Null
Invoke-NetValueAzure -Arguments @('role', 'assignment', 'create', '--assignee-object-id', $principalId, '--assignee-principal-type', 'ServicePrincipal', '--role', 'Storage Blob Data Contributor', '--scope', "$stateId/blobServices/default/containers/tfstate", '--output', 'none') | Out-Null
Write-Output "`nGitHub production environment variables:"
Write-Output "AZURE_CLIENT_ID=$clientId"
Write-Output "AZURE_TENANT_ID=$tenantId"
Write-Output "AZURE_SUBSCRIPTION_ID=$subscriptionId"
Write-Output "TF_STATE_ACCOUNT=$stateAccount"
Write-Output "AZURE_WEB_APP_NAME=$appName"
Write-Output "SQL_SERVER_NAME=$appName-sql"
Write-Output "DEPLOYMENT_PRINCIPAL_ID=$principalId"
