function Find-HandoffEvent([string[]]$Lines, [string]$Id, [string[]]$States) {
    for ($index = $Lines.Length - 1; $index -ge 0; $index--) {
        $fields = $Lines[$index] -split ' ', 3
        if ($fields.Count -eq 3 -and $fields[1] -ceq $Id -and $fields[2] -cin $States) {
            return $fields[2]
        }
    }
}

function Find-ReturnRequest([string[]]$Lines, [long]$Now) {
    for ($index = $Lines.Length - 1; $index -ge 0; $index--) {
        if ($Lines[$index] -cmatch '^(\d{10}) ([0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}) return-request$') {
            $age = $Now - [long]$Matches[1]
            if ($age -ge -5 -and $age -lt 35) { return $Matches[2] }
            return
        }
    }
}
