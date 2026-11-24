# TactriFree-Setup.ps1 - Windows 7 / 8 / 8.1 version: install / uninstall the TactriFree J2534 driver for the OpenPort 2.0.
# Written for Windows PowerShell 2.0 / .NET 2.0 (what Windows 7 ships with); also runs on newer PowerShell.
#
#   Install   : TactriFree-Setup.ps1                 (Administrator; or double-click "installer.cmd")
#   Uninstall : TactriFree-Setup.ps1 -Uninstall      (or Control Panel > Programs > TactriFree, or "Uninstall TactriFree.cmd")
#   Preview   : add -Plan  (shows every step, changes nothing, no Administrator needed)
#
# What install does (each step logged to <ProgramFiles>\TactriFree\setup.log):
#  1. DLLs: tactrifree32.dll -> <ProgramFiles(x86)>\TactriFree, tactrifree64.dll -> <ProgramFiles>\TactriFree
#     (32-bit Windows: only tactrifree32.dll, in <ProgramFiles>\TactriFree).
#  2. J2534 registry entries "TactriFree" (32-bit programs: WOW6432Node; 64-bit programs: native key). An OpenPort/Tactrix
#     entry whose DLL no longer exists is deleted. Programs using the standard J2534 interface (RomRaider, FastECU, ...)
#     then list "TactriFree J2534 for OpenPort 2.0".
#  3. USB driver: binds the cable (USB\VID_0403&PID_CC4D, or USB\VID_0403&PID_CC4C&MI_00; never the CC4B bootloader) to
#     Microsoft's WinUSB driver, part of Windows 7 / 8 / 8.1. The package (tactrifree_winusb.inf + .cat) has no driver code of its
#     own. Its catalog is signed on THIS PC with a certificate created here for that one purpose; the certificate is
#     trusted on this PC only and its private key is deleted right after signing, so nothing else can be signed with it.
#     The original Tactrix driver is NOT removed: uninstalling TactriFree and replugging the cable gives the cable back
#     to it (EcuFlash needs it: this package has no EcuFlash bridge).
#  4. An entry in Control Panel > Programs and Features for uninstalling.
# Uninstall reverses every step that install recorded (install-state.xml).
#
# Not affiliated with or endorsed by Tactrix. "OpenPort 2.0" names the hardware TactriFree is compatible with.
#
# TEST ONLY: -SandboxRoot <dir> redirects every folder to <dir> and every registry write to HKCU\Software\TactriFreeSandbox,
# skips the Administrator check, makes the signing certificate in the current user's store and installs no driver.

param([switch]$Uninstall, [switch]$Plan, [switch]$RebindDriver, [string]$SandboxRoot = '', [switch]$NoPause)
$ErrorActionPreference = 'Stop'
$Version = '1.0 beta7 for Windows 7/8/8.1'
$Here    = Split-Path -Parent $MyInvocation.MyCommand.Definition
$HwIds   = @('USB\VID_0403&PID_CC4D', 'USB\VID_0403&PID_CC4C&MI_00')
$Sandbox = [bool]$SandboxRoot
$Is64Os  = ($env:PROCESSOR_ARCHITECTURE -eq 'AMD64') -or ($env:PROCESSOR_ARCHITEW6432 -eq 'AMD64')

# ---------------------------------------------------------------- locations
if($Sandbox){
    $PF64 = Join-Path $SandboxRoot 'Program Files'; $PF86 = Join-Path $SandboxRoot 'Program Files (x86)'
    $RegBase = [Microsoft.Win32.Registry]::CurrentUser; $RegPrefix = 'Software\TactriFreeSandbox\'
    $Reg32Root = $RegPrefix + 'SOFTWARE\WOW6432Node'; $Reg64Root = $RegPrefix + 'SOFTWARE'
} else {
    if($Is64Os){ $PF64 = $env:ProgramW6432; if(-not $PF64){ $PF64 = $env:ProgramFiles }; $PF86 = ${env:ProgramFiles(x86)} }
    else { $PF64 = $env:ProgramFiles; $PF86 = $env:ProgramFiles }
    $RegBase = [Microsoft.Win32.Registry]::LocalMachine; $RegPrefix = ''          # 64-bit PowerShell: the 64-bit view
    if($Is64Os){ $Reg32Root = 'SOFTWARE\WOW6432Node' } else { $Reg32Root = 'SOFTWARE' }
    $Reg64Root = 'SOFTWARE'
}
$Dir64 = Join-Path $PF64 'TactriFree'
$Dir86 = Join-Path $PF86 'TactriFree'
foreach($d in $Dir64,$Dir86){ if(-not [IO.Path]::IsPathRooted($d) -or (Split-Path $d -Leaf) -ne 'TactriFree'){ throw "Unexpected install folder '$d'" } }
$State     = Join-Path $Dir64 'install-state.xml'
$LogFile   = Join-Path $Dir64 'setup.log'
$J2534Key  = 'PassThruSupport.04.04\TactriFree'
$UninstKey = $RegPrefix + 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\TactriFree'
$CertName  = "CN=TactriFree local driver signing ($env:COMPUTERNAME)"

