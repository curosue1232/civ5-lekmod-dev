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
        Write-LEKUtf8NoBom $target $t
    }
    W 'THUMB NEXT ACTION REMOVED.' Green
    exit 0
} catch { W ('ERROR: '+$_.Exception.Message) Red; exit 1 }
