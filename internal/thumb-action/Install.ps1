param([string]$CivPath='')
$ErrorActionPreference='Stop'
$Root=Split-Path $PSScriptRoot -Parent
. (Join-Path $Root 'LekTools.ps1')
function W([string]$s,[ConsoleColor]$c=[ConsoleColor]::Gray){ Write-Host $s -ForegroundColor $c }
$OldBegin='-- LEK_EXT_THUMB_NEXT_ACTION_V01_BEGIN'
$OldEnd='-- LEK_EXT_THUMB_NEXT_ACTION_V01_END'
$V02Begin='-- LEK_EXT_SPACE_NEXT_ACTION_V02_BEGIN'
$V02End='-- LEK_EXT_SPACE_NEXT_ACTION_V02_END'
$Begin='-- LEK_EXT_SPACE_NEXT_ACTION_V03_BEGIN'
$End='-- LEK_EXT_SPACE_NEXT_ACTION_V03_END'
$TradeBegin='-- LEK_EXT_SPACE_ACCEPT_TRADE_V03_BEGIN'
$TradeEnd='-- LEK_EXT_SPACE_ACCEPT_TRADE_V03_END'

try {
    if(Test-LEKCivRunning){ throw 'Civilization V appears to be running. Close it before installing.' }
    $civ=Find-LEKCivV $CivPath
    if(!$civ){ throw 'Civilization V install folder not found.' }
    $target=Join-LEKPath $civ 'Assets\DLC\Expansion2\UI\InGame\WorldView\ActionInfoPanel.lua'
    if(!(Test-LEKPath $target)){ throw 'Brave New World ActionInfoPanel.lua was not found.' }
    $text=[IO.File]::ReadAllText($target)
    if(!$text.Contains('function OnEndTurnClicked()') -or !$text.Contains('Controls.EndTurnButton:RegisterCallback( Mouse.eLClick, OnEndTurnClicked );')){
        throw 'The installed ActionInfoPanel does not contain the expected native End Turn handler.'
    }
    $backupRoot=Join-Path (Split-Path $Root -Parent) 'local\backups\thumb-action'
    Backup-LEKFileOnce $target $backupRoot 'ActionInfoPanel.lua' | Out-Null
    $text=Remove-LEKMarkedBlock $text $OldBegin $OldEnd
    $text=Remove-LEKMarkedBlock $text $V02Begin $V02End
    Write-LEKUtf8NoBom $target $text
    $body=@'
local LEKSpaceNextActionHeld = false
local LEKSpaceTrackedTurn = -1
local LEKSpaceTrackedPlayer = -1
local LEKSpaceTrackedUnit = -1

local function LEKSpaceClearTrackedUnit()
    LEKSpaceTrackedTurn = -1
    LEKSpaceTrackedPlayer = -1
    LEKSpaceTrackedUnit = -1
end

local function LEKSpaceIsUnitBlocker(blockingType)
    return blockingType == EndTurnBlockingTypes.ENDTURN_BLOCKING_STACKED_UNITS
        or blockingType == EndTurnBlockingTypes.ENDTURN_BLOCKING_UNIT_NEEDS_ORDERS
        or blockingType == EndTurnBlockingTypes.ENDTURN_BLOCKING_UNITS
end

local function LEKSpaceActivateOrSkip()
    local playerID = Game.GetActivePlayer()
    local player = Players[playerID]
    local turn = Game.GetGameTurn()
    local unit = UI.GetHeadSelectedUnit()
    if player and unit
        and LEKSpaceTrackedTurn == turn
        and LEKSpaceTrackedPlayer == playerID
        and LEKSpaceTrackedUnit == unit:GetID() then
        LEKSpaceClearTrackedUnit()
        Game.SelectionListGameNetMessage(GameMessageTypes.GAMEMESSAGE_PUSH_MISSION, GameInfoTypes.MISSION_SKIP, unit:GetID(), 0, 0, false)
        return
    end

    LEKSpaceClearTrackedUnit()
    local blockingType = player and player:GetEndTurnBlockingType()
    OnEndTurnClicked()
    if player and LEKSpaceIsUnitBlocker(blockingType) then
        unit = UI.GetHeadSelectedUnit()
        if unit then
            LEKSpaceTrackedTurn = turn
            LEKSpaceTrackedPlayer = playerID
            LEKSpaceTrackedUnit = unit:GetID()
        end
    end
end

local function LEKSpaceNextActionInput(uiMsg, wParam)
    if wParam == Keys.VK_SPACE then
        if uiMsg == KeyEvents.KeyDown then
            if not LEKSpaceNextActionHeld then
                LEKSpaceNextActionHeld = true
                LEKSpaceActivateOrSkip()
            end
            return true
        elseif uiMsg == KeyEvents.KeyUp then
            LEKSpaceNextActionHeld = false
            return true
        end
    end
    return false
end
ContextPtr:SetInputHandler(LEKSpaceNextActionInput)
'@
    Set-LEKMarkedBlock $target $Begin $End $body.Trim()
    $tradeTarget=Join-LEKPath $civ 'Assets\DLC\UI_bc1\LeaderHead\TradeLogic.lua'
    if(!(Test-LEKPath $tradeTarget)){ throw 'Installed EUI TradeLogic.lua owner was not found.' }
    $tradeText=[IO.File]::ReadAllText($tradeTarget)
    if(!$tradeText.Contains('function InputHandler( uiMsg, wParam, lParam )') -or !$tradeText.Contains('Controls.ProposeButton:RegisterCallback')){
        throw 'Installed EUI TradeLogic.lua does not contain the expected input and offer handlers.'
    }
    Backup-LEKFileOnce $tradeTarget $backupRoot 'TradeLogic.lua' | Out-Null
    $tradeBody=@'
local function LEKSpaceAcceptIncomingOffer()
    if g_PVPTrade
        or not g_bAIMakingOffer
        or g_diploUIStateID ~= DiploUIStateTypes.DIPLO_UI_STATE_TRADE_AI_MAKES_OFFER
        or Controls.ProposeButton:IsHidden()
        or Controls.ProposeButton:IsDisabled()
        or not g_Deal
        or g_Deal:GetNumItems() == 0 then
        return false
    end
    g_Deal:SetFromPlayer(g_iUs)
    g_Deal:SetToPlayer(g_iThem)
    UI.DoProposeDeal()
    g_bMessageFromDiploAI = false
    DoDemandState(false)
    UIManager:DequeuePopup(ContextPtr)
    return true
end

local LEKSpaceOriginalTradeInput = InputHandler
function InputHandler(uiMsg, wParam, lParam)
    if uiMsg == KeyEvents.KeyDown and wParam == Keys.VK_SPACE then
        if LEKSpaceAcceptIncomingOffer() then return true end
    end
    return LEKSpaceOriginalTradeInput(uiMsg, wParam, lParam)
end
'@
    Set-LEKMarkedBlock $tradeTarget $TradeBegin $TradeEnd $tradeBody.Trim()
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Verify.ps1') -CivPath $civ
    if($LASTEXITCODE -ne 0){ throw 'Space Next Action was written, but verification failed.' }
    W 'SPACE NEXT ACTION v0.3 INSTALLED.' Green
    exit 0
} catch { W ('ERROR: '+$_.Exception.Message) Red; exit 1 }