# ---------------------------------------------------------------- helpers
$script:log = New-Object System.Collections.ArrayList
$script:curStep = 'checks before starting'; $script:curAction = ''; $script:logTemp = $false
function Say($m){ $l = "{0:HH:mm:ss} {1}" -f (Get-Date), $m; Write-Host $m; [void]$script:log.Add($l) }
function Step($m){ $script:curStep = $m; $script:curAction = ''; Say ''; Say "== $m" }
function Do-It([string]$what, [scriptblock]$action){
    $script:curAction = $what
    if($Plan){ Say "   [plan] $what" } else { Say "   $what"; & $action } }
# Log: <ProgramFiles>\TactriFree\setup.log; %TEMP%\tactrifree-setup.log if that cannot be written (no Administrator, failed early) and for an uninstall
function Save-Log(){
    $lines = [string[]]$script:log.ToArray()
    if(-not $Plan -and -not $script:logTemp){
        try { New-Item -ItemType Directory -Force $Dir64 | Out-Null; Add-Content -Path $LogFile -Value $lines -Encoding UTF8; return $LogFile } catch {} }
    $tmp = Join-Path $env:TEMP 'tactrifree-setup.log'
    try { Add-Content -Path $tmp -Value $lines -Encoding UTF8; return $tmp } catch {}
    return '' }
function Win32-Text($code){ try { return (New-Object ComponentModel.Win32Exception([int]$code)).Message } catch { return '' } }
# Everything a tester needs to report a failure: what was being done, the error, where in this script, inner errors.
function Report-Error($e){
    Say ''
    Say '#####################################################################'
    Say '  SETUP FAILED - please send this whole window (or the log file named'
    Say '  below) to the TactriFree developer.'
    Say '#####################################################################'
    Say ("  step      : " + $script:curStep)
    if($script:curAction){ Say ("  action    : " + $script:curAction) }
    Say ("  error     : " + $e.Exception.Message)
    Say ("  type      : " + $e.Exception.GetType().FullName)
    if($e.Exception -is [Runtime.InteropServices.COMException] -or $e.Exception -is [ComponentModel.Win32Exception]){
        Say ("  code      : 0x{0:X8}" -f (U32 $e.Exception.ErrorCode)) }
    if($e.InvocationInfo -and $e.InvocationInfo.ScriptLineNumber){
        Say ("  where     : line " + $e.InvocationInfo.ScriptLineNumber + ": " + ([string]$e.InvocationInfo.Line).Trim()) }
    $inner = $e.Exception.InnerException
    while($inner){ Say ("  inner     : " + $inner.GetType().FullName + ": " + $inner.Message); $inner = $inner.InnerException }
    Say ("  windows   : " + [Environment]::OSVersion.VersionString + $(if($Is64Os){', 64-bit'}else{', 32-bit'}) +
         ", PowerShell " + $PSVersionTable.PSVersion + ", .NET " + [Environment]::Version + ", process " + (8 * [IntPtr]::Size) + "-bit")
    Say ("  script    : " + $MyInvocation.ScriptName) }
function Reg-Set($path, $values){             # $values: hashtable name -> string | int
    $k = $RegBase.CreateSubKey($path)
    foreach($n in $values.Keys){ $v = $values[$n]
        if($v -is [int]){ $k.SetValue($n, $v, [Microsoft.Win32.RegistryValueKind]::DWord) }
        else { $k.SetValue($n, [string]$v, [Microsoft.Win32.RegistryValueKind]::String) } }
    $k.Close() }
function Reg-Exists($path){ $k = $RegBase.OpenSubKey($path); if($k){ $k.Close(); return $true }; return $false }
function Reg-Delete($path){ if(Reg-Exists $path){ $RegBase.DeleteSubKeyTree($path) } }
function J2534-Values($name, $dll){
    return @{ Name=$name; Vendor='TactriFree'; ConfigApplication=''; FunctionLibrary=$dll; DeviceId=0;
        CAN=1; ISO9141=1; ISO9141_CH1=1; ISO9141_CH2=1; ISO9141_CH3=1; ISO14230=1; ISO14230_CH1=1; ISO14230_CH2=1;
        ISO14230_CH3=1; ISO15765=1; J1850PWM=0; J1850VPW=0 } }
