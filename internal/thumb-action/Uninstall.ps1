param([string]$CivPath='')
$ErrorActionPreference='Stop'
$Root=Split-Path $PSScriptRoot -Parent
. (Join-Path $Root 'LekTools.ps1')
function W([string]$s,[ConsoleColor]$c=[ConsoleColor]::Gray){ Write-Host $s -ForegroundColor $c }
try {
    if(Test-LEKCivRunning){ throw 'Civilization V appears to be running. Close it before uninstalling.' }
    $civ=Find-LEKCivV $CivPath
    if(!$civ){ throw 'Civilization V install folder not found.' }
    $target=Join-LEKPath $civ 'Assets\DLC\Expansion2\UI\InGame\WorldView\ActionInfoPanel.lua'
    if(Test-LEKPath $target){
        $t=[IO.File]::ReadAllText($target)
        $t=Remove-LEKMarkedBlock $t '-- LEK_EXT_THUMB_NEXT_ACTION_V01_BEGIN' '-- LEK_EXT_THUMB_NEXT_ACTION_V01_END'
        $t=Remove-LEKMarkedBlock $t '-- LEK_EXT_SPACE_NEXT_ACTION_V02_BEGIN' '-- LEK_EXT_SPACE_NEXT_ACTION_V02_END'
        $t=Remove-LEKMarkedBlock $t '-- LEK_EXT_SPACE_NEXT_ACTION_V03_BEGIN' '-- LEK_EXT_SPACE_NEXT_ACTION_V03_END'
        Write-LEKUtf8NoBom $target $t
    }
    $tradeTarget=Join-LEKPath $civ 'Assets\DLC\UI_bc1\LeaderHead\TradeLogic.lua'
    if(Test-LEKPath $tradeTarget){
        $t=[IO.File]::ReadAllText($tradeTarget)
        $t=Remove-LEKMarkedBlock $t '-- LEK_EXT_SPACE_ACCEPT_TRADE_V03_BEGIN' '-- LEK_EXT_SPACE_ACCEPT_TRADE_V03_END'
        Write-LEKUtf8NoBom $tradeTarget $t
    }
    W 'SPACE/THUMB NEXT ACTION REMOVED.' Green
    exit 0
} catch { W ('ERROR: '+$_.Exception.Message) Red; exit 1 }
