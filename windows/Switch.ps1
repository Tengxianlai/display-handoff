param([ValidateSet('Listen','Mac','Recover','Check')][string]$Action = 'Check')
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
. (Join-Path $root 'Protocol.ps1')
$config = Get-Content -LiteralPath (Join-Path $root 'config.json') -Raw | ConvertFrom-Json
$mailbox = $config.MacShare
$events = Join-Path $mailbox 'events.log'
$snapshot = Join-Path $root 'layout.snapshot'
$request = Join-Path $root 'mac.request'
$reply = Join-Path $root 'mac.reply'
$log = Join-Path $root 'switch.log'

function Write-Log([string]$Message) {
    Add-Content -LiteralPath $log -Encoding UTF8 -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff') $Message"
}

function Read-Message([string]$Path) {
    if ([IO.File]::Exists($Path)) { [IO.File]::ReadAllText($Path).Trim() }
}

function Write-Message([string]$Path, [string]$Message) {
    $temporary = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    $backup = "$temporary.bak"
    try {
        [IO.File]::WriteAllText($temporary, $Message)
        if ([IO.File]::Exists($Path)) { [IO.File]::Replace($temporary, $Path, $backup) }
        else { [IO.File]::Move($temporary, $Path) }
    }
    finally {
        [IO.File]::Delete($temporary)
        [IO.File]::Delete($backup)
    }
}

function Read-Events { Get-Content -LiteralPath $events -Tail 32 -ErrorAction SilentlyContinue }

function Wait-Mac([string]$Id, [int]$Seconds, [string[]]$States) {
    $deadline = [DateTime]::UtcNow.AddSeconds($Seconds)
    do {
        $state = Find-HandoffEvent @(Read-Events) $Id ($States + @('input-mismatch','wake-timeout'))
        if ($state -eq 'input-mismatch') { throw 'Windows and Mac have different DDC input settings.' }
        if ($state -eq 'wake-timeout') { throw 'Mac could not read back the configured monitor input.' }
        if ($state) { return $state }
        Start-Sleep -Milliseconds 250
    } while ([DateTime]::UtcNow -lt $deadline)
    throw 'Timed out waiting for Mac. Check the Mac login session, file sharing, and monitor input.'
}

function Switch-ToMac([string]$Id) {
    $wakeRequest = Join-Path $mailbox 'wake.request'
    $message = "$Id $($config.WindowsInput) $($config.MacInput)"
    Write-Message $wakeRequest $message
    try {
        $state = Wait-Mac $Id 12 @('wake-ready','wake-active')
        Write-Log 'Mac is ready.'
        if ($state -eq 'wake-active' -or [WindowsDisplay]::Input() -ne [int]$config.WindowsInput) {
            $null = Wait-Mac $Id 10 @('wake-active')
            [WindowsDisplay]::AdoptMac($snapshot)
        }
        else {
            [WindowsDisplay]::SelectMac($snapshot, [Func[bool]]{
                try { (Wait-Mac $Id 23 @('wake-active')) -eq 'wake-active' }
                catch { Write-Log $_.Exception.Message; $false }
            })
        }
        Write-Message $reply "$Id ok"
        Write-Log 'Mac confirmed the shared input. Windows verified its remaining display.'
    }
    finally {
        if ((Read-Message $wakeRequest) -eq $message) { [IO.File]::Delete($wakeRequest) }
    }
}

function Switch-ToWindows([string]$Id) {
    $response = Join-Path $mailbox "return.$Id.reply"
    [WindowsDisplay]::Restore($snapshot)
    if ([WindowsDisplay]::Input() -ne [int]$config.WindowsInput) {
        Write-Message $response "$Id ready"
        $deadline = [DateTime]::UtcNow.AddSeconds(12)
        do {
            Start-Sleep -Milliseconds 350
            $selected = [WindowsDisplay]::Input()
        } until ($selected -eq [int]$config.WindowsInput -or [DateTime]::UtcNow -ge $deadline)
        if ($selected -ne [int]$config.WindowsInput) {
            throw 'Windows restored both displays. Select the Windows input in the shared monitor menu to finish.'
        }
    }
    Write-Message $response "$Id ok"
    Write-Log 'Windows verified the shared monitor input and dual-display layout.'
}

if ($Action -eq 'Mac') {
    $client = New-Object Threading.Mutex($false, 'Local\DisplayHandoff.Client')
    if (!$client.WaitOne(0)) { $client.Dispose(); exit }
    try {
        $id = [guid]::NewGuid().ToString('D')
        Write-Message $request $id
        $deadline = [DateTime]::UtcNow.AddSeconds(42)
        do {
            $message = Read-Message $reply
            if ($message -eq "$id ok") { exit }
            if ($message -like "$id error *") { throw $message.Substring($id.Length + 7) }
            Start-Sleep -Milliseconds 200
        } while ([DateTime]::UtcNow -lt $deadline)
        throw 'The switch timed out. Check the Windows background process and the SMB connection.'
    }
    catch {
        $shell = New-Object -ComObject WScript.Shell
        $null = $shell.Popup($_.Exception.Message, 18, 'Display Handoff', 48)
        exit 1
    }
    finally { $client.ReleaseMutex(); $client.Dispose() }
}

Add-Type -Path (Join-Path $root 'WindowsDisplay.cs')
[WindowsDisplay]::Configure($config.Permanent, $config.Shared, $config.WindowsInput, $config.MacInput)
if ($Action -eq 'Check') {
    [pscustomobject]@{ Layout = [WindowsDisplay]::Describe(); Input = [WindowsDisplay]::Input(); MacMailbox = [IO.File]::Exists($events) }
    exit
}
if ($Action -eq 'Recover') {
    [WindowsDisplay]::Restore($snapshot)
    if ([WindowsDisplay]::Input() -ne [int]$config.WindowsInput) {
        Write-Output 'If the shared screen is still on Mac, select the Windows input in the monitor menu.'
    }
    exit
}

$listener = New-Object Threading.Mutex($false, 'Local\DisplayHandoff.Listener')
if (!$listener.WaitOne(0)) { $listener.Dispose(); exit }
try {
    Write-Log 'Display Handoff listener started.'
    $lastMac = $lastReturn = ''
    while ($true) {
        try {
            $id = Read-Message $request
            if ($id -match '^[0-9a-f-]{36}$' -and $id -ne $lastMac) {
                $lastMac = $id
                if ([DateTime]::UtcNow - [IO.File]::GetLastWriteTimeUtc($request) -lt [TimeSpan]::FromSeconds(20)) {
                    try { Switch-ToMac $id }
                    catch { Write-Log $_.Exception.Message; Write-Message $reply "$id error $($_.Exception.Message)" }
                }
            }

            $returnId = Find-ReturnRequest @(Read-Events) ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
            if ($returnId -and $returnId -ne $lastReturn) {
                $lastReturn = $returnId
                try { Switch-ToWindows $returnId }
                catch {
                    Write-Log $_.Exception.Message
                    Write-Message (Join-Path $mailbox "return.$returnId.reply") "$returnId error $($_.Exception.Message)"
                }
            }
        }
        catch { Write-Log $_.Exception.Message }
        Start-Sleep -Milliseconds 350
    }
}
finally { $listener.ReleaseMutex(); $listener.Dispose() }