function U32($i){ return [BitConverter]::ToUInt32([BitConverter]::GetBytes([int]$i), 0) }
function Cable-Status(){                      # the J2534-mode cable as Windows sees it now (present devices only)
    $r = @{ present=$false; service=''; instance=''; inf='' }
    $dev = @(Get-WmiObject Win32_PnPEntity -ErrorAction SilentlyContinue | Where-Object {
        $_.DeviceID -like 'USB\VID_0403&PID_CC4D\*' -or $_.DeviceID -like 'USB\VID_0403&PID_CC4C&MI_00\*' }) | Select-Object -First 1
    if(-not $dev){ return $r }
    $r.present = $true; $r.instance = [string]$dev.DeviceID; $r.service = [string]$dev.Service
    try { $lm = [Microsoft.Win32.Registry]::LocalMachine
          $ek = $lm.OpenSubKey('SYSTEM\CurrentControlSet\Enum\' + $r.instance)
          if($ek){ $drv = [string]$ek.GetValue('Driver'); $ek.Close()
              if($drv){ $ck = $lm.OpenSubKey('SYSTEM\CurrentControlSet\Control\Class\' + $drv)
                  if($ck){ $r.inf = [string]$ck.GetValue('InfPath'); $ck.Close() } } } } catch {}
    return $r }
function Inf-Version($text){                  # DriverVer = mm/dd/yyyy,a.b.c.d  ->  [version]
    $m = [regex]::Match($text, 'DriverVer\s*=\s*[^,\r\n]*,\s*([0-9.]+)')
    if($m.Success){ return [version]$m.Groups[1].Value }; return [version]'0.0' }
function Our-Packages(){                      # TactriFree WinUSB packages in Windows' INF folder: @{pub; ver}
    $r = @()
    foreach($f in @(Get-ChildItem (Join-Path $env:windir 'INF') -Filter 'oem*.inf' -ErrorAction SilentlyContinue)){
        try { $t = [IO.File]::ReadAllText($f.FullName) } catch { continue }
        if($t.Contains('TactriFree project') -and $t.Contains('tactrifree_winusb.cat')){
            $r += New-Object PSObject -Property @{ pub = $f.Name; ver = (Inf-Version $t) } } }
    return $r }
function Catalog-Signer($pub){                # thumbprint of the certificate that signed an installed package oemN.inf ('' if not readable)
    $c = Join-Path $env:SystemRoot ('System32\CatRoot\{F750E6C3-38EE-11D1-85E5-00C04FC295EE}\' + [IO.Path]::GetFileNameWithoutExtension($pub) + '.cat')
    if(-not (Test-Path -LiteralPath $c)){ return '' }
    $s = Get-AuthenticodeSignature -FilePath $c
    if($s.SignerCertificate){ return [string]$s.SignerCertificate.Thumbprint }; return '' }
function Read-State(){ if(Test-Path $State){ return (Import-Clixml $State) }; return $null }
function Save-State($s){ if($Plan){ return }               # install record; written after step 3 too (partial installs)
    New-Item -ItemType Directory -Force $Dir64 | Out-Null; $s | Export-Clixml -Path $State }

# P/Invoke: SetupAPI staging / removal and the forced driver update (the same calls Zadig/libwdi use). C# 2.0 syntax.
$native = @'
using System; using System.Text; using System.Runtime.InteropServices;
public static class TfSetup7 {
  [DllImport("newdev.dll", CharSet=CharSet.Unicode, SetLastError=true)]
  public static extern bool UpdateDriverForPlugAndPlayDevicesW(IntPtr hwnd, string hwid, string inf, uint flags, out bool reboot);
  [DllImport("setupapi.dll", CharSet=CharSet.Unicode, SetLastError=true)]
  public static extern bool SetupCopyOEMInfW(string src, string mediaLocation, uint mediaType, uint copyStyle,
                                             StringBuilder dest, int destSize, out int required, IntPtr component);
  [DllImport("setupapi.dll", CharSet=CharSet.Unicode, SetLastError=true)]
  public static extern bool SetupUninstallOEMInfW(string inf, uint flags, IntPtr reserved);
  // the error is read right here: read later from PowerShell it can already be overwritten (ciper/tactrifree#1)
  public static bool Bind(string hwid, string inf, uint flags, out bool reboot, out int err){
    bool ok = UpdateDriverForPlugAndPlayDevicesW(IntPtr.Zero, hwid, inf, flags, out reboot);
    if(ok) err = 0; else err = Marshal.GetLastWin32Error();
    return ok; }
}
'@
function Load-Native(){ if(-not ('TfSetup7' -as [type])){ Add-Type -TypeDefinition $native } }

# Certificate store helpers (.NET 2.0)
function Store-Open($name, $location){
    $s = New-Object Security.Cryptography.X509Certificates.X509Store($name, $location)
    $s.Open([Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite); return $s }
function Store-Find($name, $location, [scriptblock]$match){
    $s = Store-Open $name $location; $found = @($s.Certificates | Where-Object $match); $s.Close(); return $found }
function Store-Remove($name, $location, $thumb){
    $s = Store-Open $name $location; $n = 0
    foreach($c in @($s.Certificates | Where-Object { $_.Thumbprint -eq $thumb })){ $s.Remove($c); $n++ }
    $s.Close(); return $n }
function Store-Add($name, $location, $cert){ $s = Store-Open $name $location; $s.Add($cert); $s.Close() }

# Self-signed code-signing certificate via CertEnroll (COM, present on Windows 7; New-SelfSignedCertificate is not).
# SHA-1 so a Windows 7 without the SHA-2 updates can verify it; the key never leaves this PC and is deleted after signing.
function New-SigningCert($machine){
    $ctx = 1; if($machine){ $ctx = 2 }                                   # 1 = user, 2 = machine
    $dn = New-Object -ComObject X509Enrollment.CX500DistinguishedName; $dn.Encode($CertName, 0)
    $key = New-Object -ComObject X509Enrollment.CX509PrivateKey
    $key.ProviderName = 'Microsoft Enhanced RSA and AES Cryptographic Provider'
    $key.KeySpec = 2; $key.Length = 2048; $key.ExportPolicy = 0
    if($machine){ $key.MachineContext = 1 } else { $key.MachineContext = 0 }
    $key.Create()
    $oids = New-Object -ComObject X509Enrollment.CObjectIds
    $cs = New-Object -ComObject X509Enrollment.CObjectId; $cs.InitializeFromValue('1.3.6.1.5.5.7.3.3'); $oids.Add($cs)   # code signing
    $eku = New-Object -ComObject X509Enrollment.CX509ExtensionEnhancedKeyUsage; $eku.InitializeEncode($oids)
    $ku = New-Object -ComObject X509Enrollment.CX509ExtensionKeyUsage; $ku.InitializeEncode(0x80)                     # digital signature
    $req = New-Object -ComObject X509Enrollment.CX509CertificateRequestCertificate
    $req.InitializeFromPrivateKey($ctx, $key, '')
    $req.Subject = $dn; $req.Issuer = $dn
    $req.NotBefore = (Get-Date).AddDays(-1); $req.NotAfter = (Get-Date).AddYears(30)
    $req.X509Extensions.Add($eku); $req.X509Extensions.Add($ku)
    $sha1 = New-Object -ComObject X509Enrollment.CObjectId; $sha1.InitializeFromValue('1.3.14.3.2.26')
    $req.SignatureInformation.HashAlgorithm = $sha1
    $req.Encode()
    $enr = New-Object -ComObject X509Enrollment.CX509Enrollment; $enr.InitializeFromRequest($req)
    $b64 = $enr.CreateRequest(1)                                         # 1 = base64 without header
    $enr.InstallResponse(2, $b64, 1, '')                                 # 2 = allow untrusted (self-signed) -> My store
    $pub = New-Object Security.Cryptography.X509Certificates.X509Certificate2(,[Convert]::FromBase64String($b64))
    return @{ thumb = $pub.Thumbprint; pub = $pub; key = $key } }

function Main(){
# ---------------------------------------------------------------- preconditions
$mode = 'install'; if($Uninstall){ $mode = 'uninstall' }
$extra = ''; if($Plan){ $extra += ', PLAN ONLY - nothing is changed' }; if($Sandbox){ $extra += ', SANDBOX ' + $SandboxRoot }
Say "TactriFree $Version setup  ($mode$extra)"
Say ("   " + [Environment]::OSVersion.VersionString + $(if($Is64Os){', 64-bit'}else{', 32-bit'}) + ", PowerShell " + $PSVersionTable.PSVersion +
     ", .NET " + [Environment]::Version + ", process " + (8 * [IntPtr]::Size) + "-bit")
Say ("   package folder: " + $Here)
if(-not $Sandbox -and -not $Plan){
    $script:logTemp = $true
    $admin = (New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if(-not $admin){ throw 'Run as Administrator (right-click > Run as administrator, or use "installer.cmd").' }
    if($Is64Os -and [IntPtr]::Size -ne 8){ throw 'Run from 64-bit PowerShell (the .cmd launchers do this).' }
    $osv = [Environment]::OSVersion.Version
    if($osv.Major -ge 10){ throw 'This package is for Windows 7, 8 and 8.1. On Windows 10 and 11 use the normal TactriFree package (it also has the EcuFlash bridge).' }
    if($osv -lt (New-Object Version 6,1)){ throw 'Windows 7 or newer is needed (Vista and XP are not supported).' }
    $script:logTemp = $false
}
foreach($pn in 'FastECU','tcuflash','ecuflash'){ if(Get-Process $pn -ErrorAction SilentlyContinue){ throw "Close $pn first." } }
if(Get-Process javaw -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -match 'RomRaider' }){ throw 'Close RomRaider first.' }

# ================================================================= UNINSTALL
if($Uninstall){
    $script:logTemp = $true                                   # the TactriFree folder is removed: log to %TEMP%
    $st = Read-State
    if(-not $st){ Say "No install record ($State): removing only what is recognisably TactriFree's." }
    Step 'USB driver'
    # the recorded package and any other TactriFree package (left by a reinstall or an interrupted install)
    $pk = @(); if(-not $Sandbox){ $pk = @(Our-Packages | ForEach-Object { $_.pub }) }
    if($st -and $st.driverInf -and ($pk -notcontains [string]$st.driverInf)){ $pk += [string]$st.driverInf }
    if($pk.Count){ foreach($p in $pk){ $pp = $p
        Do-It "remove driver package $pp (the cable returns to the next best driver after a replug)" {
            Load-Native
            if([TfSetup7]::SetupUninstallOEMInfW($pp, 1, [IntPtr]::Zero)){ Say '   removed' }
            else { $e = [Runtime.InteropServices.Marshal]::GetLastWin32Error(); Say ("   NOT removed, error 0x{0:X8} {1}" -f (U32 $e), (Win32-Text $e)) } } } }
    else { Say '   no TactriFree driver package installed - left as it is' }
    # the recorded certificate AND any other TactriFree signing certificate (e.g. left by an interrupted install).
    # Sandbox: only its own recorded certificate, and never one that is also in the machine stores - the CurrentUser Root
    # and TrustedPublisher stores also SHOW the LocalMachine certificates, and run as Administrator a removal there deletes
    # the machine copy (a sandbox test removed a real installation's certificates this way)
    $rec = ''; if($st -and $st.certThumbprint){ $rec = [string]$st.certThumbprint }
    $machine = @(); if($Sandbox){ foreach($ms in 'Root','TrustedPublisher'){ $machine += @(Store-Find $ms 'LocalMachine' { $true } | ForEach-Object { $_.Thumbprint }) } }
    foreach($store in 'Root','TrustedPublisher'){
        $loc = 'LocalMachine'; if($Sandbox){ $loc = 'CurrentUser' }
        foreach($c in @(Store-Find $store $loc { if($Sandbox){ $rec -and $_.Thumbprint -eq $rec -and ($machine -notcontains $_.Thumbprint) }
                                                 else { ($rec -and $_.Thumbprint -eq $rec) -or $_.Subject -like 'CN=TactriFree local driver signing*' } })){
            $t = $c.Thumbprint
            Do-It "remove the local TactriFree signing certificate $($t.Substring(0,8)) from $store" { [void](Store-Remove $store $loc $t) } } }
    Step 'J2534 registry entries'
    foreach($rk in ($Reg32Root + '\' + $J2534Key), ($Reg64Root + '\' + $J2534Key)){
        if(Reg-Exists $rk){ Do-It "delete $rk" { Reg-Delete $rk } } }
    Step 'Files'
    foreach($f in (Join-Path $Dir86 'tactrifree32.dll'), (Join-Path $Dir64 'tactrifree64.dll')){
        if(Test-Path -LiteralPath $f){ Do-It "delete $f" { Remove-Item -LiteralPath $f -Force } } }
    Do-It 'delete the Programs and Features entry' { Reg-Delete $UninstKey }
    if(-not $Plan){
        Remove-Item -LiteralPath $State -Force -ErrorAction SilentlyContinue
        if($Sandbox){ foreach($d in $Dir86, $Dir64){ if(Test-Path -LiteralPath $d){ Remove-Item -LiteralPath $d -Recurse -Force } } }
        else {
            # this script may be running from <ProgramFiles>\TactriFree\setup: remove the folders a few seconds after it exits
            $cmd = "/c ping -n 5 127.0.0.1 >nul & rmdir /s /q `"$Dir64`" & rmdir /s /q `"$Dir86`""
            # started in the Windows folder: a working folder inside TactriFree's would block its own removal
            Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\cmd.exe') -ArgumentList $cmd -WindowStyle Hidden -WorkingDirectory $env:SystemRoot }
    }
    Say ''; if($Plan){ Say 'Plan complete - nothing was changed.'; return }
    Say 'TactriFree removed. Unplug and replug the cable.'
    return
}

# ================================================================= INSTALL
$need = @('x86\tactrifree32.dll', 'driver\tactrifree_winusb.inf', 'driver\tactrifree_winusb.cat')
if($Is64Os -or $Sandbox){ $need += 'x64\tactrifree64.dll' }
foreach($f in $need){ if(-not (Test-Path (Join-Path $Here $f))){ throw "Package file missing: $f (run this from the TactriFree package folder)." } }
$st = @{ version=$Version; installed=(Get-Date).ToString('s'); sandbox=$Sandbox; driverInf=''; certThumbprint=''; driverNote='' }
$prev = Read-State; if($prev){ foreach($k in 'driverInf','certThumbprint'){ if($prev[$k]){ $st[$k] = $prev[$k] } } }

Step '1. Driver files'
Do-It "copy tactrifree32.dll -> $Dir86" { New-Item -ItemType Directory -Force $Dir86 | Out-Null; Copy-Item (Join-Path $Here 'x86\tactrifree32.dll') $Dir86 -Force }
if($Is64Os -or $Sandbox){
    Do-It "copy tactrifree64.dll -> $Dir64" { New-Item -ItemType Directory -Force $Dir64 | Out-Null; Copy-Item (Join-Path $Here 'x64\tactrifree64.dll') $Dir64 -Force } }
Do-It "copy this setup (for uninstall) -> $Dir64\setup" {
    $sd = Join-Path $Dir64 'setup'
    if((Resolve-Path $Here).Path.TrimEnd('\') -ne $sd.TrimEnd('\')){
        New-Item -ItemType Directory -Force $sd | Out-Null
        Copy-Item (Join-Path $Here '*') $sd -Recurse -Force } }

Step '2. J2534 registry entries'
foreach($root in @($Reg32Root, $Reg64Root) | Select-Object -Unique){
    $pk = $RegBase.OpenSubKey($root + '\PassThruSupport.04.04'); if(-not $pk){ continue }
    $names = $pk.GetSubKeyNames()
    foreach($n in $names){
        if($n -eq 'TactriFree'){ continue }
        $k = $pk.OpenSubKey($n); if(-not $k){ continue }       # key gone between listing and opening
        $nm = [string]$k.GetValue('Name'); $fl = [string]$k.GetValue('FunctionLibrary'); $k.Close()
        if(($n + ' ' + $nm) -match 'OpenPort|Tactrix' -and $fl -and -not (Test-Path -LiteralPath $fl)){
            $full = $root + '\PassThruSupport.04.04\' + $n
            Do-It "remove broken J2534 entry '$n' (its DLL $fl does not exist)" { Reg-Delete $full } } }
    $pk.Close() }
$k32 = $Reg32Root + '\' + $J2534Key; $k64 = $Reg64Root + '\' + $J2534Key
Do-It "$k32  -> tactrifree32.dll (32-bit programs)" { Reg-Set $k32 (J2534-Values 'TactriFree J2534 for OpenPort 2.0' (Join-Path $Dir86 'tactrifree32.dll')) }
if($Is64Os -or $Sandbox){
    Do-It "$k64  -> tactrifree64.dll (64-bit programs)" { Reg-Set $k64 (J2534-Values 'TactriFree J2534 for OpenPort 2.0 (64-bit)' (Join-Path $Dir64 'tactrifree64.dll')) } }

Step '3. USB driver (WinUSB)'
$cs = @{ present=$false; service=''; instance=''; inf='' }; if(-not $Sandbox){ $cs = Cable-Status }
if($cs.present){ Say "   cable: $($cs.instance), driver service '$($cs.service)', INF '$($cs.inf)'" } else { Say '   cable: not plugged in' }
$newVer = Inf-Version ([IO.File]::ReadAllText((Join-Path $Here 'driver\tactrifree_winusb.inf')))
$ours = @(); if(-not $Sandbox){ $ours = @(Our-Packages) }
if($ours.Count){ Say ("   TactriFree driver packages in Windows: " + (($ours | ForEach-Object { "$($_.pub) v$($_.ver)" }) -join ', ') + "; this setup has v$newVer") }
$curOurs = @($ours | Where-Object { $_.pub -ieq $cs.inf }) | Select-Object -First 1
if($curOurs -and $curOurs.ver -ge $newVer -and -not $RebindDriver){
    Say "   the cable already uses TactriFree's driver package v$($curOurs.ver) - up to date"; $st.driverNote = 'TactriFree package current' }
else {
    $script:inUseInf = ''
    $work = Join-Path ([IO.Path]::GetTempPath()) ('tactrifree-driver-' + [Guid]::NewGuid().ToString('N').Substring(0,8))
    # try/finally: if anything below fails, the temporary folder still goes and what WAS done (certificate, driver
    # package) is recorded, so -Uninstall can remove it
    try {
    Do-It "prepare the driver package in $work" { New-Item -ItemType Directory -Force $work | Out-Null
        Copy-Item (Join-Path $Here 'driver\tactrifree_winusb.inf'), (Join-Path $Here 'driver\tactrifree_winusb.cat') $work }
    Do-It 'create a signing certificate for this PC only and sign the catalog with it' {
        $loc = 'LocalMachine'; if($Sandbox){ $loc = 'CurrentUser' }
        $c = New-SigningCert (-not $Sandbox)
        $st.certThumbprint = $c.thumb
        $mine = @(Store-Find 'My' $loc { $_.Thumbprint -eq $c.thumb }) | Select-Object -First 1
        if(-not $mine){ throw "signing certificate $($c.thumb) not found in $loc\My" }
        $sig = Set-AuthenticodeSignature -FilePath (Join-Path $work 'tactrifree_winusb.cat') -Certificate $mine
        if([string]$sig.Status -ne 'Valid' -and [string]$sig.Status -ne 'UnknownError'){ throw "catalog signing failed: $($sig.Status) $($sig.StatusMessage)" }
        foreach($store in 'Root','TrustedPublisher'){
            if($Sandbox -and $store -eq 'Root'){ Say '   (sandbox: not adding to Root - Windows would ask)'; continue }
            Store-Add $store $loc $c.pub; Say "   trusted on this PC: $store" }
        $c.key.Delete()                                                  # private key gone: the certificate can never sign again
        [void](Store-Remove 'My' $loc $c.thumb)
        Say "   private key deleted (certificate $($c.thumb))"
        if(-not $Sandbox){ $chk = Get-AuthenticodeSignature (Join-Path $work 'tactrifree_winusb.cat')
            if([string]$chk.Status -ne 'Valid'){ throw "catalog signature not valid after trusting the certificate: $($chk.Status) $($chk.StatusMessage)" }
            Say '   catalog signature: Valid' } }
    if($Sandbox){ Say '   (sandbox: driver package not installed)' }
    else {
        Do-It 'add the driver package to Windows (SetupCopyOEMInf)' {
            Load-Native
            $sb = New-Object System.Text.StringBuilder 520; $req = 0
            if(-not [TfSetup7]::SetupCopyOEMInfW((Join-Path $work 'tactrifree_winusb.inf'), $work, 1, 0, $sb, 520, [ref]$req, [IntPtr]::Zero)){
                $e = [Runtime.InteropServices.Marshal]::GetLastWin32Error(); throw ("adding the driver package failed, error 0x{0:X8} {1}" -f (U32 $e), (Win32-Text $e)) }
            $st.driverInf = Split-Path $sb.ToString() -Leaf
            Say "   added as $($st.driverInf)"
            # for a package identical to one it already has, Windows keeps ITS copy, signed at an earlier install: the
            # certificate just made then signs nothing, and the earlier one may no longer be trusted. That copy is removed
            # and the package added again, so the cable gets the package signed just now.
            $signer = Catalog-Signer $st.driverInf
            if($signer -and $signer -ne $st.certThumbprint){
                Say "   Windows kept its earlier copy $($st.driverInf) (signed at an earlier install by certificate $($signer.Substring(0,8))) - replace it with the package signed just now"
                if(-not [TfSetup7]::SetupUninstallOEMInfW($st.driverInf, 1, [IntPtr]::Zero)){ $e = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
                    Say ("   removing it failed, error 0x{0:X8} {1}" -f (U32 $e), (Win32-Text $e)) }
                $sb = New-Object System.Text.StringBuilder 520; $req = 0
                if(-not [TfSetup7]::SetupCopyOEMInfW((Join-Path $work 'tactrifree_winusb.inf'), $work, 1, 0, $sb, 520, [ref]$req, [IntPtr]::Zero)){
                    $e = [Runtime.InteropServices.Marshal]::GetLastWin32Error(); throw ("adding the driver package failed, error 0x{0:X8} {1}" -f (U32 $e), (Win32-Text $e)) }
                $st.driverInf = Split-Path $sb.ToString() -Leaf
                Say "   added as $($st.driverInf)"
                $signer = Catalog-Signer $st.driverInf
                if($signer -and $signer -ne $st.certThumbprint){
                    throw "Windows still uses its earlier copy of the driver package ($($st.driverInf), signed by certificate $signer); uninstall TactriFree, then run setup again" } } }
        Do-It 'bind the cable to it (forced, like Zadig''s Replace Driver)' {
            Load-Native
            $reboot = $false; $ok = $false; $err = [uint32]0; [int]$raw = 0
            foreach($id in $HwIds){                                      # whichever form of the cable is plugged in
                $ok = [TfSetup7]::Bind($id, (Join-Path $work 'tactrifree_winusb.inf'), 1, [ref]$reboot, [ref]$raw)
                $err = U32 $raw
                if($ok -or $err -ne [uint32]3758096907){ break } }        # 3758096907 = 0xE000020B ERROR_NO_SUCH_DEVINST
            $script:inUseInf = $st.driverInf                             # the package the cable is (or will be) on
            if($ok){ Say "   cable bound to WinUSB$(if($reboot){' (Windows asks for a restart)'})"; $st.driverNote = 'TactriFree package bound' }
            elseif($err -eq [uint32]3758096907){ Say '   cable not plugged in: the package is installed and Windows will use it when the cable is plugged in'
                                                 $st.driverNote = 'staged (cable absent)' }
            else {
                # Windows reported a failure (seen as error 0 when setup runs again over an installed TactriFree, ciper/
                # tactrifree#1). What counts is where the cable is now: on WinUSB with THIS version of TactriFree's package
                # it is ready; anything else stops setup with the details.
                $now = Cable-Status
                $nowOurs = $now.inf -and @(Our-Packages | Where-Object { $_.pub -ieq $now.inf -and $_.ver -ge $newVer }).Count -gt 0
                if($now.present -and $now.service -ieq 'WinUSB' -and $nowOurs){
                    $script:inUseInf = $now.inf; $st.driverInf = $now.inf       # record the package actually in use
                    Say ("   Windows reported error 0x{0:X8} for the bind, but the cable is on WinUSB with TactriFree's driver package {1} - OK" -f $err, $now.inf)
                    $st.driverNote = ('TactriFree package in use (bind reported error 0x{0:X8})' -f $err) }
                elseif(-not $now.present){
                    Say ("   bind reported error 0x{0:X8} and the cable is not plugged in: the package is installed and Windows will use it when the cable is plugged in" -f $err)
                    $st.driverNote = 'staged (cable absent)' }
                else { throw ("binding the cable failed, error 0x{0:X8} {1}; the cable is on driver service '{2}', INF '{3}'" -f $err, (Win32-Text $raw), $now.service, $now.inf) } } }
        # every other TactriFree package goes, same version included (a reinstall used to leave the previous one behind,
        # unrecorded); never the one the cable is on now
        # (listed again: the package list may have changed above)
        $list = $ours; if(-not $Plan){ $list = @(Our-Packages) }
        $stale = @($list | Where-Object { $_.pub -ine $st.driverInf -and $_.pub -ine $script:inUseInf })
        foreach($o in $stale){
            $op = $o.pub
            Do-It "remove the previous TactriFree driver package $op v$($o.ver)" {
                Load-Native; if(-not [TfSetup7]::SetupUninstallOEMInfW($op, 1, [IntPtr]::Zero)){ $e = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
                    Say ("   NOT removed, error 0x{0:X8} {1} (harmless: an unused old package)" -f (U32 $e), (Win32-Text $e)) } } }
        # signing certificates: keep every one that signs a TactriFree package still in Windows (the new one, or an
        # earlier one the cable stays on), remove the other TactriFree ones. Nothing is removed if a signer can't be read.
        if($Plan){ Say '   [plan] remove TactriFree signing certificates that sign none of the TactriFree driver packages left in Windows' }
        else {
            $keep = @(); $known = $true
            foreach($p in @(Our-Packages)){ $t = Catalog-Signer $p.pub; if($t){ $keep += $t } else { $known = $false } }
            if(-not $known){ Say '   the signer of a TactriFree driver package could not be read - earlier signing certificates kept' }
            else {
                foreach($store in 'Root','TrustedPublisher'){
                    foreach($old in @(Store-Find $store 'LocalMachine' { $_.Subject -like 'CN=TactriFree local driver signing*' -and ($keep -notcontains $_.Thumbprint) })){
                        $t = $old.Thumbprint
                        Do-It "remove the unused TactriFree signing certificate $($t.Substring(0,8)) from $store" { [void](Store-Remove $store 'LocalMachine' $t) } } } } }
    }
    } finally {
        if(-not $Plan){ Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue; Save-State $st } }
}

Step '4. Programs and Features entry'
$setupCopy = Join-Path $Dir64 'setup\TactriFree-Setup.ps1'
$psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
Do-It "register 'TactriFree' for uninstall" {
    Reg-Set $UninstKey @{ DisplayName='TactriFree'; DisplayVersion=$Version; Publisher='TactriFree (open source)';
        InstallLocation=$Dir64; NoModify=1; NoRepair=1;
        UninstallString="`"$psExe`" -NoProfile -ExecutionPolicy Bypass -File `"$setupCopy`" -Uninstall" } }

Save-State $st
Say ''
if($Plan){ Say 'Plan complete - nothing was changed. Run without -Plan (as Administrator) to install.'; return }
Say 'TactriFree installed.'
Say ' - RomRaider / FastECU / other J2534 programs: choose "TactriFree J2534 for OpenPort 2.0".'
Say ' - EcuFlash: not supported by this package; uninstall TactriFree and replug the cable to use EcuFlash.'
Say ' - Driver log: %TEMP%\tactrifree-debug.log'
}

# ================================================================= run: report any error in full, always pause at the end
$failed = $false
try { Main }
catch { $failed = $true; try { Report-Error $_ } catch { Write-Host ("SETUP FAILED: " + $_.Exception.Message) } }
$logAt = Save-Log
Say ''
if($logAt){ Say "Log file: $logAt" }
if($failed){ Say 'Setup did NOT finish. Nothing after the failed step was done.' }
if(-not $NoPause){ Write-Host ''; Read-Host 'Press Enter to close this window' | Out-Null }
if($failed){ exit 1 } else { exit 0 }
