param([string]$CivPath='')
$ErrorActionPreference='Stop'
$Root=Split-Path $PSScriptRoot -Parent
. (Join-Path $Root 'LekTools.ps1')
function W([string]$s,[ConsoleColor]$c=[ConsoleColor]::Gray){ Write-Host $s -ForegroundColor $c }
try {
    $civ=Find-LEKCivV $CivPath
    if(!$civ){ throw 'Civilization V install folder not found.' }
    $target=Join-LEKPath $civ 'Assets\DLC\Expansion2\UI\InGame\WorldView\ActionInfoPanel.lua'
    if(!(Test-LEKPath $target)){ throw 'Brave New World ActionInfoPanel.lua was not found.' }
    $t=[IO.File]::ReadAllText($target)
    $checks=[ordered]@{
        'exactly one Space v0.2 bridge'=([regex]::Matches($t,'LEK_EXT_SPACE_NEXT_ACTION_V02_BEGIN').Count -eq 1 -and [regex]::Matches($t,'LEK_EXT_SPACE_NEXT_ACTION_V02_END').Count -eq 1)
        'old thumb bridge removed'=(-not $t.Contains('LEK_EXT_THUMB_NEXT_ACTION_V01_BEGIN'))
        'uses proven Space key constant'= $t.Contains('wParam == Keys.VK_SPACE')
        'handles Space key down and up'=($t.Contains('uiMsg == KeyEvents.KeyDown') -and $t.Contains('uiMsg == KeyEvents.KeyUp'))
        'held Space is debounced'=($t.Contains('LEKSpaceNextActionHeld') -and $t.Contains('if not LEKSpaceNextActionHeld then'))
        'calls the existing End Turn click handler'= $t.Contains('OnEndTurnClicked()')
        'consumes handled Space input'= $t.Contains('return true')
        'leaves other input unhandled'= $t.Contains('return false')
    }
    $good=$true
    foreach($c in $checks.GetEnumerator()){ if($c.Value){W ('PASS  '+$c.Key) Green}else{W ('FAIL  '+$c.Key) Red;$good=$false} }
    if(!$good){ exit 1 }
    W 'SPACE NEXT ACTION v0.2 VERIFIED.' Green
    exit 0
} catch { W ('ERROR: '+$_.Exception.Message) Red; exit 1 }
