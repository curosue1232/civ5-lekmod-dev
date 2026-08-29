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
    W ' LEKMOD 30.7 COMBINED INSTALL: CORE + RAS WONDER + FAIR TRADES + SPACE ACTION' Cyan
    W '============================================================' Cyan
    if(Test-LEKCivRunning){ throw 'Civilization V appears to be running. Close it before installing.' }

    $civ=Find-LEKCivV $CivPath
    if(!$civ){ $m=Read-Host 'Paste Civilization V install folder'; if($m){ $civ=Find-LEKCivV $m } }
    if(!$civ){ throw 'Civilization V install folder not found.' }
    W ('Civ V: '+$civ) Green
    W 'Install order: Reroll -> Host Instant Start -> UltraFast -> RAS -> RAS wonder -> Fair Trades -> Space Next Action' Gray

    Show-LEKPrerequisiteMenu @(
        [pscustomobject]@{ Name='LEKMOD v30.7 (required base mod)'; Url='https://github.com/EnormousApplePie/Lekmod/releases/tag/v30.7'; Detected=(Test-LEKModPresent $civ) }
        [pscustomobject]@{ Name='EUI, v1.28 or earlier (v1.29+ is not supported)'; Url='https://forums.civfanatics.com/resources/civ5-enhanced-user-interface.24303/'; Detected=(Test-LEKEUIPresent $civ) }
    )
    W 'This installer never downloads or bundles LEKMOD or EUI -- both explicitly' DarkGray
    W 'prohibit redistribution. It only patches an existing install of each.' DarkGray

    W ''
    $confirm=Read-Host 'This will patch Civ V files at the path above. Continue? (Y/N)'
    if($confirm -notmatch '^[Yy]'){ W 'Cancelled. Nothing was changed.' Yellow; exit 0 }

    W ''
    W 'Checking for LEKMOD v30.7...' Cyan
    if(!(Test-LEKModPresent $civ)){
        W ''
        W 'LEKMOD v30.7 was not found at Assets\DLC\LEKMOD_V30.7.' Red
        W 'This installer only patches an existing LEKMOD install -- it never bundles' Yellow
        W 'LEKMOD itself, because LEKMOD''s own license prohibits redistributing its' Yellow
        W 'files without the author''s explicit permission.' Yellow
        Open-LEKPrereqLink 'the official LEKMOD v30.7 release' 'https://github.com/EnormousApplePie/Lekmod/releases/tag/v30.7'
        Open-LEKPrereqLink 'the LEKMOD Discord (install help)' 'https://discord.gg/VQBNPmc'
        throw 'Install LEKMOD v30.7 first, then rerun this installer.'
    }
    W 'LEKMOD v30.7 detected.' Green

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
    Invoke-Child '6/7  Fair Trades'                        (Join-Path $Root 'fair\Install.ps1') $civ
    Invoke-Child '7/7  Space Next Action v0.2'              (Join-Path $Root 'thumb-action\Install.ps1') $civ

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
