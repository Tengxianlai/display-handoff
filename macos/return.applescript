on run
    set agentPath to (POSIX path of (path to home folder)) & "Library/Application Support/DisplayHandoff/agent.sh"
    try
        do shell script "/bin/bash " & quoted form of agentPath & " return"
    on error errorText
        display alert "Could not return to Windows" message errorText as warning
    end try
end run
