param([string]$CivPath='')
$ErrorActionPreference='Stop'
$Root=$PSScriptRoot
. (Join-Path $Root 'LekTools.ps1')
function W([string]$s,[ConsoleColor]$c=[ConsoleColor]::Gray){ Write-Host $s -ForegroundColor $c }

function Test-RASV0872Prerequisites([string]$Civ){
    $mpSetup=Join-LEKPath $Civ 'Assets\UI\FrontEnd\Multiplayer\GameSetup\MPGameSetupScreen.lua'
    $euiLoad=Join-LEKPath $Civ 'Assets\DLC\UI_bc1\GameSetup\LoadScreen.lua'
    $inGames=@(
        (Join-LEKPath $Civ 'Assets\UI\InGame\InGame.lua'),
        (Join-LEKPath $Civ 'Assets\DLC\Expansion\UI\InGame\InGame.lua'),
        (Join-LEKPath $Civ 'Assets\DLC\Expansion2\UI\InGame\InGame.lua'),
        (Join-LEKPath $Civ 'Assets\DLC\LEKMOD_V30.7\UI\InGame.lua')
    ) | Where-Object { Test-LEKPath $_ }

    $missing=@()
    if(!(Test-LEKContains $mpSetup 'GTAS_MP_V0872_STICKY_REROLL_CONTEXT')){ $missing+='RAS v0.8.7.2 MPGameSetup sticky-reroll context' }
    if(!(Test-LEKContains $euiLoad 'GTAS_MP_V0872_LOADSCREEN_HEARTBEAT')){ $missing+='RAS v0.8.7.2 EUI LoadScreen bypass instrumentation' }
    $hasInGame=$false
    foreach($p in $inGames){ if(Test-LEKContains $p 'GTAS_MP_V0872_INGAME_HEARTBEAT'){ $hasInGame=$true; break } }
    if(!$hasInGame){ $missing+='RAS v0.8.7.2 InGame safe-load handler' }
    return $missing
}

function Invoke-Child([string]$Label,[string]$Script,[string]$Civ){
    W ''
    W ('==== ' + $Label + ' ====') Cyan
    if(!(Test-LEKPath $Script)){ throw "Component script missing: $Script" }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Script -CivPath $Civ
    if($LASTEXITCODE -ne 0){ throw "$Label failed with exit code $LASTEXITCODE" }
}

try {
    W '============================================================' Cyan
    W ' LEKMOD 30.7 COMBINED INSTALL: CORE + RAS WONDER HOTFIX + FAIR TRADES' Cyan
    W '============================================================' Cyan
    if(Test-LEKCivRunning){ throw 'Civilization V appears to be running. Close it before installing.' }

    $civ=Find-LEKCivV $CivPath
    if(!$civ){ $m=Read-Host 'Paste Civilization V install folder'; if($m){ $civ=Find-LEKCivV $m } }
    if(!$civ){ throw 'Civilization V install folder not found.' }
    W ('Civ V: '+$civ) Green
    W 'Install order: Reroll v0.21 -> Host Instant Start v0.1 -> UltraFast v0.3.1 -> RAS v0.8.8 -> RAS wonder v0.8.9 -> Fair Trades' Gray

    $C=Join-Path $Root 'core'
    $missingRAS=@(Test-RASV0872Prerequisites $civ)
    $installRAS=$true
    if($missingRAS.Count -gt 0){
        W ''
        W 'RAS v0.8.8 prerequisites are NOT all present:' Yellow
        foreach($m in $missingRAS){ W ('  - '+$m) Yellow }
        W ''
        W 'The RAS v0.8.8 package is not a standalone base installer.' Yellow
        W 'Fair Trades does not depend on RAS and will still be installed. The combined' Yellow
        W 'installer can install the other three core patches plus Fair Trades safely.' Yellow
        $ans=Read-Host 'Continue without RAS v0.8.8 (and RAS wonder hotfix, which depends on it)? (Y/N)'
        if($ans -notmatch '^[Yy]'){ throw 'Cancelled before any files were changed. Install the required RAS v0.8.7.2 base first, then rerun this installer.' }
        $installRAS=$false
    } else {
        W 'RAS v0.8.7.2 bypass prerequisites detected.' Green
    }

    Invoke-Child '1/6  MP Reroll / Rehost v0.21'          (Join-Path $C 'R\INSTALL_V021.ps1') $civ
    Invoke-Child '2/6  Host Instant Start v0.1'            (Join-Path $C 'H\INSTALL_HOST_INSTANT_START_V01.ps1') $civ
    Invoke-Child '3/6  UltraFast MP Startup v0.3.1'        (Join-Path $C 'U\INSTALL_ULTRAFAST_MP_STARTUP_V03_REROLLSAFE.ps1') $civ

    if($installRAS){
        Invoke-Child '4/6  RAS MP Bridge v0.8.8 Restart Settings Replay' (Join-Path $C 'RAS\INSTALL_RAS_V088_RESTART_SETTINGS_REPLAY.ps1') $civ
        Invoke-Child '5/6  RAS wonder hotfix v0.8.9'       (Join-Path $Root 'ras-wonder\Install.ps1') $civ
    } else {
        W ''
        W 'SKIPPED 4/6-5/6 (RAS v0.8.8, RAS wonder hotfix) because the required v0.8.7.2 base was not installed.' Yellow
    }

    # Fair Trades depends only on Core (Reroll/Host/UltraFast), not on RAS v0.8.8
    # or the wonder hotfix -- install it regardless of $installRAS.
    Invoke-Child '6/6  Fair Trades'                        (Join-Path $Root 'fair\Install.ps1') $civ

    W ''
    W 'Running combined verification...' Cyan
    $rasMode = if($installRAS){ 'Required' } else { 'Skip' }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'VerifyAll.ps1') -CivPath $civ -RASMode $rasMode
    if($LASTEXITCODE -ne 0){ throw 'Installation completed, but combined verification reported a real failure.' }

    W ''
    W '============================================================' Green
    W ' COMBINED INSTALL COMPLETE' Green
    W '============================================================' Green
    if(!$installRAS){ W 'Base 3 core patches installed; RAS v0.8.8 and everything depending on it were skipped.' Yellow }
    exit 0
} catch {
    W ''
    W ('ERROR: '+$_.Exception.Message) Red
    if($_.InvocationInfo -and $_.InvocationInfo.PositionMessage){ W $_.InvocationInfo.PositionMessage DarkGray }
    W 'No automatic rollback was attempted; each component installer keeps its own backups.' Yellow
    exit 1
}
