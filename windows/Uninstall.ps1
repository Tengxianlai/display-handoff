$ErrorActionPreference = 'Stop'
$root = Join-Path $env:LOCALAPPDATA 'DisplayHandoff'
$script = Join-Path $root 'Switch.ps1'
if (![IO.File]::Exists($script)) { exit }
$powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
& $powershell -NoProfile -File $script -Action Recover
if ($LASTEXITCODE) { throw 'Recover the Windows display layout before removing the shortcuts.' }
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -like "*$script* -Action Listen*" } |
    ForEach-Object { Stop-Process -Id $_.ProcessId }
$shell = New-Object -ComObject WScript.Shell
$desktop = [Environment]::GetFolderPath('Desktop')
$startup = [Environment]::GetFolderPath('Startup')
$links = (Join-Path $desktop 'Switch to Mac.lnk'), (Join-Path $desktop 'Restore Windows displays.lnk'), (Join-Path $startup 'Display Handoff.lnk')
foreach ($link in $links) {
    if ([IO.File]::Exists($link) -and $shell.CreateShortcut($link).Arguments -like "*$script*") { [IO.File]::Delete($link) }
}
Write-Output "Stopped Display Handoff and removed its shortcuts. Local data is at $root."
