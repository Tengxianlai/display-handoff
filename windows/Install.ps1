param(
    [Parameter(Mandatory)][ValidatePattern('^\\\\[^\\]+\\[^\\]+')][string]$MacShare,
    [ValidateRange(1,255)][int]$WindowsInput = 15,
    [ValidateRange(1,255)][int]$MacInput = 16,
    [switch]$CheckOnly
)
$ErrorActionPreference = 'Stop'
$root = Join-Path $env:LOCALAPPDATA 'DisplayHandoff'
$script = Join-Path $root 'Switch.ps1'
$desktop = [Environment]::GetFolderPath('Desktop')
$startup = [Environment]::GetFolderPath('Startup')
$links = [ordered]@{
    (Join-Path $desktop 'Switch to Mac.lnk') = 'Mac'
    (Join-Path $desktop 'Restore Windows displays.lnk') = 'Recover'
    (Join-Path $startup 'Display Handoff.lnk') = 'Listen'
}
$mailbox = $MacShare
$events = Join-Path $mailbox 'events.log'
if (![IO.File]::Exists($events)) { throw 'Open the Mac mailbox SMB path in Explorer and verify that events.log is accessible.' }
$probe = Join-Path $mailbox ('.display-handoff-check-' + [guid]::NewGuid().ToString('N'))
try { [IO.File]::WriteAllText($probe, '') }
finally { if ([IO.File]::Exists($probe)) { [IO.File]::Delete($probe) } }

Add-Type -Path (Join-Path $PSScriptRoot 'WindowsDisplay.cs')
$displays = [WindowsDisplay]::Discover()
[WindowsDisplay]::Configure($displays[0], $displays[1], $WindowsInput, $MacInput)
$readback = [WindowsDisplay]::Input()
if ($readback -ne $WindowsInput) {
    throw "Windows read input $readback. Select the Windows input on the shared monitor and check its DDC/CI settings and input code."
}
if ($CheckOnly) { Write-Output 'Both display paths, Windows DDC readback, and SMB access verified.'; exit }

foreach ($path in $links.Keys) {
    if ([IO.File]::Exists($path)) { throw "A shortcut already exists at $path. Run Uninstall.ps1 before reinstalling." }
}
$null = New-Item -ItemType Directory -Path $root -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'WindowsDisplay.cs'),(Join-Path $PSScriptRoot 'Switch.ps1'),(Join-Path $PSScriptRoot 'Protocol.ps1') -Destination $root -Force
[WindowsDisplay]::CaptureDual((Join-Path $root 'layout.snapshot'))
[ordered]@{ MacShare = $MacShare; WindowsInput = $WindowsInput; MacInput = $MacInput; Permanent = $displays[0]; Shared = $displays[1] } |
    ConvertTo-Json | Set-Content -LiteralPath (Join-Path $root 'config.json') -Encoding UTF8

$powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$shell = New-Object -ComObject WScript.Shell
foreach ($path in $links.Keys) {
    $shortcut = $shell.CreateShortcut($path)
    $shortcut.TargetPath = $powershell
    $shortcut.Arguments = "-NoProfile -WindowStyle Hidden -File `"$script`" -Action $($links[$path])"
    $shortcut.WorkingDirectory = $root
    $shortcut.Save()
}
Start-Process -FilePath $powershell -ArgumentList "-NoProfile -WindowStyle Hidden -File `"$script`" -Action Listen" -WindowStyle Hidden
Write-Output 'Installed. Use Switch to Mac on the Windows desktop.'
