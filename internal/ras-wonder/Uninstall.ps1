param([string]$CivPath='')
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'LekTools.ps1')
function W([string]$s,[ConsoleColor]$c=[ConsoleColor]::Gray){ Write-Host $s -ForegroundColor $c }

try {
    W '============================================================' Cyan
    W ' RAS MP BRIDGE v0.8.9 - WONDER GRAPHICS UNINSTALL' Cyan
    W '============================================================' Cyan
    if(Test-LEKCivRunning){ throw 'Civilization V appears to be running. Close it before uninstalling.' }
    $civ=Find-LEKCivV $CivPath
    if(!$civ){ $m=Read-Host 'Paste Civilization V install folder'; if($m){$civ=Find-LEKCivV $m} }
    if(!$civ){ throw 'Civilization V was not found.' }

    $inGame=Join-LEKPath $civ 'Assets\DLC\LEKMOD_V30.7\UI\InGame.lua'
    $loadScreen=Join-LEKPath $civ 'Assets\DLC\UI_bc1\GameSetup\LoadScreen.lua'
    $startGame=Join-LEKPath $civ 'Assets\UI\FrontEnd\Multiplayer\GTAS_StartGame.lua'

    if(Test-LEKPath $loadScreen){
        $t=[IO.File]::ReadAllText($loadScreen)
        $t=Remove-LEKMarkedBlock $t '-- GTAS_MP_V089_REROLL_WONDER_LOADSCREEN_BEGIN' '-- GTAS_MP_V089_REROLL_WONDER_LOADSCREEN_END'
        Write-LEKUtf8NoBom $loadScreen $t
        W 'REMOVED  LoadScreen reroll wonder pre-render block' Green
    }
    if(Test-LEKPath $startGame){
        $t=[IO.File]::ReadAllText($startGame)
        $t=Remove-LEKMarkedBlock $t '-- GTAS_MP_V089_WONDER_RUNTIME_BEGIN' '-- GTAS_MP_V089_WONDER_RUNTIME_END'
        Write-LEKUtf8NoBom $startGame $t
        W 'REMOVED  GTAS_StartGame late replay guard block' Green
    }
    if(Test-LEKPath $inGame){
        $t=[IO.File]::ReadAllText($inGame)
        $before=$t
        $t=Remove-LEKMarkedBlock $t '-- GTAS_MP_V089_EARLY_WONDER_GRAPHICS_BEGIN' '-- GTAS_MP_V089_EARLY_WONDER_GRAPHICS_END'
        if($t -ne $before){
            Write-LEKUtf8NoBom $inGame $t
            W 'REMOVED  stale experimental InGame v0.8.9 block' Green
        }
    }

    W ''
    W 'RAS v0.8.9 wonder hotfix removed. Frozen RAS v0.8.8 remains installed.' Green
    W 'Restart Civilization V before testing after uninstall.' Yellow
    exit 0
} catch {
    W ('RAS WONDER UNINSTALL ERROR: '+$_.Exception.Message) Red
    if($_.InvocationInfo -and $_.InvocationInfo.PositionMessage){ W $_.InvocationInfo.PositionMessage DarkGray }
    if($_.ScriptStackTrace){ W ('STACK: '+$_.ScriptStackTrace) DarkGray }
    exit 1
}
