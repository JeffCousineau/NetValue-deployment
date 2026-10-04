$ErrorActionPreference = 'Stop'
$global:BudgetTestWritten = $false
$global:BudgetTestWrongTenant = $false
$global:BudgetTestValue = @{
    eTag = 'original-etag'
    properties = @{
        amount = 20; category = 'Cost'; timeGrain = 'Monthly'
        timePeriod = @{ startDate = '2026-10-01T00:00:00Z'; endDate = '2028-09-30T00:00:00Z' }
        filter = @{ dimensions = @{ name = 'ResourceGroupName'; operator = 'In'; values = @('sample-group') } }
        notifications = @{
            Existing = @{ enabled = $true; threshold = 50; thresholdType = 'Actual'; operator = 'GreaterThan'; locale = 'fr-fr'; contactEmails = @('owner@example.invalid'); contactRoles = @(); contactGroups = @() }
        }
    }
}
function global:az {
    $global:LASTEXITCODE = 0
    if ($args[0] -eq 'account') {
        if ($args[1] -eq 'set') { return }
        $tenant = if ($global:BudgetTestWrongTenant) { 'wrong' } else { 'e099407c-b3b3-45aa-868e-cc901f513dc5' }
        return (@{ id = '0bc9dd71-16c4-428e-8160-8a90c7c892f5'; tenantId = $tenant } | ConvertTo-Json)
    }
    $method = $args[[Array]::IndexOf($args, '--method') + 1]
    if ($method -eq 'get') { return ($global:BudgetTestValue | ConvertTo-Json -Depth 15) }
    if ($method -ne 'put') { throw 'Unexpected budget operation.' }
    $file = $args[[Array]::IndexOf($args, '--body') + 1].Substring(1)
    $body = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json
    if ($body.eTag -ne 'original-etag' -or $body.properties.amount -ne 20 -or [DateTimeOffset]$body.properties.timePeriod.endDate -ne [DateTimeOffset]'2028-09-30T00:00:00Z' -or $body.properties.filter.dimensions.values[0] -ne 'sample-group') { throw 'Existing budget settings were not preserved.' }
    $alerts = $body.properties.notifications.PSObject.Properties
    if (@($alerts).Count -ne 5 -or $body.properties.notifications.Existing.threshold -ne 50) { throw 'Existing alert lost or new alert count wrong.' }
    foreach ($alert in $alerts) {
        if ($alert.Value.contactEmails[0] -ne 'owner@example.invalid' -or $alert.Value.locale -ne 'fr-fr') { throw 'Private recipient or language changed.' }
    }
    $global:BudgetTestValue = $body
    $global:BudgetTestWritten = $true
}
try {
    $script = Join-Path (Split-Path -Parent $PSScriptRoot) 'setup-cost-alerts.ps1'
    & $script | Out-Null
    if (!$global:BudgetTestWritten) { throw 'Budget was not updated.' }
    & $script | Out-Null # Re-running must not add more notifications.
    $global:BudgetTestWrongTenant = $true
    $global:BudgetTestWritten = $false
    $rejected = $false
    try { & $script | Out-Null } catch { $rejected = $_.Exception.Message -like '*mismatch*' }
    if (!$rejected -or $global:BudgetTestWritten) { throw 'Wrong tenant was allowed to update budget.' }
    Write-Output 'Cost-alert preservation, recipient privacy, idempotency, and tenant checks passed.'
} finally { Remove-Item Function:\az -ErrorAction SilentlyContinue }