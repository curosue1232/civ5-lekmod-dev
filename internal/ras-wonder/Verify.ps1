param([string]$CivPath='')
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'LekTools.ps1')
function W([string]$s,[ConsoleColor]$c=[ConsoleColor]::Gray){ Write-Host $s -ForegroundColor $c }

try {
    W '============================================================' Cyan
    W ' RAS MP BRIDGE v0.8.9 - WONDER GRAPHICS VERIFY' Cyan
    W '============================================================' Cyan
    $civ=Find-LEKCivV $CivPath
    if(!$civ){ $m=Read-Host 'Paste Civilization V install folder'; if($m){$civ=Find-LEKCivV $m} }
    if(!$civ){ throw 'Civilization V was not found.' }

    $inGame=Join-LEKPath $civ 'Assets\DLC\LEKMOD_V30.7\UI\InGame.lua'
    $loadScreen=Join-LEKPath $civ 'Assets\DLC\UI_bc1\GameSetup\LoadScreen.lua'
    $startGame=Join-LEKPath $civ 'Assets\UI\FrontEnd\Multiplayer\GTAS_StartGame.lua'
    $good=$true

    foreach($c in @(
        @('v0.8.8 safe late replay retained', (Test-LEKContains $inGame '-- GTAS_MP_BRIDGE_V088_REROLL_RUNTIME_REPLAY_BEGIN')),
        @('v0.8.7.1 LoadScreen phase retained', (Test-LEKContains $loadScreen '-- GTAS_MP_BRIDGE_V0871_LOADSCREEN_BEGIN')),
        @('reroll wonder LoadScreen begin', (Test-LEKContains $loadScreen '-- GTAS_MP_V089_REROLL_WONDER_LOADSCREEN_BEGIN')),
        @('reroll wonder LoadScreen end', (Test-LEKContains $loadScreen '-- GTAS_MP_V089_REROLL_WONDER_LOADSCREEN_END')),
        @('Dawn-of-Man pre-render registration', (Test-LEKContains $loadScreen 'Events.SerialEventDawnOfManShow.Add(RunRerollWonderPreRender)')),
        @('wonder-only DisableOtherWonders call', (Test-LEKContains $loadScreen 'DisableOtherWonders()')),
        @('wonder-only PlaceWonders call', (Test-LEKContains $loadScreen 'PlaceWonders()')),
        @('no early InitMap call in v0.8.9 block', (-not (([IO.File]::ReadAllText($loadScreen) -split '-- GTAS_MP_V089_REROLL_WONDER_LOADSCREEN_BEGIN',2)[1] -split '-- GTAS_MP_V089_REROLL_WONDER_LOADSCREEN_END',2)[0].Contains('InitMap()'))),
        @('wonder runtime begin', (Test-LEKContains $startGame '-- GTAS_MP_V089_WONDER_RUNTIME_BEGIN')),
        @('wonder runtime end', (Test-LEKContains $startGame '-- GTAS_MP_V089_WONDER_RUNTIME_END')),
        @('wrapped PlaceWonders', (Test-LEKContains $startGame 'GTAS_MP_V089_WrappedPlaceWonders')),
        @('wrapped DisableOtherWonders', (Test-LEKContains $startGame 'GTAS_MP_V089_WrappedDisableOtherWonders')),
        @('late duplicate skip guard', (Test-LEKContains $startGame 'GTAS_MP_V089_WONDERS_DONE_SEED')),
        @('graphics heartbeat diagnostics', (Test-LEKContains $loadScreen 'WonderGraphicsHeartbeat'))
    )){
        if($c[1]){ W ('PASS  '+$c[0]) Green } else { W ('FAIL  '+$c[0]) Red; $good=$false }
    }

    if(Test-LEKPath $inGame){
        $t=[IO.File]::ReadAllText($inGame)
        if(-not $t.Contains('-- GTAS_MP_V089_EARLY_WONDER_GRAPHICS_BEGIN')){
            W 'PASS  superseded InGame v0.8.9 experiment absent' Green
        } else { W 'FAIL  stale InGame v0.8.9 experiment remains' Red; $good=$false }
    }

    if(Test-LEKPath $loadScreen){
        $t=[IO.File]::ReadAllText($loadScreen)
        $n1=[regex]::Matches($t,[regex]::Escape('-- GTAS_MP_V089_REROLL_WONDER_LOADSCREEN_BEGIN')).Count
        $n2=[regex]::Matches($t,[regex]::Escape('-- GTAS_MP_V089_REROLL_WONDER_LOADSCREEN_END')).Count
        if($n1 -eq 1 -and $n2 -eq 1){ W 'PASS  exactly one LoadScreen wonder block' Green }
        else{ W ('FAIL  LoadScreen wonder block count begin='+$n1+' end='+$n2) Red; $good=$false }
    }

    if(Test-LEKPath $startGame){
        $t=[IO.File]::ReadAllText($startGame)
        $n1=[regex]::Matches($t,[regex]::Escape('-- GTAS_MP_V089_WONDER_RUNTIME_BEGIN')).Count
        $n2=[regex]::Matches($t,[regex]::Escape('-- GTAS_MP_V089_WONDER_RUNTIME_END')).Count
        if($n1 -eq 1 -and $n2 -eq 1){ W 'PASS  exactly one GTAS_StartGame wonder guard block' Green }
        else{ W ('FAIL  GTAS_StartGame wonder block count begin='+$n1+' end='+$n2) Red; $good=$false }

        if($t.Contains('InitMap();') -and $t.Contains('function GTAS_MP_ApplyMapPhase()')){
            W 'PASS  original guarded full map phase retained' Green
        } else { W 'FAIL  original RAS map phase appears damaged' Red; $good=$false }
    }

    W ''
    if($good){ W 'RAS v0.8.9 WONDER GRAPHICS HOTFIX VERIFIED.' Green; exit 0 }
    W 'VERIFY FOUND A PROBLEM.' Red; exit 1
} catch {
    W ('RAS WONDER VERIFY ERROR: '+$_.Exception.Message) Red
    if($_.InvocationInfo -and $_.InvocationInfo.PositionMessage){ W $_.InvocationInfo.PositionMessage DarkGray }
    if($_.ScriptStackTrace){ W ('STACK: '+$_.ScriptStackTrace) DarkGray }
    exit 1
}
