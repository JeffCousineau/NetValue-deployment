$ErrorActionPreference = 'Stop'
$global:NetValueTestMockTenant = 'e099407c-b3b3-45aa-868e-cc901f513dc5'
$global:NetValueTestMockFailProvider = $false
$global:NetValueTestNativeJsonRead = $false
$global:NetValueTestCredentialFile = $null
$global:NetValueTestProviderCalled = $false
$global:NetValueTestContainerAttempts = 0
function global:az {
    $global:LASTEXITCODE = 0
    if ($args | Where-Object { $_ -match '[()]' }) { throw 'Command-shell metacharacters were passed to az.cmd' }
    switch ("$($args[0]) $($args[1])") {
        'account show' { return "$global:NetValueTestMockTenant`r`n" }
        'account set' { return }
        'provider register' {
            $global:NetValueTestProviderCalled = $true
            if ($global:NetValueTestMockFailProvider) { $global:LASTEXITCODE = 9 }
            return
        }
        'group create' { return }
        'storage account' { return "/subscriptions/test/resourceGroups/test/providers/Microsoft.Storage/storageAccounts/test`r`n" }
        'storage container' {
            $global:NetValueTestContainerAttempts++
            if ($global:NetValueTestContainerAttempts -eq 1) { $global:LASTEXITCODE = 1 }
            return
        }
        'role assignment' { return }
        'ad signed-in-user' { return '1112bb2c-81d0-4e08-8009-4eab2c6a9b8b' }
        'ad sp' { return '00000000-0000-0000-0000-000000000002' }
        'ad app' {
            if ($args[2] -eq 'list') {
                $nameIndex = [Array]::IndexOf($args, '--display-name')
                return (ConvertTo-Json -InputObject @(@{ displayName = $args[$nameIndex + 1]; appId = '00000000-0000-0000-0000-000000000003' }) -Compress)
            }
            if ($args[2] -eq 'federated-credential') {
                if ($args[3] -eq 'list') { return '[]' }
                $parameterIndex = [Array]::IndexOf($args, '--parameters')
                $global:NetValueTestCredentialFile = $args[$parameterIndex + 1].Substring(1)
                if (![IO.Path]::IsPathRooted($global:NetValueTestCredentialFile) -or !(Test-Path -LiteralPath $global:NetValueTestCredentialFile)) { throw 'Native JSON file path is unreadable' }
                $credential = Get-Content -LiteralPath $global:NetValueTestCredentialFile -Raw | ConvertFrom-Json
                if ($credential.subject -ne 'repo:JeffCousineau/NetValue-deployment:environment:production' -or $credential.audiences[0] -ne 'api://AzureADTokenExchange') { throw 'Invalid federated credential JSON' }
                $global:NetValueTestNativeJsonRead = $true
                return
            }
            throw 'Unexpected app command'
        }
        default { throw "Unexpected mock Azure command: $args" }
    }
}
function global:Start-Sleep { param($Seconds) }
$bootstrap = Join-Path (Split-Path -Parent $PSScriptRoot) 'bootstrap-azure.ps1'
try {
    $output = & $bootstrap
    if (!$global:NetValueTestNativeJsonRead -or $global:NetValueTestContainerAttempts -ne 2) { throw 'Native JSON handling or permission retry failed' }
    if (Test-Path -LiteralPath $global:NetValueTestCredentialFile) { throw 'Temporary JSON file was not cleaned up' }
    if ($output -notcontains 'AZURE_CLIENT_ID=00000000-0000-0000-0000-000000000003') { throw 'Final configuration missing or contains CRLF' }
    $global:NetValueTestMockTenant = '00000000-0000-0000-0000-000000000001'
    $global:NetValueTestProviderCalled = $false
    $rejected = $false
    try { & $bootstrap | Out-Null } catch { $rejected = $_.Exception.Message -like '*directory mismatch*' }
    if (!$rejected -or $global:NetValueTestProviderCalled) { throw 'Wrong tenant was allowed to provision resources' }
    $global:NetValueTestMockTenant = 'e099407c-b3b3-45aa-868e-cc901f513dc5'
    $global:NetValueTestMockFailProvider = $true
    $rejected = $false
    try { & $bootstrap | Out-Null } catch { $rejected = $_.Exception.Message -like '*exit 9*' }
    if (!$rejected) { throw 'Azure CLI failure was ignored' }
    $global:LASTEXITCODE = 0
    Write-Output 'PowerShell native JSON, existing identity reuse, permission retry, tenant guard, cleanup, and CLI failure checks passed.'
} finally {
    Remove-Item Function:\az -ErrorAction SilentlyContinue
    Remove-Item Function:\Start-Sleep -ErrorAction SilentlyContinue
}
