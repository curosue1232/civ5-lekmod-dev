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
        'exactly one marked bridge'=([regex]::Matches($t,'LEK_EXT_THUMB_NEXT_ACTION_V01_BEGIN').Count -eq 1 -and [regex]::Matches($t,'LEK_EXT_THUMB_NEXT_ACTION_V01_END').Count -eq 1)
        'uses XButtonUp'= $t.Contains('uiMsg == MouseEvents.XButtonUp')
        'maps only thumb/back button 1'= $t.Contains('wParam == 1')
        'calls the existing End Turn click handler'= $t.Contains('OnEndTurnClicked()')
        'consumes handled thumb click'= $t.Contains('return true')
        'leaves other input unhandled'= $t.Contains('return false')
    }
    $good=$true
    foreach($c in $checks.GetEnumerator()){ if($c.Value){W ('PASS  '+$c.Key) Green}else{W ('FAIL  '+$c.Key) Red;$good=$false} }
    if(!$good){ exit 1 }
    W 'THUMB NEXT ACTION v0.1 VERIFIED.' Green
    exit 0
} catch { W ('ERROR: '+$_.Exception.Message) Red; exit 1 }
