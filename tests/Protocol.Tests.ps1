$ErrorActionPreference = 'Stop'
$source = Join-Path $PSScriptRoot '..\windows'
. (Join-Path $source 'Protocol.ps1')
Add-Type -Path (Join-Path $source 'WindowsDisplay.cs')

$now = 1750000000
$request = '81e2bce5-1dce-4e5d-b65e-2646baccadcd'
$other = '969e5e0e-7a5f-49d0-8400-1ef829b8243d'
$events = @("$now $request wake-ready", "$now $other wake-active", "$now $request wake-active")
if ((Find-HandoffEvent $events $request @('wake-ready','wake-active')) -ne 'wake-active') { throw 'Did not read the current wake phase.' }
if (Find-HandoffEvent $events $other @('wake-ready')) { throw 'Accepted the wrong wake phase.' }
if (Find-HandoffEvent @($events[0],$events[1]) $request @('wake-active')) { throw 'Accepted a different transaction as active.' }
if (Find-ReturnRequest @("$($now-36) $request return-request") $now) { throw 'Accepted a stale return request.' }
if (Find-ReturnRequest @("$($now+6) $request return-request") $now) { throw 'Accepted an implausibly future request.' }
if (Find-ReturnRequest @("$now not-a-uuid return-request") $now) { throw 'Accepted an invalid return request ID.' }
if ((Find-ReturnRequest @("$now $request return-request") $now) -ne $request) { throw 'Missed a fresh return request.' }

foreach ($file in Get-ChildItem -LiteralPath $source -Filter '*.ps1') {
    $tokens = $null
    $errors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
    if ($errors) { throw ($errors | Out-String) }
}
Write-Output 'Windows scripts parsed, native interop compiled, and protocol checks passed.'
