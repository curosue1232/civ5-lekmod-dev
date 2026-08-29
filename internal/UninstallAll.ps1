param([string]$CivPath='')
$ErrorActionPreference='Stop'
$Root=$PSScriptRoot
. (Join-Path $Root 'LekTools.ps1')
function W([string]$s,[ConsoleColor]$c=[ConsoleColor]::Gray){ Write-Host $s -ForegroundColor $c }

function Invoke-Child([string]$Label,[string]$Script,[string]$Civ){
    W ''
    W ('==== '+$Label+' ====') Cyan
    if(!(Test-LEKPath $Script)){ W ('Skipped (not present): '+$Script) DarkGray; return }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Script -CivPath $Civ
    if($LASTEXITCODE -ne 0){ W ("$Label reported a non-zero exit; continuing uninstall order.") Yellow }
}

try {
    W '============================================================' Cyan
    W ' LEKMOD 30.7 COMBINED UNINSTALL: FAIR TRADES + RAS WONDER HOTFIX + CORE' Cyan
    W '============================================================' Cyan
    if(Test-LEKCivRunning){ throw 'Civilization V appears to be running. Close it before uninstalling.' }

    $civ=Find-LEKCivV $CivPath
    if(!$civ){ $m=Read-Host 'Paste Civilization V install folder'; if($m){ $civ=Find-LEKCivV $m } }
    if(!$civ){ throw 'Civilization V install folder not found.' }
    W ('Civ V: '+$civ) Green
    W 'Uninstall order (reverse of install): Thumb Next Action -> Fair Trades -> RAS wonder -> RAS -> UltraFast -> Host Instant Start -> Reroll/Rehost' Gray

    W ''
    W 'This will remove all patches this stack installed at the path above.' Yellow
    $confirm=Read-Host 'Continue? (Y/N)'
    if($confirm -notmatch '^[Yy]'){ W 'Cancelled. Nothing was changed.' Yellow; exit 0 }

    $C=Join-Path $Root 'core'
    Invoke-Child '1/7  Thumb Next Action v0.1'          (Join-Path $Root 'thumb-action\Uninstall.ps1') $civ
    Invoke-Child '2/7  Fair Trades'                    (Join-Path $Root 'fair\Uninstall.ps1') $civ
    Invoke-Child '3/7  RAS wonder hotfix v0.8.9'        (Join-Path $Root 'ras-wonder\Uninstall.ps1') $civ
    Invoke-Child '4/7  RAS MP Bridge v0.8.8'            (Join-Path $C 'RAS\UNINSTALL_RAS_V088_RESTART_SETTINGS_REPLAY.ps1') $civ
    Invoke-Child '5/7  UltraFast MP Startup v0.3.1'     (Join-Path $C 'U\UNINSTALL_ULTRAFAST_MP_STARTUP_V03_REROLLSAFE.ps1') $civ
    Invoke-Child '6/7  Host Instant Start v0.1'         (Join-Path $C 'H\UNINSTALL_HOST_INSTANT_START_V01.ps1') $civ
    Invoke-Child '7/7  MP Reroll / Rehost v0.21'        (Join-Path $C 'R\UNINSTALL_V021.ps1') $civ

    W ''
    W '============================================================' Green
    W ' COMBINED UNINSTALL COMPLETE' Green
    W '============================================================' Green
    W 'It does NOT remove the older RAS v0.8.7.x base, which this stack does not own.' Yellow
    exit 0
} catch {
    W ''
    W ('ERROR: '+$_.Exception.Message) Red
    if($_.InvocationInfo -and $_.InvocationInfo.PositionMessage){ W $_.InvocationInfo.PositionMessage DarkGray }
    exit 1
}
