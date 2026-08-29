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
    $tradeTarget=Join-LEKPath $civ 'Assets\DLC\UI_bc1\LeaderHead\TradeLogic.lua'
    if(!(Test-LEKPath $tradeTarget)){ throw 'Installed EUI TradeLogic.lua owner was not found.' }
    $trade=[IO.File]::ReadAllText($tradeTarget)
    $checks=[ordered]@{
        'exactly one Space v0.3 bridge'=([regex]::Matches($t,'LEK_EXT_SPACE_NEXT_ACTION_V03_BEGIN').Count -eq 1 -and [regex]::Matches($t,'LEK_EXT_SPACE_NEXT_ACTION_V03_END').Count -eq 1)
        'old thumb bridge removed'=(-not $t.Contains('LEK_EXT_THUMB_NEXT_ACTION_V01_BEGIN'))
        'old Space v0.2 bridge removed'=(-not $t.Contains('LEK_EXT_SPACE_NEXT_ACTION_V02_BEGIN'))
        'uses proven Space key constant'= $t.Contains('wParam == Keys.VK_SPACE')
        'handles Space key down and up'=($t.Contains('uiMsg == KeyEvents.KeyDown') -and $t.Contains('uiMsg == KeyEvents.KeyUp'))
        'held Space is debounced'=($t.Contains('LEKSpaceNextActionHeld') -and $t.Contains('if not LEKSpaceNextActionHeld then'))
        'selected unit is scoped to player and turn'=($t.Contains('LEKSpaceTrackedTurn == turn') -and $t.Contains('LEKSpaceTrackedPlayer == playerID') -and $t.Contains('LEKSpaceTrackedUnit == unit:GetID()'))
        'second Space uses native skip mission'= $t.Contains('Game.SelectionListGameNetMessage(GameMessageTypes.GAMEMESSAGE_PUSH_MISSION, GameInfoTypes.MISSION_SKIP, unit:GetID(), 0, 0, false)')
        'skip uses native selection advancement'=($t.Contains('LEKSpaceClearTrackedUnit()') -and $t.Contains('LEKSpaceActivateOrSkip()'))
        'calls the existing End Turn click handler'= $t.Contains('OnEndTurnClicked()')
        'consumes handled Space input'= $t.Contains('return true')
        'leaves other input unhandled'= $t.Contains('return false')
        'exactly one EUI Space accept bridge'=([regex]::Matches($trade,'LEK_EXT_SPACE_ACCEPT_TRADE_V03_BEGIN').Count -eq 1 -and [regex]::Matches($trade,'LEK_EXT_SPACE_ACCEPT_TRADE_V03_END').Count -eq 1)
        'accept is limited to incoming AI offers'= $trade.Contains('g_diploUIStateID ~= DiploUIStateTypes.DIPLO_UI_STATE_TRADE_AI_MAKES_OFFER')
        'accept excludes PVP and non-offer sessions'=($trade.Contains('if g_PVPTrade') -and $trade.Contains('or not g_bAIMakingOffer'))
        'accept requires a visible enabled button'=($trade.Contains('Controls.ProposeButton:IsHidden()') -and $trade.Contains('Controls.ProposeButton:IsDisabled()'))
        'accept rejects empty deals'= $trade.Contains('g_Deal:GetNumItems() == 0')
        'accept uses native finalizer'= $trade.Contains('UI.DoProposeDeal()')
    }
    $good=$true
    foreach($c in $checks.GetEnumerator()){ if($c.Value){W ('PASS  '+$c.Key) Green}else{W ('FAIL  '+$c.Key) Red;$good=$false} }
    if(!$good){ exit 1 }
    W 'SPACE NEXT ACTION v0.3 VERIFIED.' Green
    exit 0
} catch { W ('ERROR: '+$_.Exception.Message) Red; exit 1 }
