[CmdletBinding()]
param([string] $BudgetName = 'Monthly_NetValue')
$ErrorActionPreference = 'Stop'
$subscriptionId = '0bc9dd71-16c4-428e-8160-8a90c7c892f5'
$tenantId = 'e099407c-b3b3-45aa-868e-cc901f513dc5'
$azureCommand = 'az'
if (!(Get-Command az -ErrorAction SilentlyContinue)) {
    $azureCommand = 'C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd'
    if (!(Test-Path -LiteralPath $azureCommand)) { throw 'Install Azure CLI and sign in before running this script.' }
}
function Invoke-BudgetAzure {
    param([string[]] $Arguments)
    $output = & $azureCommand @Arguments
    if ($LASTEXITCODE -ne 0) { throw 'Azure CLI cost-alert operation failed.' }
    return ($output -join "`n").Trim()
}
Invoke-BudgetAzure -Arguments @('account', 'set', '--subscription', $subscriptionId) | Out-Null
$account = Invoke-BudgetAzure -Arguments @('account', 'show', '--output', 'json') | ConvertFrom-Json
if ($account.tenantId -ne $tenantId -or $account.id -ne $subscriptionId) { throw 'Azure subscription/directory mismatch.' }
$url = "https://management.azure.com/subscriptions/$subscriptionId/providers/Microsoft.Consumption/budgets/$([Uri]::EscapeDataString($BudgetName))?api-version=2024-08-01"
$existing = Invoke-BudgetAzure -Arguments @('rest', '--method', 'get', '--url', $url, '--output', 'json') | ConvertFrom-Json
if ($existing.properties.category -ne 'Cost' -or $existing.properties.timeGrain -ne 'Monthly') { throw 'Expected an existing monthly cost budget.' }
$notifications = [ordered]@{}
foreach ($property in $existing.properties.notifications.PSObject.Properties) { $notifications[$property.Name] = $property.Value }
if (!$notifications.Count) { throw 'Configure a recipient on the existing budget first.' }
$recipient = @($notifications.Values)[0]
if (!(@($recipient.contactEmails).Count + @($recipient.contactRoles).Count + @($recipient.contactGroups).Count)) { throw 'The budget has no notification recipient.' }
foreach ($alert in @(
    @{ Name = 'NetValue_Actual_1_Percent'; Threshold = 1; Type = 'Actual' },
    @{ Name = 'NetValue_Actual_5_Percent'; Threshold = 5; Type = 'Actual' },
    @{ Name = 'NetValue_Actual_100_Percent'; Threshold = 100; Type = 'Actual' },
    @{ Name = 'NetValue_Forecast_100_Percent'; Threshold = 100; Type = 'Forecasted' }
)) {
    $notifications[$alert.Name] = @{
        enabled = $true; operator = 'GreaterThanOrEqualTo'
        threshold = $alert.Threshold; thresholdType = $alert.Type
        contactEmails = @($recipient.contactEmails); contactRoles = @($recipient.contactRoles)
        contactGroups = @($recipient.contactGroups); locale = $recipient.locale
    }
}
if ($notifications.Count -gt 5) { throw 'Azure permits five budget notifications. Review existing alerts before adding these four.' }
$properties = @{
    amount = $existing.properties.amount; category = $existing.properties.category
    timeGrain = $existing.properties.timeGrain; timePeriod = $existing.properties.timePeriod
    notifications = $notifications
}
if ($existing.properties.filter) { $properties.filter = $existing.properties.filter }
$body = @{ eTag = $existing.eTag; properties = $properties } | ConvertTo-Json -Depth 15
$file = [IO.Path]::GetTempFileName()
try {
    [IO.File]::WriteAllText($file, $body, [Text.UTF8Encoding]::new($false))
    Invoke-BudgetAzure -Arguments @('rest', '--method', 'put', '--url', $url, '--body', "@$file", '--output', 'none') | Out-Null
} finally { Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue }
$verified = Invoke-BudgetAzure -Arguments @('rest', '--method', 'get', '--url', $url, '--output', 'json') | ConvertFrom-Json
foreach ($key in $notifications.Keys) {
    $actual = $verified.properties.notifications.$key
    if (!$actual.enabled -or $actual.threshold -ne $notifications[$key].threshold -or $actual.thresholdType -ne $notifications[$key].thresholdType) { throw 'Cost alert verification failed.' }
}
if ($verified.properties.amount -ne $existing.properties.amount) { throw 'Budget amount changed unexpectedly.' }
Write-Output "Verified $($notifications.Count) alerts for $BudgetName. Existing amount, scope, period, and recipients preserved."