$ErrorActionPreference = 'SilentlyContinue'

# Navigate to edge://settings/passwords and use Promise-based API
$targets = (curl.exe -s http://127.0.0.1:9222/json/list | ConvertFrom-Json)
$page = $targets | Where-Object { $_.type -eq 'page' } | Select-Object -First 1

$ws = New-Object System.Net.WebSockets.ClientWebSocket
$ct = [System.Threading.CancellationToken]::None
$ws.ConnectAsync([Uri]$page.webSocketDebuggerUrl, $ct).Wait()

$buf = [byte[]]::new(10485760)
$script:mid = 0

function CdpEval {
    param([string]$js)
    $script:mid++
    $m = @{ id = $script:mid; method = "Runtime.evaluate"; params = @{ expression = $js; awaitPromise = $true; returnByValue = $true } }
    $j = ConvertTo-Json -Compress -InputObject $m -Depth 5
    $b = [System.Text.Encoding]::UTF8.GetBytes($j)
    $s = [ArraySegment[byte]]::new($b)
    $ws.SendAsync($s, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait()
    $s2 = [ArraySegment[byte]]::new($buf)
    $r = $ws.ReceiveAsync($s2, $ct).Result
    return [System.Text.Encoding]::UTF8.GetString($buf, 0, $r.Count)
}

# Navigate
$null = CdpEval 'void(0)'
$navM = @{ id = 999; method = "Page.navigate"; params = @{ url = "edge://settings/passwords" } }
$navJ = ConvertTo-Json -Compress -InputObject $navM -Depth 5
$navB = [System.Text.Encoding]::UTF8.GetBytes($navJ)
$navS = [ArraySegment[byte]]::new($navB)
$ws.SendAsync($navS, 'Text', $true, $ct).Wait()
Start-Sleep 15
$null = CdpEval 'void(0)'

# ═══ Try multiple API patterns ═══
Write-Output "=== test 1: callback pattern ==="
$r1 = CdpEval 'new Promise(r => { chrome.passwordsPrivate.getSavedPasswordList(function(l) { r(JSON.stringify(l)) }) })'
$o1 = $r1 | ConvertFrom-Json
$v1 = $o1.result.result.value
Write-Output "result: $($v1.Substring(0, [Math]::Min(200, [string]$v1)))"

Write-Output ""
Write-Output "=== test 2: promise pattern ==="
$r2 = CdpEval 'new Promise(async r => { try { const l = await chrome.passwordsPrivate.getSavedPasswordList(); r(JSON.stringify(l)); } catch(e) { r(JSON.stringify({error: e.message})); } })'
$o2 = $r2 | ConvertFrom-Json
$v2 = $o2.result.result.value
Write-Output "result: $($v2.Substring(0, [Math]::Min(200, [string]$v2)))"

Write-Output ""
Write-Output "=== test 3: direct call ==="
$r3 = CdpEval 'chrome.passwordsPrivate.getSavedPasswordList()'
$o3 = $r3 | ConvertFrom-Json
$v3 = $o3.result.result.value
Write-Output "result: $($v3.Substring(0, [Math]::Min(200, [string]$v3)))"

Write-Output ""
Write-Output "=== test 4: introspect API ==="
$r4 = CdpEval 'JSON.stringify({type: typeof chrome.passwordsPrivate, keys: Object.getOwnPropertyNames(Object.getPrototypeOf(chrome.passwordsPrivate)), own: Object.keys(chrome.passwordsPrivate)})'
$o4 = $r4 | ConvertFrom-Json
$v4 = $o4.result.result.value
Write-Output "API info: $v4"

Write-Output ""
Write-Output "=== test 5: passwordsManagerPrivate ==="
$r5 = CdpEval 'typeof chrome.passwordsManagerPrivate !== "undefined" ? JSON.stringify(Object.keys(chrome.passwordsManagerPrivate)) : "not found"'
$o5 = $r5 | ConvertFrom-Json
$v5 = $o5.result.result.value
Write-Output "passwordsManagerPrivate: $v5"

Write-Output ""
Write-Output "=== test 6: all chrome.* keys ==="
$r6 = CdpEval 'JSON.stringify(Object.keys(chrome).sort())'
$o6 = $r6 | ConvertFrom-Json
$v6 = $o6.result.result.value
Write-Output "chrome keys: $v6"

Write-Output ""
Write-Output "=== test 7: page URL check ==="
$r7 = CdpEval 'window.location.href'
$o7 = $r7 | ConvertFrom-Json
$v7 = $o7.result.result.value
Write-Output "URL: $v7"

$ws.Dispose()
Write-Output "done"