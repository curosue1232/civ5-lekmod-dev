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
    $menuXmlPaths=@(
        (Join-LEKPath $civ 'Assets\UI\InGame\Menus\GameMenu.xml'),
        (Join-LEKPath $civ 'Assets\DLC\Expansion\UI\InGame\Menus\GameMenu.xml'),
        (Join-LEKPath $civ 'Assets\DLC\Expansion2\UI\InGame\Menus\GameMenu.xml')
    ) | Where-Object { Test-LEKPath $_ }
    if($menuXmlPaths.Count -eq 0){ throw 'No GameMenu.xml copy was found.' }
    $menuLuaPath=Join-LEKPath $civ 'Assets\UI\InGame\Menus\GameMenu.lua'
    if(!(Test-LEKPath $menuLuaPath)){ throw 'GameMenu.lua was not found.' }
    $menuLuaText=[IO.File]::ReadAllText($menuLuaPath)
    $inGamePaths=@(
        (Join-LEKPath $civ 'Assets\UI\InGame\InGame.lua'),
        (Join-LEKPath $civ 'Assets\DLC\Expansion\UI\InGame\InGame.lua'),
        (Join-LEKPath $civ 'Assets\DLC\Expansion2\UI\InGame\InGame.lua'),
        (Join-LEKPath $civ 'Assets\DLC\LEKMOD_V30.7\UI\InGame.lua')
    ) | Where-Object { Test-LEKPath $_ }
    $checks=[ordered]@{
        'exactly one Space v0.7 bridge'=([regex]::Matches($t,'LEK_EXT_SPACE_NEXT_ACTION_V07_BEGIN').Count -eq 1 -and [regex]::Matches($t,'LEK_EXT_SPACE_NEXT_ACTION_V07_END').Count -eq 1)
        'old thumb bridge removed'=(-not $t.Contains('LEK_EXT_THUMB_NEXT_ACTION_V01_BEGIN'))
        'old Space v0.2 bridge removed'=(-not $t.Contains('LEK_EXT_SPACE_NEXT_ACTION_V02_BEGIN'))
        'old Space v0.3 bridge removed'=(-not $t.Contains('LEK_EXT_SPACE_NEXT_ACTION_V03_BEGIN'))
        'old Space v0.4 bridge removed'=(-not $t.Contains('LEK_EXT_SPACE_NEXT_ACTION_V04_BEGIN'))
        'old Space v0.5 bridge removed'=(-not $t.Contains('LEK_EXT_SPACE_NEXT_ACTION_V05_BEGIN'))
        'old Space v0.6 bridge removed'=(-not $t.Contains('LEK_EXT_SPACE_NEXT_ACTION_V06_BEGIN'))
        'uses proven Space key constant'= $t.Contains('wParam == Keys.VK_SPACE')
        'handles Space key down and up'=($t.Contains('uiMsg == KeyEvents.KeyDown') -and $t.Contains('uiMsg == KeyEvents.KeyUp'))
        'held Space is debounced'=($t.Contains('LEKSpaceNextActionHeld') -and $t.Contains('if not LEKSpaceNextActionHeld then'))
        'selected unit retry requires unchanged player turn position and moves'=($t.Contains('LEKSpaceTrackedTurn == turn') -and $t.Contains('LEKSpaceTrackedPlayer == playerID') -and $t.Contains('LEKSpaceTrackedUnit == unit:GetID()') -and $t.Contains('LEKSpaceTrackedX == x') -and $t.Contains('LEKSpaceTrackedY == y') -and $t.Contains('LEKSpaceTrackedMoves == moves'))
        'second Space uses native skip mission'= $t.Contains('Game.SelectionListGameNetMessage(GameMessageTypes.GAMEMESSAGE_PUSH_MISSION, GameInfoTypes.MISSION_SKIP, unit:GetID(), 0, 0, false)')
        'skip uses native selection advancement'=($t.Contains('LEKSpaceClearTrackedUnit()') -and $t.Contains('LEKSpaceActivateOrSkip()'))
        'calls the existing End Turn click handler'= $t.Contains('OnEndTurnClicked()')
        'consumes handled Space input'= $t.Contains('return true')
        'leaves other input unhandled'= $t.Contains('return false')
        'unit autopilot is pcall-wrapped against unknown API surface'=($t.Contains('local function LEKSpaceAutoActUnit(unit, isStackedBlocker)') -and $t.Contains('pcall(LEKSpaceAutoActUnitInner, unit, isStackedBlocker)'))
        'workers automate build'= $t.Contains('GameInfoTypes.AUTOMATE_BUILD')
        'scouts, retained explorer upgrades, and unarmed ships automate explore'=($t.Contains('GameInfoTypes.AUTOMATE_EXPLORE') -and $t.Contains('DomainTypes.DOMAIN_SEA') -and $t.Contains('unit:GetUnitAIType()') -and $t.Contains('GameInfo.UnitAIInfos.UNITAI_EXPLORE') -and $t.Contains('AUTOMATE_EXPLORE_RETAINED_ROLE'))
        'settlers use the native settle-recommendation event'=($t.Contains('Events.GenericWorldAnchor.Add(LEKSpaceOnWorldAnchor)') -and $t.Contains('GenericWorldAnchorTypes.WORLD_ANCHOR_SETTLER'))
        'settler settles immediately when legal, else moves to nearest recommendation'=($t.Contains('owner:CanFound') -and $t.Contains('GameInfoTypes.MISSION_FOUND') -and $t.Contains('Map.PlotDistance(x,y,p:GetX(),p:GetY())'))
        'stacked-unit blocker moves off the stack instead of fortifying'=($t.Contains('isStackedBlocker') -and $t.Contains('Map.PlotDirection(x,y,direction)') -and $t.Contains('LEKSpaceMoveSelectedUnit(p,"UNSTACK_MOVE")'))
        'unit promotion uses the native generic action mechanism'=($t.Contains('unit:CanPromote()') -and $t.Contains('ActionSubTypes.ACTIONSUBTYPE_PROMOTION') -and $t.Contains('Game.CanHandleAction(actionID, plot, false)') -and $t.Contains('Game.HandleAction(actionID)'))
        'promotion-ready units are treated as a unit blocker'= $t.Contains('EndTurnBlockingTypes.ENDTURN_BLOCKING_UNIT_PROMOTION')
        'combat units prefer war enemies over barbarians over guarding the border'=($t.Contains('LEKSpaceIsAtWarWithAnyMajor') -and $t.Contains('LEKSpaceNearestEnemyUnit(unit,false,true)') -and $t.Contains('LEKSpaceNearestEnemyUnit(unit,true,false)') -and $t.Contains('GameInfoTypes.IMPROVEMENT_BARBARIAN_CAMP') -and $t.Contains('LEKSpaceIsFrontierPlot'))
        'frontier guards use reachable passable domain-correct unoccupied plots'=($t.Contains('local function LEKSpaceIsGuardTraversable(p,unit)') -and $t.Contains('domain~=DomainTypes.DOMAIN_LAND and domain~=DomainTypes.DOMAIN_SEA') -and $t.Contains('p:IsValidDomainForLocation(unit)') -and $t.Contains('p:IsImpassable()') -and $t.Contains('LEKSpacePlotHasOtherCombatUnit') -and $t.Contains('p:GetUnit(i)') -and $t.Contains('local function LEKSpaceNearestReachableFrontier(unit,radius)') -and $t.IndexOf('local function LEKSpacePlotHasOtherCombatUnit(p,unit)') -lt $t.IndexOf('local function LEKSpaceNearestReachableFrontier(unit,radius)') -and $t.Contains('local queue={{plot=start,dist=0}}') -and $t.Contains('LEKSpaceNearestReachableFrontier(unit,30)'))
        'idle combat units alert then reconsider their guard position after ten turns'=($t.Contains('GameInfoTypes.MISSION_ALERT') -and $t.Contains('LEKSpaceGuardReviewTurns[unit:GetID()]=Game.GetGameTurn()+10') -and $t.Contains('guard:GetActivityType()==ActivityTypes.ACTIVITY_SENTRY') -and $t.Contains('LEKSpaceGuardReviewTurns[id]=turn+10') -and $t.Contains('LEKSpaceReviewDueGuard(player,turn)') -and $t.Contains('blockingType==EndTurnBlockingTypes.NO_ENDTURN_BLOCKING_TYPE'))
        'city range attack uses the native selected-city and legality check'=($t.Contains('UI.GetHeadSelectedCity()') -and $t.Contains('city:CanRangeStrikeAt(p:GetX(),p:GetY(),true,true)') -and $t.Contains('TaskTypes.TASK_RANGED_ATTACK'))
        'city range attack is dispatched as its own branch, not folded into the unit blocker'= $t.Contains('elseif player and blockingType == EndTurnBlockingTypes.ENDTURN_BLOCKING_CITY_RANGE_ATTACK')
        'city range attack is pcall-wrapped against unknown API surface'= $t.Contains('pcall(LEKSpaceCityRangeAttackInner, city)')
        'trade units establish a route via the native destination list and mission'=($t.Contains('GetPotentialInternationalTradeRouteDestinations(unit)') -and $t.Contains('GameInfoTypes.MISSION_ESTABLISH_TRADE_ROUTE') -and $t.Contains('UNITAI_TRADE_UNIT'))
        'trade route picks highest Gold yield deterministically'= $t.Contains('YieldTypes.YIELD_GOLD+1')
        'selected-unit movement uses native WorldView path instead of raw move missions'=($t.Contains('local function LEKSpaceMoveSelectedUnit(plot,result)') -and $t.Contains('Game.SelectionListMove(plot,false,false,false)') -and $t.Contains('LEKSpaceMoveSelectedUnit(borderPlot,"MOVE_TO_BORDER_GUARD")'))
        'automate flag is shared via UserData, not a local-only variable'=($t.Contains('Modding.OpenUserData("LEK_SPACE_AUTOMATE",1)') -and $t.Contains('LEKAutomateIsActive') -and $t.Contains('LEKAutomateSetActive'))
        'ActionInfoPanel listens only to unconsumed world ticks'=($t.Contains('LuaEvents.LEKSpaceAutomateWorldTick.Add(function()') -and $t.Contains('LEKSpaceActivateOrSkip()') -and !$t.Contains('LEKSpaceModalPaused') -and !$t.Contains('if not ContextPtr:IsHidden() then LEKSpaceActivateOrSkip() end'))
        'ActionInfoPanel no longer owns the fragile hidden-screen timer'=(-not $t.Contains('ContextPtr:SetUpdate(function(dt)'))
        'automate stops on any keypress, not just Escape'= $t.Contains('if uiMsg == KeyEvents.KeyDown and LEKAutomateIsActive() then')
        'prophet found/enhance religion via legality-checked native actions'=($t.Contains('LEKSpaceFindMissionAction("MISSION_FOUND_RELIGION", plot)') -and $t.Contains('LEKSpaceFindMissionAction("MISSION_ENHANCE_RELIGION", plot)') -and $t.Contains('Game.CanHandleAction(actionID, plot, false)'))
        'further prophets spread religion to cities lacking its majority'=($t.Contains('LEKSpaceFindMissionAction("MISSION_SPREAD_RELIGION", plot)') -and $t.Contains('city:GetReligiousMajority() ~= religionID') -and $t.Contains('unit:GetReligion()'))
        'stuck-unit fallback tracks regardless of dispatcher result'=(!$t.Contains('if not LEKSpaceAutoActUnit(unit, isStackedBlocker) then') -and $t.Contains('LEKSpaceAutoActUnit(unit, isStackedBlocker)'))
        'stranded explorer or dry work boat gets deleted, everything else gets skipped'=($t.Contains('action.Type == "COMMAND_DELETE"') -and $t.Contains('DELETED_STRANDED_UNIT') -and $t.Contains('Game.HandleAction(deleteAction)'))
        'work boats build improvements, not explore'=($t.Contains('unitClass == "UNITCLASS_WORKER" or unitClass == "UNITCLASS_WORKBOAT" or (info and info.DefaultUnitAI == "UNITAI_WORKER_SEA")') -and $t.Contains('unitClass == "UNITCLASS_SCOUT"'))
        'exactly one EUI Space accept bridge'=([regex]::Matches($trade,'LEK_EXT_SPACE_ACCEPT_TRADE_V03_BEGIN').Count -eq 1 -and [regex]::Matches($trade,'LEK_EXT_SPACE_ACCEPT_TRADE_V03_END').Count -eq 1)
        'accept is limited to incoming AI offers'= $trade.Contains('g_diploUIStateID ~= DiploUIStateTypes.DIPLO_UI_STATE_TRADE_AI_MAKES_OFFER')
        'accept excludes PVP and non-offer sessions'=($trade.Contains('if g_PVPTrade') -and $trade.Contains('or not g_bAIMakingOffer'))
        'accept requires a visible enabled button'=($trade.Contains('Controls.ProposeButton:IsHidden()') -and $trade.Contains('Controls.ProposeButton:IsDisabled()'))
        'accept rejects empty deals'= $trade.Contains('g_Deal:GetNumItems() == 0')
        'accept uses native finalizer'= $trade.Contains('UI.DoProposeDeal()')
        'accept is wired into the Automate tick, not just the manual keypress'=($trade.Contains('LuaEvents.LEKSpaceAutomateTick.Add(function()') -and $trade.Contains('pcall(LEKSpaceAcceptIncomingOffer)'))
        'exactly one Automate menu logic block in GameMenu.lua'=([regex]::Matches($menuLuaText,'LEK_EXT_SPACE_AUTOMATE_MENU_V01_BEGIN').Count -eq 1 -and [regex]::Matches($menuLuaText,'LEK_EXT_SPACE_AUTOMATE_MENU_V01_END').Count -eq 1)
        'Automate menu logic shares the same UserData store as ActionInfoPanel'= $menuLuaText.Contains('Modding.OpenUserData("LEK_SPACE_AUTOMATE",1)')
        'Automate button click toggles state and returns to game when turning on'=($menuLuaText.Contains('Controls.LekAutomateButton:RegisterCallback(Mouse.eLClick, LEKAutomateClick)') -and $menuLuaText.Contains('OnReturn()'))
        'Automate menu logic chains the existing OnShowHide instead of replacing it'=($menuLuaText.Contains('local oldShow = OnShowHide') -and $menuLuaText.Contains('if oldShow then oldShow(hide, init) end'))
    }
    $good=$true
    foreach($c in $checks.GetEnumerator()){ if($c.Value){W ('PASS  '+$c.Key) Green}else{W ('FAIL  '+$c.Key) Red;$good=$false} }
    foreach($menuXmlPath in $menuXmlPaths){
        $menuXmlText=[IO.File]::ReadAllText($menuXmlPath)
        $xmlChecks=[ordered]@{
            ("exactly one Automate button block in "+$menuXmlPath)=([regex]::Matches($menuXmlText,[regex]::Escape('LEK_EXT_SPACE_AUTOMATE_BUTTON_V01_BEGIN')).Count -eq 1 -and [regex]::Matches($menuXmlText,[regex]::Escape('LEK_EXT_SPACE_AUTOMATE_BUTTON_V01_END')).Count -eq 1)
            ("Automate button placed after RetireButton, inside MainStack in "+$menuXmlPath)=($menuXmlText.IndexOf('ID="RetireButton"') -lt $menuXmlText.IndexOf('LEK_EXT_SPACE_AUTOMATE_BUTTON_V01_BEGIN') -and $menuXmlText.IndexOf('LEK_EXT_SPACE_AUTOMATE_BUTTON_V01_END') -lt $menuXmlText.IndexOf('MainMenuButton'))
            ("Automate button XML defines the LekAutomateButton control in "+$menuXmlPath)= $menuXmlText.Contains('ID="LekAutomateButton"')
        }
        foreach($c in $xmlChecks.GetEnumerator()){ if($c.Value){W ('PASS  '+$c.Key) Green}else{W ('FAIL  '+$c.Key) Red;$good=$false} }
    }
    foreach($inGamePath in $inGamePaths){
        $inGameText=[IO.File]::ReadAllText($inGamePath)
        $driverChecks=[ordered]@{
            ("exactly one persistent Automate driver in "+$inGamePath)=([regex]::Matches($inGameText,'LEK_EXT_SPACE_AUTOMATE_DRIVER_V02_BEGIN').Count -eq 1 -and [regex]::Matches($inGameText,'LEK_EXT_SPACE_AUTOMATE_DRIVER_V02_END').Count -eq 1)
            ("Automate driver chains native OnUpdate in "+$inGamePath)=($inGameText.Contains('local LEKSpaceOriginalInGameUpdate=OnUpdate') -and $inGameText.Contains('LEKSpaceOriginalInGameUpdate(dt)'))
            ("Automate driver uses fast two-phase ticks in "+$inGamePath)=($inGameText.Contains('LEKSpaceDriverTimer>=0.7') -and $inGameText.Contains('tonumber(seconds) or 1.7') -and $inGameText.Contains('LEKSpaceDriverModalHandledThisTick=false') -and $inGameText.Contains('LuaEvents.LEKSpaceAutomateTick()') -and $inGameText.Contains('LuaEvents.LEKSpaceAutomateWorldTick()'))
            ("driver is installed before native SetUpdate registration in "+$inGamePath)=($inGameText.IndexOf('LEK_EXT_SPACE_AUTOMATE_DRIVER_V02_BEGIN') -lt $inGameText.IndexOf('ContextPtr:SetUpdate( OnUpdate );'))
        }
        foreach($c in $driverChecks.GetEnumerator()){ if($c.Value){W ('PASS  '+$c.Key) Green}else{W ('FAIL  '+$c.Key) Red;$good=$false} }
    }
    $confirmPaths=@(
        (Join-LEKPath $civ 'Assets\DLC\UI_bc1\Improvements\ConfirmCommandPopup.lua'),
        (Join-LEKPath $civ 'Assets\UI\InGame\PopupsGeneric\ConfirmCommandPopup.lua')
    ) | Where-Object { Test-LEKPath $_ }
    if($confirmPaths.Count -eq 0){ throw 'No ConfirmCommandPopup.lua copy was found.' }
    foreach($confirmPath in $confirmPaths){
        $confirmText=[IO.File]::ReadAllText($confirmPath)
        $confirmChecks=[ordered]@{
            ("exactly one ConfirmCommand bridge in "+$confirmPath)=([regex]::Matches($confirmText,'LEK_EXT_SPACE_CONFIRM_COMMAND_V01_BEGIN').Count -eq 1 -and [regex]::Matches($confirmText,'LEK_EXT_SPACE_CONFIRM_COMMAND_V01_END').Count -eq 1)
            ("ConfirmCommand handles Space key in "+$confirmPath)=($confirmText.Contains('wParam == Keys.VK_SPACE') -and $confirmText.Contains('LEKSpaceExecuteConfirmCommand'))
            ("ConfirmCommand wired to Automate tick in "+$confirmPath)=($confirmText.Contains('LuaEvents.LEKSpaceAutomateTick.Add') -and $confirmText.Contains('LuaEvents.LEKSpaceAutomateModalHandled(1.7)') -and $confirmText.Contains('pcall(LEKSpaceExecuteConfirmCommand)'))
            ("ConfirmCommand executes native DoCommand in "+$confirmPath)= $confirmText.Contains('Game.SelectionListGameNetMessage( GameMessageTypes.GAMEMESSAGE_DO_COMMAND')
        }
        foreach($c in $confirmChecks.GetEnumerator()){ if($c.Value){W ('PASS  '+$c.Key) Green}else{W ('FAIL  '+$c.Key) Red;$good=$false} }
    }
    if(!$good){ exit 1 }
    W 'SPACE NEXT ACTION v0.7 VERIFIED.' Green
    exit 0
} catch { W ('ERROR: '+$_.Exception.Message) Red; exit 1 }
