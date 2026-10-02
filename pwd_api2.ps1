$ErrorActionPreference = 'SilentlyContinue'

# Get first page target
$targets = (curl.exe -s http://127.0.0.1:9222/json/list | ConvertFrom-Json)
$page = $targets | Where-Object { $_.type -eq 'page' } | Select-Object -First 1

$ws = New-Object System.Net.WebSockets.ClientWebSocket
$ct = [System.Threading.CancellationToken]::None
$ws.ConnectAsync([Uri]$page.webSocketDebuggerUrl, $ct).Wait()

$buf = [byte[]]::new(10485760)
$id = 0
function E {
    param([string]$js)
    $script:id++
    $m = @{ id = $script:id; method = "Runtime.evaluate"; params = @{ expression = $js; awaitPromise = $true; returnByValue = $true } }
    $j = ConvertTo-Json -Compress -InputObject $m -Depth 5
    $b = [System.Text.Encoding]::UTF8.GetBytes($j)
    $s = [ArraySegment[byte]]::new($b)
    $ws.SendAsync($s, 'Text', $true, $ct).Wait()
    $s2 = [ArraySegment[byte]]::new($buf)
    $r = $ws.ReceiveAsync($s2, $ct).Result
    return [System.Text.Encoding]::UTF8.GetString($buf, 0, $r.Count)
}

# Navigate to settings/passwords and wait LONG
$id++
$navM = @{ id = $id; method = "Page.navigate"; params = @{ url = "edge://settings/passwords" } }
$navJ = ConvertTo-Json -Compress -InputObject $navM -Depth 5
$navB = [System.Text.Encoding]::UTF8.GetBytes($navJ)
$navS = [ArraySegment[byte]]::new($navB)
$ws.SendAsync($navS, 'Text', $true, $ct).Wait()
Start-Sleep 25

# Verify page loaded
$r0 = E 'document.title + " @ " + location.href'
$o0 = $r0 | ConvertFrom-Json
Write-Output "page: $($o0.result.result.value)"

# Test 1: Get all passwordsPrivate methods
$r1 = E 'JSON.stringify(Object.getOwnPropertyNames(chrome.passwordsPrivate).sort())'
$o1 = $r1 | ConvertFrom-Json
Write-Output "passwordsPrivate methods: $($o1.result.result.value)"

# Test 2: Try Promise pattern
$r2 = E 'JSON.stringify(typeof chrome.passwordsPrivate.getSavedPasswordList)'
$o2 = $r2 | ConvertFrom-Json
Write-Output "getSavedPasswordList type: $($o2.result.result.value)"

# Test 3: Call as promise
$r3 = E 'chrome.passwordsPrivate.getSavedPasswordList().then(l => JSON.stringify(l)).catch(e => JSON.stringify({err: e.message}))'
$o3 = $r3 | ConvertFrom-Json
Write-Output "promise result: $($o3.result.result.value)"

# Test 4: Call with callback and setTimeout to wait
$r4 = E 'new Promise(r => { let done = false; chrome.passwordsPrivate.getSavedPasswordList(function(l) { if (!done) { done = true; r(JSON.stringify(l)); } }); setTimeout(() => { if (!done) { done = true; r(JSON.stringify({timeout: true})); } }, 10000); })'
$o4 = $r4 | ConvertFrom-Json
Write-Output "callback+timeout: $($o4.result.result.value)"

# Test 5: chrome.send pattern (legacy WebUI)
$r5 = E '(function() { try { chrome.send("getSavedPasswordsList"); return "chrome.send sent"; } catch(e) { return "chrome.send error: " + e.message; } })()'
$o5 = $r5 | ConvertFrom-Json
Write-Output "chrome.send: $($o5.result.result.value)"

# Wait for the async password list to arrive via onSavedPasswordsListChanged event
Start-Sleep 10

# Test 6: Check if we can access the passwords via the page's internal state
$r6 = E '
(function() {
    // Try to find the passwords data in the settings page JS
    if (window.settingsRoutes) return JSON.stringify({routes: Object.keys(window.settingsRoutes)});
    if (window.settings) return JSON.stringify({settings: Object.keys(window.settings)});
    
    // Check all global variables
    let globals = Object.keys(window).filter(k => k.toLowerCase().includes("password") || k.toLowerCase().includes("credential"));
    if (globals.length > 0) return JSON.stringify({globals: globals});
    
    // Check chrome object more thoroughly
    let ppKeys = chrome.passwordsPrivate ? Object.getOwnPropertyNames(chrome.passwordsPrivate) : [];
    let proto = chrome.passwordsPrivate ? Object.getOwnPropertyNames(Object.getPrototypeOf(chrome.passwordsPrivate)) : [];
    
    return JSON.stringify({
        ppKeys: ppKeys,
        proto: proto,
        globals: globals
    });
})()
'
$o6 = $r6 | ConvertFrom-Json
Write-Output "internal state: $($o6.result.result.value)"

# Test 7: Try to navigate the settings sub-page to passwords via DOM click
$r7 = E '
(function() {
    // Settings pages use a navigation menu - click on the "Passwords" item
    function clickInShadow(root, depth) {
        if (depth > 6) return false;
        let els = root.querySelectorAll("*");
        for (let el of els) {
            let text = el.textContent || "";
            if (text.includes("비밀번호") || text.includes("Password") || text.includes("password")) {
                if (el.click) { el.click(); return true; }
            }
            if (el.shadowRoot) {
                if (clickInShadow(el.shadowRoot, depth + 1)) return true;
            }
        }
        return false;
    }
    let clicked = clickInShadow(document, 0);
    return JSON.stringify({clicked: clicked});
})()
'
$o7 = $r7 | ConvertFrom-Json
Write-Output "nav click: $($o7.result.result.value)"

Start-Sleep 10

# Test 8: After clicking, try getSavedPasswordList again
$r8 = E 'new Promise(r => chrome.passwordsPrivate.getSavedPasswordList(function(l) { r(JSON.stringify(l)); }))'
$o8 = $r8 | ConvertFrom-Json
Write-Output "after click: $($o8.result.result.value)"

$ws.Dispose()
Write-Output "done"