param([string]$CivPath='')
$ErrorActionPreference='Stop'
$Root=Split-Path $PSScriptRoot -Parent
. (Join-Path $Root 'LekTools.ps1')
function W([string]$s,[ConsoleColor]$c=[ConsoleColor]::Gray){ Write-Host $s -ForegroundColor $c }
$OldBegin='-- LEK_EXT_THUMB_NEXT_ACTION_V01_BEGIN'
$OldEnd='-- LEK_EXT_THUMB_NEXT_ACTION_V01_END'
$V02Begin='-- LEK_EXT_SPACE_NEXT_ACTION_V02_BEGIN'
$V02End='-- LEK_EXT_SPACE_NEXT_ACTION_V02_END'
$V03Begin='-- LEK_EXT_SPACE_NEXT_ACTION_V03_BEGIN'
$V03End='-- LEK_EXT_SPACE_NEXT_ACTION_V03_END'
$V04Begin='-- LEK_EXT_SPACE_NEXT_ACTION_V04_BEGIN'
$V04End='-- LEK_EXT_SPACE_NEXT_ACTION_V04_END'
$V05Begin='-- LEK_EXT_SPACE_NEXT_ACTION_V05_BEGIN'
$V05End='-- LEK_EXT_SPACE_NEXT_ACTION_V05_END'
$V06Begin='-- LEK_EXT_SPACE_NEXT_ACTION_V06_BEGIN'
$V06End='-- LEK_EXT_SPACE_NEXT_ACTION_V06_END'
$Begin='-- LEK_EXT_SPACE_NEXT_ACTION_V07_BEGIN'
$End='-- LEK_EXT_SPACE_NEXT_ACTION_V07_END'
$TradeBegin='-- LEK_EXT_SPACE_ACCEPT_TRADE_V03_BEGIN'
$TradeEnd='-- LEK_EXT_SPACE_ACCEPT_TRADE_V03_END'
$ConfirmBegin='-- LEK_EXT_SPACE_CONFIRM_COMMAND_V01_BEGIN'
$ConfirmEnd='-- LEK_EXT_SPACE_CONFIRM_COMMAND_V01_END'
$MenuButtonBegin='<!-- LEK_EXT_SPACE_AUTOMATE_BUTTON_V01_BEGIN -->'
$MenuButtonEnd='<!-- LEK_EXT_SPACE_AUTOMATE_BUTTON_V01_END -->'
$MenuLogicBegin='-- LEK_EXT_SPACE_AUTOMATE_MENU_V01_BEGIN'
$MenuLogicEnd='-- LEK_EXT_SPACE_AUTOMATE_MENU_V01_END'
$DriverBegin='-- LEK_EXT_SPACE_AUTOMATE_DRIVER_V02_BEGIN'
$DriverEnd='-- LEK_EXT_SPACE_AUTOMATE_DRIVER_V02_END'

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
    $text=Remove-LEKMarkedBlock $text $V03Begin $V03End
    $text=Remove-LEKMarkedBlock $text $V04Begin $V04End
    $text=Remove-LEKMarkedBlock $text $V05Begin $V05End
    $text=Remove-LEKMarkedBlock $text $V06Begin $V06End
    Write-LEKUtf8NoBom $target $text
    $body=@'
local LEKAutopilotDB=nil
pcall(function() LEKAutopilotDB=Modding.OpenUserData("LEK_SPACE_AUTOPILOT",1) end)
local function LEKAutopilotLog(k,v) if LEKAutopilotDB then pcall(function() LEKAutopilotDB.SetValue(k,v) end) end end

local LEKSpaceNextActionHeld = false
local LEKSpaceTrackedTurn = -1
local LEKSpaceTrackedPlayer = -1
local LEKSpaceTrackedUnit = -1
local LEKSpaceTrackedX = -1
local LEKSpaceTrackedY = -1
local LEKSpaceTrackedMoves = -1
local LEKSpaceSettlerAnchors = {}
local LEKSpaceGuardReviewTurns = {}
local LEKSpaceEscorts = {}
local LEKSpaceEscortTargets = {}
local LEKSpaceEscortDestinations = {}

local function LEKSpaceOnWorldAnchor(atype, bShow, x, y, data1)
    if atype == GenericWorldAnchorTypes.WORLD_ANCHOR_SETTLER then
        local key = x..":"..y
        if bShow then LEKSpaceSettlerAnchors[key] = {x=x,y=y} else LEKSpaceSettlerAnchors[key] = nil end
    end
end
Events.GenericWorldAnchor.Add(LEKSpaceOnWorldAnchor)

local function LEKSpaceClearTrackedUnit()
    LEKSpaceTrackedTurn = -1
    LEKSpaceTrackedPlayer = -1
    LEKSpaceTrackedUnit = -1
    LEKSpaceTrackedX = -1
    LEKSpaceTrackedY = -1
    LEKSpaceTrackedMoves = -1
end

local function LEKSpaceIsUnitBlocker(blockingType)
    return blockingType == EndTurnBlockingTypes.ENDTURN_BLOCKING_STACKED_UNITS
        or blockingType == EndTurnBlockingTypes.ENDTURN_BLOCKING_UNIT_NEEDS_ORDERS
        or blockingType == EndTurnBlockingTypes.ENDTURN_BLOCKING_UNITS
        or blockingType == EndTurnBlockingTypes.ENDTURN_BLOCKING_UNIT_PROMOTION
end

local function LEKSpaceIsAtWarWithAnyMajor(ownerID)
    local ownerTeam = Teams[Players[ownerID]:GetTeam()]
    for i=0,GameDefines.MAX_MAJOR_CIVS-1 do
        local p = Players[i]
        if p and p:IsAlive() and i~=ownerID and ownerTeam:IsAtWar(p:GetTeam()) then return true end
    end
    return false
end

-- Nearest visible enemy unit belonging to barbarians (includeBarbarians) or
-- to any major civ the unit's owner is at war with (includeWarPlayers).
local function LEKSpaceNearestEnemyUnit(unit, includeBarbarians, includeWarPlayers)
    local x,y = unit:GetX(), unit:GetY()
    local ownerID = unit:GetOwner()
    local ownerTeamID = Players[ownerID]:GetTeam()
    local ownerTeam = Teams[ownerTeamID]
    local best,bestDist = nil,nil
    for i=0,GameDefines.MAX_PLAYERS-1 do
        local p = Players[i]
        if p and p:IsAlive() and i~=ownerID then
            local isBarb = p:IsBarbarian()
            local qualifies = (isBarb and includeBarbarians) or (not isBarb and includeWarPlayers and ownerTeam:IsAtWar(p:GetTeam()))
            if qualifies then
                for eu in p:Units() do
                    local plot = eu:GetPlot()
                    if plot and plot:IsVisible(ownerTeamID,false) then
                        local d = Map.PlotDistance(x,y,eu:GetX(),eu:GetY())
                        if not best or d<bestDist then best,bestDist=eu,d end
                    end
                end
            end
        end
    end
    return best,bestDist
end

-- Bounded hex-radius scan for the nearest plot matching predicate. Used for
-- barbarian camps and the empire border, neither of which have a native
-- "find nearest" helper exposed to Lua.
local function LEKSpaceNearestPlot(x,y,radius,predicate)
    local best,bestDist = nil,nil
    for dx=-radius,radius do
        for dy=-radius,radius do
            local p = Map.GetPlot(x+dx,y+dy)
            if p then
                local d = Map.PlotDistance(x,y,p:GetX(),p:GetY())
                if d>0 and d<=radius and predicate(p) then
                    if not best or d<bestDist then best,bestDist=p,d end
                end
            end
        end
    end
    return best,bestDist
end

local function LEKSpaceIsGuardTraversable(p,unit)
    if not p or not unit or not p:IsOwned() or p:GetOwner()~=unit:GetOwner() then return false end
    local domain=unit:GetDomainType()
    if domain~=DomainTypes.DOMAIN_LAND and domain~=DomainTypes.DOMAIN_SEA then return false end
    return p:IsValidDomainForLocation(unit) and not p:IsMountain() and not p:IsImpassable()
end

local function LEKSpaceIsFrontierPlot(p,unit)
    if not LEKSpaceIsGuardTraversable(p,unit) then return false end
    for direction=0,5 do
        local adj = Map.PlotDirection(p:GetX(),p:GetY(),direction)
        if not adj or not adj:IsOwned() or adj:GetOwner()~=unit:GetOwner() then return true end
    end
    return false
end

local function LEKSpacePlotHasOtherCombatUnit(p,unit)
    if not p then return false end
    for i=0,p:GetNumUnits()-1 do
        local other=p:GetUnit(i)
        if other and other:GetOwner()==unit:GetOwner() and other:GetID()~=unit:GetID()
            and (other:GetBaseCombatStrength()>0 or other:GetBaseRangedCombatStrength()>0) then
            return true
        end
    end
    return false
end

-- Breadth-first search through the unit owner's traversable territory. This
-- avoids logging a geometric border target that the selected unit can never
-- actually reach (water, mountain, wrong landmass, or a disconnected pocket).
local function LEKSpaceNearestReachableFrontier(unit,radius)
    local start=unit:GetPlot()
    if not start then return nil end
    local queue={{plot=start,dist=0}}
    local seen={[start:GetPlotIndex()]=true}
    local head=1
    while head<=#queue do
        local node=queue[head]
        head=head+1
        if node.dist<radius then
            for direction=0,5 do
                local p=Map.PlotDirection(node.plot:GetX(),node.plot:GetY(),direction)
                if p and not seen[p:GetPlotIndex()] and LEKSpaceIsGuardTraversable(p,unit) then
                    seen[p:GetPlotIndex()]=true
                    local dist=node.dist+1
                    if LEKSpaceIsFrontierPlot(p,unit) and not LEKSpacePlotHasOtherCombatUnit(p,unit) then return p end
                    queue[#queue+1]={plot=p,dist=dist}
                end
            end
        end
    end
    return nil
end

-- Same generic action-execution mechanism used for unit promotion: scan the
-- currently selected unit's available actions for a specific mission type
-- and confirm the engine considers it legal right now, rather than blindly
-- pushing the mission and hoping.
local function LEKSpaceFindMissionAction(missionTypeName, plot)
    for actionID=0,#GameInfoActions do
        local action = GameInfoActions[actionID]
        if action and action.SubType == ActionSubTypes.ACTIONSUBTYPE_MISSION and action.Type == missionTypeName and Game.CanHandleAction(actionID, plot, false) then
            return actionID
        end
    end
    return nil
end

-- Match a real WorldView right-click. Raw MISSION_MOVE_TO network messages
-- can fail silently, leaving the selected unit stationary and causing the
-- next Automate tick to force-skip it as still blocked.
local function LEKSpaceMoveSelectedUnit(plot,result)
    if not plot then return false end
    LEKAutopilotLog("U_LastResult",result)
    LEKAutopilotLog("U_LastMoveX",plot:GetX())
    LEKAutopilotLog("U_LastMoveY",plot:GetY())
    Game.SelectionListMove(plot,false,false,false)
    return true
end

-- The native async C++ pathfinder can let two escorted units drift apart
-- when their movement points differ, breaking the same-tile invariant the
-- Settler escort logic depends on. Shared by both the Settler and Guard
-- sides of that logic so they step in lockstep instead of each getting a
-- long-range move order.
local function LEKSpaceGreedyStepToward(x,y,destPlot)
    local currentDist = Map.PlotDistance(x,y,destPlot:GetX(),destPlot:GetY())
    local nextPlot,nextDist = nil,nil
    for direction=0,5 do
        local p = Map.PlotDirection(x,y,direction)
        if p and not p:IsWater() and not p:IsImpassable() then
            local d = Map.PlotDistance(p:GetX(),p:GetY(),destPlot:GetX(),destPlot:GetY())
            if d<currentDist and (not nextPlot or d<nextDist) then nextPlot,nextDist=p,d end
        end
    end
    return nextPlot
end

-- Best-effort per-unit-type default action for a unit Space has just
-- selected because it needs orders. Never required to be optimal -- only to
-- avoid leaving an obviously-idle unit doing nothing. Wrapped in pcall by
-- the caller so an unexpected API surface here can never break the rest of
-- this file's input handling.
local function LEKSpaceAutoActUnitInner(unit, isStackedBlocker)
    local unitClass = nil
    local info = GameInfo.Units[unit:GetUnitType()]
    if info then unitClass = info.Class end
    local unitAIType = unit:GetUnitAIType()
    LEKAutopilotLog("U_LastUnitClass",unitClass or "")
    LEKAutopilotLog("U_LastUnitAIType",unitAIType or -1)

    if unit.CanPromote and unit:CanPromote() then
        -- GameInfoActions is the same unified action table (commands, builds,
        -- missions, promotions, automates) the native unit panel enumerates
        -- with Game.CanHandleAction and executes with Game.HandleAction --
        -- this picks the first legal promotion exactly the way a real click
        -- on a promotion icon would.
        local plot = unit:GetPlot()
        for actionID=0,#GameInfoActions do
            local action = GameInfoActions[actionID]
            if action and action.SubType == ActionSubTypes.ACTIONSUBTYPE_PROMOTION and Game.CanHandleAction(actionID, plot, false) then
                LEKAutopilotLog("U_LastResult","PROMOTED")
                Game.HandleAction(actionID)
                return true
            end
        end
    end
    if unitClass == "UNITCLASS_WORKER" or unitClass == "UNITCLASS_WORKBOAT" or (info and info.DefaultUnitAI == "UNITAI_WORKER_SEA") then
        -- Work Boats are UNITAI_WORKER_SEA, the sea counterpart of a land
        -- Worker's UNITAI_WORKER -- AUTOMATE_BUILD covers both, finding and
        -- improving whatever resource (land or water) the unit can reach.
        -- They were previously misclassified alongside Scouts as explorers,
        -- which is wrong: their job is building, not exploring.
        LEKAutopilotLog("U_LastResult","AUTOMATE_WORKER")
        Game.SelectionListGameNetMessage(GameMessageTypes.GAMEMESSAGE_DO_COMMAND, CommandTypes.COMMAND_AUTOMATE, GameInfoTypes.AUTOMATE_BUILD, -1, 0, false)
        return true
    end
    local isExplorer = (unitClass == "UNITCLASS_SCOUT")
        or (GameInfoTypes.PROMOTION_IGNORE_TERRAIN_COST and unit.IsHasPromotion and unit:IsHasPromotion(GameInfoTypes.PROMOTION_IGNORE_TERRAIN_COST))
        or (info and info.DefaultUnitAI == "UNITAI_EXPLORE")
        or (GameInfo.UnitAIInfos.UNITAI_EXPLORE and unitAIType == GameInfo.UnitAIInfos.UNITAI_EXPLORE.ID)
    if isExplorer then
        LEKAutopilotLog("U_LastResult",unitClass == "UNITCLASS_SCOUT" and "AUTOMATE_EXPLORE_CLASS" or "AUTOMATE_EXPLORE_RETAINED_ROLE")
        Game.SelectionListGameNetMessage(GameMessageTypes.GAMEMESSAGE_DO_COMMAND, CommandTypes.COMMAND_AUTOMATE, GameInfoTypes.AUTOMATE_EXPLORE, -1, 0, false)
        return true
    end
    if unit:GetDomainType() == DomainTypes.DOMAIN_SEA and unit:GetBaseCombatStrength() == 0 and unit:GetBaseRangedCombatStrength() == 0 then
        -- An unarmed naval unit (e.g. the first boat built) -- treat like a scout.
        LEKAutopilotLog("U_LastResult","AUTOMATE_EXPLORE_SEA")
        Game.SelectionListGameNetMessage(GameMessageTypes.GAMEMESSAGE_DO_COMMAND, CommandTypes.COMMAND_AUTOMATE, GameInfoTypes.AUTOMATE_EXPLORE, -1, 0, false)
        return true
    end
    if unitClass == "UNITCLASS_SETTLER" then
        local x,y = unit:GetX(), unit:GetY()
        local owner = Players[unit:GetOwner()]
        local foundAction = nil
        for i=0,#GameInfoActions do
            local a = GameInfoActions[i]
            if a and a.Type == "MISSION_FOUND" then
                foundAction = a.ID
                break
            end
        end
        if owner and owner:CanFound(x,y) and foundAction then
            LEKAutopilotLog("U_LastResult","SETTLE_HERE")
            Game.HandleAction(foundAction)
            return true
        end
        local best,bestDist=nil,nil
        for _,p in pairs(LEKSpaceSettlerAnchors) do
            local d=Map.PlotDistance(x,y,p.x,p.y)
            if not best or d<bestDist then best,bestDist=p,d end
        end
        if not best or bestDist>12 then
            -- The recommended-anchor list can be sparse, or point somewhere
            -- distant even when a good site sits nearby -- scan local
            -- founding value before giving up or committing to a long march.
            local fallback,fallbackVal=nil,nil
            for dx=-8,8 do
                for dy=-8,8 do
                    local p=Map.GetPlot(x+dx,y+dy)
                    if p and Map.PlotDistance(x,y,p:GetX(),p:GetY())<=8 and owner and owner:CanFound(p:GetX(),p:GetY()) then
                        local val=p:GetFoundValue(owner:GetID())
                        if not fallback or val>fallbackVal then fallback,fallbackVal=p,val end
                    end
                end
            end
            if fallback then
                best={x=fallback:GetX(),y=fallback:GetY()}
                bestDist=Map.PlotDistance(x,y,best.x,best.y)
            end
        end
        if not best then
            LEKAutopilotLog("U_LastResult","SETTLE_NO_RECOMMENDATION_YET")
            return false
        end
        if best.x == x and best.y == y then
            if unit:MovesLeft() > 0 then
                LEKSpaceSettlerAnchors[x..":"..y] = nil
                LEKAutopilotLog("U_LastResult","SETTLE_ANCHOR_INVALID")
            else
                LEKAutopilotLog("U_LastResult","SETTLE_WAIT_NO_MOVES")
            end
            Game.SelectionListGameNetMessage(GameMessageTypes.GAMEMESSAGE_PUSH_MISSION, GameInfoTypes.MISSION_SKIP, 0, 0, 0, false)
            return true
        end
        local settlerID = unit:GetID()
        local destPlot = Map.GetPlot(best.x,best.y)
        LEKSpaceEscortDestinations[settlerID] = destPlot
        if unit:GetPlot():GetOwner() ~= unit:GetOwner() or destPlot:GetOwner() ~= unit:GetOwner() then
            -- Recommended settle sites -- or the path there -- can sit
            -- outside current borders, where an unescorted Settler is easy
            -- pickings for barbarians. Bind one land combat unit to this
            -- Settler and hold both at the same tile before moving them
            -- together, instead of sending the Settler alone.
            local guardID = LEKSpaceEscorts[settlerID]
            local guard = guardID and owner:GetUnitByID(guardID) or nil
            if not guard then
                local guardDist = nil
                for candidate in owner:Units() do
                    if (candidate:GetBaseCombatStrength()>0 or candidate:GetBaseRangedCombatStrength()>0)
                        and candidate:GetDomainType() == DomainTypes.DOMAIN_LAND
                        and not LEKSpaceEscortTargets[candidate:GetID()] then
                        local d = Map.PlotDistance(x,y,candidate:GetX(),candidate:GetY())
                        if not guard or d<guardDist then guard,guardDist=candidate,d end
                    end
                end
                if guard then
                    LEKSpaceEscorts[settlerID] = guard:GetID()
                    LEKSpaceEscortTargets[guard:GetID()] = settlerID
                end
            end
            if not guard or guard:GetX()~=x or guard:GetY()~=y then
                if guard then
                    -- A fortified/sentry guard never re-enters the turn
                    -- queue on its own -- wake it so it actually marches to
                    -- the Settler instead of sitting there forever. Waking it
                    -- changes the UI selection, so the Settler must be
                    -- re-selected before the skip below or that skip lands
                    -- on the guard instead.
                    UI.SelectUnit(guard)
                    Game.SelectionListGameNetMessage(GameMessageTypes.GAMEMESSAGE_DO_COMMAND, CommandTypes.COMMAND_WAKE, 0, 0, 0, false)
                    LEKSpaceGuardReviewTurns[guard:GetID()] = nil
                    UI.SelectUnit(unit)
                end
                LEKAutopilotLog("U_LastResult","SETTLE_WAIT_FOR_ESCORT")
                Game.SelectionListGameNetMessage(GameMessageTypes.GAMEMESSAGE_PUSH_MISSION, GameInfoTypes.MISSION_SKIP, 0, 0, 0, false)
                return true
            end
            if unit:MovesLeft() <= 0 or guard:MovesLeft() <= 0 then
                LEKAutopilotLog("U_LastResult","SETTLE_WAIT_FOR_ESCORT_MOVES")
                Game.SelectionListGameNetMessage(GameMessageTypes.GAMEMESSAGE_PUSH_MISSION, GameInfoTypes.MISSION_SKIP, 0, 0, 0, false)
                return true
            end
            local nextPlot = LEKSpaceGreedyStepToward(x,y,destPlot)
            LEKAutopilotLog("U_LastResult","SETTLE_MOVE_WITH_ESCORT")
            UI.ClearSelectionList()
            if nextPlot then
                UI.SelectUnit(unit)
                Game.SelectionListGameNetMessage(GameMessageTypes.GAMEMESSAGE_PUSH_MISSION, GameInfoTypes.MISSION_MOVE_TO, nextPlot:GetX(), nextPlot:GetY(), 0, false)
                UI.SelectUnit(guard)
                Game.SelectionListGameNetMessage(GameMessageTypes.GAMEMESSAGE_PUSH_MISSION, GameInfoTypes.MISSION_MOVE_TO, nextPlot:GetX(), nextPlot:GetY(), 0, false)
            else
                UI.SelectUnit(unit)
                Game.SelectionListMove(destPlot,false,false,false)
                UI.SelectUnit(guard)
                Game.SelectionListMove(destPlot,false,false,false)
            end
            return true
        end
        return LEKSpaceMoveSelectedUnit(destPlot,"SETTLE_MOVE_TO_RECOMMENDED")
    end
    if unitClass == "UNITCLASS_PROPHET" then
        local plot = unit:GetPlot()
        -- First Prophet: found a religion. Second (once founded): enhance
        -- it. Either opens ChooseReligionPopup (BUTTONPOPUP_FOUND_RELIGION),
        -- which the policy-congress autopilot's LEKSpaceReligion() already
        -- drives end-to-end -- including picking the belief options -- from
        -- there.
        local foundAction = LEKSpaceFindMissionAction("MISSION_FOUND_RELIGION", plot)
        if foundAction then
            LEKAutopilotLog("U_LastResult","PROPHET_FOUND_RELIGION")
            Game.HandleAction(foundAction)
            return true
        end
        local enhanceAction = LEKSpaceFindMissionAction("MISSION_ENHANCE_RELIGION", plot)
        if enhanceAction then
            LEKAutopilotLog("U_LastResult","PROPHET_ENHANCE_RELIGION")
            Game.HandleAction(enhanceAction)
            return true
        end
        -- Neither is legal anymore (already founded and enhanced) -- put
        -- further Prophets to work spreading the religion instead of leaving
        -- them idle: spread right here if this city can still take it,
        -- otherwise head for the nearest own city that doesn't have this
        -- religion as its majority yet.
        local religionID = unit:GetReligion()
        if religionID and religionID >= 0 then
            local spreadAction = LEKSpaceFindMissionAction("MISSION_SPREAD_RELIGION", plot)
            local cityHere = plot:GetPlotCity()
            if spreadAction and (not cityHere or cityHere:GetReligiousMajority() ~= religionID) then
                LEKAutopilotLog("U_LastResult","PROPHET_SPREAD_RELIGION_HERE")
                Game.HandleAction(spreadAction)
                return true
            end
            local target,targetDist = nil,nil
            for i = 0, GameDefines.MAX_CIV_PLAYERS - 1 do
                local p = Players[i]
                if p and p:IsAlive() then
                    for city in p:Cities() do
                        if city:GetReligiousMajority() ~= religionID then
                            local d = Map.PlotDistance(unit:GetX(),unit:GetY(),city:GetX(),city:GetY())
                            if not target or d<targetDist then target,targetDist=city,d end
                        end
                    end
                end
            end
            if target then
                return LEKSpaceMoveSelectedUnit(Map.GetPlot(target:GetX(),target:GetY()),"PROPHET_MOVE_TO_SPREAD_TARGET")
            end
        end
        LEKAutopilotLog("U_LastResult","PROPHET_NO_RELIGIOUS_WORK_LEFT")
        Game.SelectionListGameNetMessage(GameMessageTypes.GAMEMESSAGE_DO_COMMAND, CommandTypes.COMMAND_SLEEP, 0, 0, 0, false)
        return true
    end
    if unitClass == "UNITCLASS_CARAVAN" or unitClass == "UNITCLASS_CARGO_SHIP" or (info and info.DefaultUnitAI == "UNITAI_TRADE_UNIT") then
        -- Bypasses ChooseInternationalTradeRoutePopup entirely and calls the
        -- same native destination list and mission it commits, mirroring the
        -- "highest max Gold" sort option that popup itself offers by default.
        local owner = Players[unit:GetOwner()]
        local destinations = owner:GetPotentialInternationalTradeRouteDestinations(unit)
        local best,bestGold = nil,nil
        for _,v in ipairs(destinations or {}) do
            local gold = 0
            if v.Yields and v.Yields[YieldTypes.YIELD_GOLD+1] then gold = v.Yields[YieldTypes.YIELD_GOLD+1].Mine or 0 end
            if not best or gold>bestGold or (gold==bestGold and (v.X<best.X or (v.X==best.X and v.Y<best.Y))) then best,bestGold=v,gold end
        end
        if best then
            LEKAutopilotLog("U_LastResult","ESTABLISHED_TRADE_ROUTE")
            local plot = Map.GetPlot(best.X, best.Y)
            Game.SelectionListGameNetMessage(GameMessageTypes.GAMEMESSAGE_PUSH_MISSION, GameInfoTypes.MISSION_ESTABLISH_TRADE_ROUTE, plot:GetPlotIndex(), best.TradeConnectionType, 0, false, nil)
            return true
        end
        LEKAutopilotLog("U_LastResult","NO_TRADE_ROUTE_AVAILABLE")
        return false
    end
    if unit:IsGreatPerson() then
        LEKAutopilotLog("U_LastResult","GREAT_PERSON_TRY_ABILITY")
        for _,name in ipairs({"MISSION_DISCOVER","MISSION_GOLDEN_AGE","MISSION_HURRY","MISSION_LEAD","MISSION_TRADE"}) do
            local m=GameInfoTypes[name]
            if m then Game.SelectionListGameNetMessage(GameMessageTypes.GAMEMESSAGE_PUSH_MISSION, m, unit:GetX(), unit:GetY(), 0, false) end
        end
        return true
    end
    if unit:GetBaseCombatStrength() > 0 or unit:GetBaseRangedCombatStrength() > 0 then
        if isStackedBlocker then
            local x,y = unit:GetX(), unit:GetY()
            for direction=0,5 do
                local p = Map.PlotDirection(x,y,direction)
                if p and not p:IsWater() and p:GetNumUnits() == 0 then
                    return LEKSpaceMoveSelectedUnit(p,"UNSTACK_MOVE")
                end
            end
            return false
        end
        local guardID = unit:GetID()
        local escortSettlerID = LEKSpaceEscortTargets[guardID]
        if escortSettlerID then
            local targetSettler = Players[unit:GetOwner()]:GetUnitByID(escortSettlerID)
            if targetSettler then
                if unit:GetX()~=targetSettler:GetX() or unit:GetY()~=targetSettler:GetY() then
                    return LEKSpaceMoveSelectedUnit(targetSettler:GetPlot(),"MOVE_TO_ESCORT_SETTLER")
                end
                local destPlot = LEKSpaceEscortDestinations[escortSettlerID]
                if destPlot then
                    local nextPlot = LEKSpaceGreedyStepToward(unit:GetX(),unit:GetY(),destPlot)
                    LEKAutopilotLog("U_LastResult","ESCORT_MOVE_WITH_SETTLER")
                    UI.ClearSelectionList()
                    if nextPlot then
                        UI.SelectUnit(unit)
                        Game.SelectionListGameNetMessage(GameMessageTypes.GAMEMESSAGE_PUSH_MISSION, GameInfoTypes.MISSION_MOVE_TO, nextPlot:GetX(), nextPlot:GetY(), 0, false)
                        UI.SelectUnit(targetSettler)
                        Game.SelectionListGameNetMessage(GameMessageTypes.GAMEMESSAGE_PUSH_MISSION, GameInfoTypes.MISSION_MOVE_TO, nextPlot:GetX(), nextPlot:GetY(), 0, false)
                    else
                        UI.SelectUnit(unit)
                        Game.SelectionListMove(destPlot,false,false,false)
                        UI.SelectUnit(targetSettler)
                        Game.SelectionListMove(destPlot,false,false,false)
                    end
                    return true
                end
            else
                -- Settler is gone (settled or lost) -- release this guard
                -- back into the ordinary combat priority ladder below.
                LEKSpaceEscortTargets[guardID] = nil
            end
        end
        local ownerID = unit:GetOwner()
        local x,y = unit:GetX(), unit:GetY()

        -- 1) At war with a major civ: head for the closest visible enemy unit.
        if LEKSpaceIsAtWarWithAnyMajor(ownerID) then
            local target = LEKSpaceNearestEnemyUnit(unit,false,true)
            if target then
                return LEKSpaceMoveSelectedUnit(target:GetPlot(),"MOVE_TOWARD_ENEMY")
            end
        end

        -- 2) Not (usefully) at war: seek the closest visible barbarian unit,
        -- else the closest known barbarian camp.
        local barbUnit = LEKSpaceNearestEnemyUnit(unit,true,false)
        if barbUnit then
            return LEKSpaceMoveSelectedUnit(barbUnit:GetPlot(),"MOVE_TOWARD_BARBARIAN")
        end
        local ownerTeamID = Players[ownerID]:GetTeam()
        local campPlot = LEKSpaceNearestPlot(x,y,15,function(p)
            return p:GetImprovementType()==GameInfoTypes.IMPROVEMENT_BARBARIAN_CAMP and p:IsRevealed(ownerTeamID,false)
        end)
        if campPlot then
            return LEKSpaceMoveSelectedUnit(campPlot,"MOVE_TOWARD_BARBARIAN_CAMP")
        end

        -- 3) Nothing hostile anywhere nearby: head to the edge of the empire
        -- and hold there instead of sitting fortified deep in the interior.
        if LEKSpaceIsFrontierPlot(unit:GetPlot(),unit) and not LEKSpacePlotHasOtherCombatUnit(unit:GetPlot(),unit) then
            LEKAutopilotLog("U_LastResult","FORTIFY_AT_BORDER")
            LEKSpaceGuardReviewTurns[unit:GetID()]=Game.GetGameTurn()+10
            Game.SelectionListGameNetMessage(GameMessageTypes.GAMEMESSAGE_PUSH_MISSION, GameInfoTypes.MISSION_ALERT, 0, 0, 0, false)
            return true
        end
        local borderPlot = LEKSpaceNearestReachableFrontier(unit,30)
        if borderPlot then
            return LEKSpaceMoveSelectedUnit(borderPlot,"MOVE_TO_BORDER_GUARD")
        end
        LEKAutopilotLog("U_LastResult","FORTIFY")
        LEKSpaceGuardReviewTurns[unit:GetID()]=Game.GetGameTurn()+10
        Game.SelectionListGameNetMessage(GameMessageTypes.GAMEMESSAGE_PUSH_MISSION, GameInfoTypes.MISSION_ALERT, 0, 0, 0, false)
        return true
    end
    return false
end
local function LEKSpaceAutoActUnit(unit, isStackedBlocker)
    local ok,result = pcall(LEKSpaceAutoActUnitInner, unit, isStackedBlocker)
    if not ok then LEKAutopilotLog("U_LastError",tostring(result)); return false end
    return result
end

-- Alert removes a guard from the ordinary end-turn blocker list. Remember
-- every alerted combat unit and wake it after ten turns so expanding culture
-- borders do not leave the old guard line permanently stranded in the
-- interior. One due guard is reconsidered per world tick.
local function LEKSpaceReviewDueGuard(player,turn)
    for guard in player:Units() do
        if (guard:GetBaseCombatStrength()>0 or guard:GetBaseRangedCombatStrength()>0)
            and guard:GetActivityType()==ActivityTypes.ACTIVITY_SENTRY then
            local id=guard:GetID()
            local due=LEKSpaceGuardReviewTurns[id]
            if not due then
                LEKSpaceGuardReviewTurns[id]=turn+10
            elseif turn>=due then
                LEKSpaceGuardReviewTurns[id]=nil
                UI.SelectUnit(guard)
                LEKAutopilotLog("U_LastGuardReviewTurn",turn)
                LEKAutopilotLog("U_LastGuardReviewUnit",id)
                LEKSpaceAutoActUnit(guard,false)
                return true
            end
        end
    end
    return false
end

-- The native handler for this blocker only calls UI.GetHeadSelectedCity() and
-- LookAt -- the engine has already selected the blocked city by the time this
-- runs, same as UI.GetHeadSelectedUnit() for the unit blockers above.
local function LEKSpaceCityRangeAttackInner(city)
    local x,y = city:GetX(), city:GetY()
    local target = LEKSpaceNearestPlot(x,y,6,function(p)
        return city:CanRangeStrikeAt(p:GetX(),p:GetY(),true,true)
    end)
    if target then
        LEKAutopilotLog("CR_LastResult","STRUCK")
        Game.SelectedCitiesGameNetMessage(GameMessageTypes.GAMEMESSAGE_DO_TASK, TaskTypes.TASK_RANGED_ATTACK, target:GetX(), target:GetY())
        return true
    end
    LEKAutopilotLog("CR_LastResult","NO_LEGAL_TARGET")
    return false
end
local function LEKSpaceCityRangeAttack(city)
    local ok,result = pcall(LEKSpaceCityRangeAttackInner, city)
    if not ok then LEKAutopilotLog("CR_LastError",tostring(result)); return false end
    return result
end

local function LEKSpaceActivateOrSkip()
    local playerID = Game.GetActivePlayer()
    local player = Players[playerID]
    local turn = Game.GetGameTurn()
    local unit = UI.GetHeadSelectedUnit()
    local moves = unit and unit.GetMoves and unit:GetMoves() or -1
    local x = unit and unit.GetX and unit:GetX() or -1
    local y = unit and unit.GetY and unit:GetY() or -1
    if player and unit
        and LEKSpaceTrackedTurn == turn
        and LEKSpaceTrackedPlayer == playerID
        and LEKSpaceTrackedUnit == unit:GetID()
        and LEKSpaceTrackedX == x
        and LEKSpaceTrackedY == y
        and LEKSpaceTrackedMoves == moves then
        LEKSpaceClearTrackedUnit()
        -- This exact unit was already acted on this same turn and is still
        -- the blocker -- whatever Space tried (an Automate call swallowed by
        -- a goody hut, a Great Person mission with no legal target here,
        -- etc.) didn't clear it, so retrying the same action would loop
        -- forever. A Scout with nowhere left to explore, or a Work Boat with
        -- no resource left to improve, is just dead weight from here on, so
        -- it gets deleted rather than skipped every turn indefinitely;
        -- anything else gets a plain Skip.
        local info = GameInfo.Units[unit:GetUnitType()]
        local unitClass = info and info.Class
        local isStrandedCandidate = (unitClass == "UNITCLASS_SCOUT")
            or (unitClass == "UNITCLASS_WORKBOAT")
            or (info and info.DefaultUnitAI == "UNITAI_WORKER_SEA")
            or (GameInfoTypes.PROMOTION_IGNORE_TERRAIN_COST and unit.IsHasPromotion and unit:IsHasPromotion(GameInfoTypes.PROMOTION_IGNORE_TERRAIN_COST))
        if isStrandedCandidate then
            -- The native Delete button never uses a raw network command -- it
            -- goes through the same generic action mechanism as Promotion
            -- (Game.HandleAction/GameInfoActions). The raw
            -- GAMEMESSAGE_DO_COMMAND+COMMAND_DELETE call silently had no
            -- effect, leaving the unit alive and re-selected as still needing
            -- orders every subsequent turn.
            local plot = unit:GetPlot()
            local deleteAction = nil
            for actionID=0,#GameInfoActions do
                local action = GameInfoActions[actionID]
                if action and action.SubType == ActionSubTypes.ACTIONSUBTYPE_COMMAND and action.Type == "COMMAND_DELETE" and Game.CanHandleAction(actionID, plot, false) then
                    deleteAction = actionID
                    break
                end
            end
            if deleteAction then
                LEKAutopilotLog("U_LastResult","DELETED_STRANDED_UNIT")
                Game.HandleAction(deleteAction)
            else
                LEKAutopilotLog("U_LastResult","DELETE_UNAVAILABLE_SKIPPING")
                Game.SelectionListGameNetMessage(GameMessageTypes.GAMEMESSAGE_PUSH_MISSION, GameInfoTypes.MISSION_SKIP, unit:GetID(), 0, 0, false)
            end
        else
            Game.SelectionListGameNetMessage(GameMessageTypes.GAMEMESSAGE_PUSH_MISSION, GameInfoTypes.MISSION_SKIP, unit:GetID(), 0, 0, false)
        end
        return
    end

    LEKSpaceClearTrackedUnit()
    local blockingType = player and player:GetEndTurnBlockingType()
    -- LEK/EUI can retain the choose-research notification after the native
    -- research command has already assigned a current technology.  The
    -- stock click handler only reactivates that stale notification, trapping
    -- Automate on the tech tree and hiding later blockers such as production.
    -- Dismiss only the proven-stale normal-research case; free-tech and
    -- espionage choices remain untouched.
    if player
        and blockingType == EndTurnBlockingTypes.ENDTURN_BLOCKING_RESEARCH
        and player:GetCurrentResearch() >= 0
        and player:GetNumFreeTechs() <= 0
    then
        local staleIndex=player:GetEndTurnBlockingNotificationIndex()
        LEKAutopilotLog("U_LastResult","REMOVED_STALE_RESEARCH_NOTIFICATION")
        LEKAutopilotLog("U_LastBlockingType",blockingType)
        if staleIndex and staleIndex>=0 then UI.RemoveNotification(staleIndex) end
        LuaEvents.LEKSpaceAutomateModalHandled(0.75)
        return
    end
    LEKAutopilotLog("U_LastBlockingType",blockingType or -1)
    if player and blockingType==EndTurnBlockingTypes.NO_ENDTURN_BLOCKING_TYPE and LEKSpaceReviewDueGuard(player,turn) then
        return
    end
    OnEndTurnClicked()
    if player and LEKSpaceIsUnitBlocker(blockingType) then
        unit = UI.GetHeadSelectedUnit()
        if unit then
            local isStackedBlocker = blockingType == EndTurnBlockingTypes.ENDTURN_BLOCKING_STACKED_UNITS
            LEKSpaceAutoActUnit(unit, isStackedBlocker)
            -- Track this unit regardless of what the dispatcher believed it
            -- accomplished -- if it's still the blocker on the very next
            -- press, the check above forces a resolution instead of retrying
            -- an action that silently didn't stick.
            LEKSpaceTrackedTurn = turn
            LEKSpaceTrackedPlayer = playerID
            LEKSpaceTrackedUnit = unit:GetID()
            LEKSpaceTrackedX = unit:GetX()
            LEKSpaceTrackedY = unit:GetY()
            LEKSpaceTrackedMoves = unit:GetMoves()
        end
    elseif player and blockingType == EndTurnBlockingTypes.ENDTURN_BLOCKING_CITY_RANGE_ATTACK then
        local city = UI.GetHeadSelectedCity()
        if city then LEKSpaceCityRangeAttack(city) end
    end
end

-- Cross-context toggle for the "Automate" button in the Escape menu
-- (GameMenu.lua): that file writes this flag, this file is the only one
-- that reads it, since Lua Contexts don't share globals with each other.
local LEKAutomateDB=nil
pcall(function() LEKAutomateDB=Modding.OpenUserData("LEK_SPACE_AUTOMATE",1) end)
local function LEKAutomateIsActive()
    if not LEKAutomateDB then return false end
    local ok,v = pcall(function() return LEKAutomateDB.GetValue("Active") end)
    return ok and v==1
end
local function LEKAutomateSetActive(active)
    if LEKAutomateDB then pcall(function() LEKAutomateDB.SetValue("Active", active and 1 or 0) end) end
end
-- Modal contexts get the first phase of each persistent driver tick.  The
-- driver emits this second phase only when no modal consumed that tick, so
-- ActionInfoPanel never needs a remembered pause flag that can become stale.
LuaEvents.LEKSpaceAutomateWorldTick.Add(function()
    LEKSpaceActivateOrSkip()
end)

local function LEKSpaceNextActionInput(uiMsg, wParam)
    -- Any keypress stops automation -- it doesn't have to be Escape
    -- specifically, just something the player actively did.
    if uiMsg == KeyEvents.KeyDown and LEKAutomateIsActive() then
        LEKAutomateSetActive(false)
    end
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

    # InGame is the persistent parent of WorldView and CityView. Patch every
    # installed DLC copy plus LEKMOD's override so the active layout always
    # owns the cross-context automation clock.
    $inGameCandidates=@(
        @{Path=(Join-LEKPath $civ 'Assets\UI\InGame\InGame.lua'); Backup='InGame-driver-base.lua'},
        @{Path=(Join-LEKPath $civ 'Assets\DLC\Expansion\UI\InGame\InGame.lua'); Backup='InGame-driver-expansion.lua'},
        @{Path=(Join-LEKPath $civ 'Assets\DLC\Expansion2\UI\InGame\InGame.lua'); Backup='InGame-driver-expansion2.lua'},
        @{Path=(Join-LEKPath $civ 'Assets\DLC\LEKMOD_V30.7\UI\InGame.lua'); Backup='InGame-driver-lekmod.lua'}
    ) | Where-Object { Test-LEKPath $_.Path }
    if($inGameCandidates.Count -eq 0){ throw 'No persistent InGame.lua parent was found.' }
    $driverBody=@'
local LEKSpaceDriverDB=nil
pcall(function() LEKSpaceDriverDB=Modding.OpenUserData("LEK_SPACE_AUTOMATE",1) end)
local LEKSpaceDriverTimer=0
local LEKSpaceDriverModalPause=0
local LEKSpaceDriverModalHandledThisTick=false
LuaEvents.LEKSpaceAutomateModalHandled.Add(function(seconds)
    LEKSpaceDriverModalHandledThisTick=true
    LEKSpaceDriverModalPause=math.max(LEKSpaceDriverModalPause,tonumber(seconds) or 1.7)
end)
local function LEKSpaceDriverActive()
    if not LEKSpaceDriverDB then return false end
    local ok,v=pcall(function() return LEKSpaceDriverDB.GetValue("Active") end)
    return ok and v==1
end
local LEKSpaceOriginalInGameUpdate=OnUpdate
function OnUpdate(dt)
    LEKSpaceOriginalInGameUpdate(dt)
    if LEKSpaceDriverActive() then
        if LEKSpaceDriverModalPause>0 then
            LEKSpaceDriverModalPause=LEKSpaceDriverModalPause-dt
            LEKSpaceDriverTimer=0
            return
        end
        LEKSpaceDriverTimer=LEKSpaceDriverTimer+dt
        if LEKSpaceDriverTimer>=0.7 then
            LEKSpaceDriverTimer=0
            LEKSpaceDriverModalHandledThisTick=false
            LuaEvents.LEKSpaceAutomateTick()
            if not LEKSpaceDriverModalHandledThisTick then
                LuaEvents.LEKSpaceAutomateWorldTick()
            end
        end
    else
        LEKSpaceDriverTimer=0
        LEKSpaceDriverModalPause=0
    end
end
'@
    foreach($candidate in $inGameCandidates){
        $inGame=$candidate.Path
        $it=[IO.File]::ReadAllText($inGame)
        if(!$it.Contains('ContextPtr:SetUpdate( OnUpdate );')){ throw "Unexpected InGame.lua update layout: $inGame" }
        Backup-LEKFileOnce $inGame $backupRoot $candidate.Backup | Out-Null
        $it=Remove-LEKMarkedBlock $it $DriverBegin $DriverEnd
        $anchor='ContextPtr:SetUpdate( OnUpdate );'
        $block="$DriverBegin`r`n$($driverBody.Trim())`r`n$DriverEnd`r`n"
        $it=$it.Replace($anchor,$block+$anchor)
        Write-LEKUtf8NoBom $inGame $it
    }
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
-- Automate (the Escape-menu button) never presses a real key, so an incoming
-- AI trade offer sat here forever with no way to accept it -- this was never
-- wired into the Automate tick at all, unlike every other Space-driven screen.
LuaEvents.LEKSpaceAutomateTick.Add(function()
    if not ContextPtr:IsHidden() then
        LuaEvents.LEKSpaceAutomateModalHandled(1.7)
        pcall(LEKSpaceAcceptIncomingOffer)
    end
end)
'@
    Set-LEKMarkedBlock $tradeTarget $TradeBegin $TradeEnd $tradeBody.Trim()

    $confirmCandidates=@(
        (Join-LEKPath $civ 'Assets\DLC\UI_bc1\Improvements\ConfirmCommandPopup.lua'),
        (Join-LEKPath $civ 'Assets\UI\InGame\PopupsGeneric\ConfirmCommandPopup.lua')
    ) | Where-Object { Test-LEKPath $_ }
    if($confirmCandidates.Count -eq 0){ throw 'No ConfirmCommandPopup.lua copy was found.' }
    $confirmBody=@'
local LEKSpaceActiveConfirmAction = nil
local LEKSpaceActiveConfirmAlt = false

local function LEKSpaceExecuteConfirmCommand()
    if LEKSpaceActiveConfirmAction and LEKSpaceActiveConfirmAction.CommandType then
        Game.SelectionListGameNetMessage( GameMessageTypes.GAMEMESSAGE_DO_COMMAND, LEKSpaceActiveConfirmAction.CommandType, LEKSpaceActiveConfirmAction.CommandData, -1, 0, LEKSpaceActiveConfirmAlt or false )
        LEKSpaceActiveConfirmAction = nil
        HideWindow()
        return true
    end
    return false
end

local LEKOriginalPopupLayoutConfirm = PopupLayouts[ButtonPopupTypes.BUTTONPOPUP_CONFIRMCOMMAND]
PopupLayouts[ButtonPopupTypes.BUTTONPOPUP_CONFIRMCOMMAND] = function(popupInfo)
    local bAlt = popupInfo.Option1
    local action = GameInfoActions[popupInfo.Data1] or {}
    LEKSpaceActiveConfirmAction = action
    LEKSpaceActiveConfirmAlt = bAlt
    if LEKOriginalPopupLayoutConfirm then
        return LEKOriginalPopupLayoutConfirm(popupInfo)
    end
end

local LEKOriginalPopupInputConfirm = PopupInputHandlers[ButtonPopupTypes.BUTTONPOPUP_CONFIRMCOMMAND]
PopupInputHandlers[ButtonPopupTypes.BUTTONPOPUP_CONFIRMCOMMAND] = function( uiMsg, wParam, lParam )
    if uiMsg == KeyEvents.KeyDown then
        if wParam == Keys.VK_SPACE then
            if LEKSpaceExecuteConfirmCommand() then return true end
        end
        if wParam == Keys.VK_ESCAPE or wParam == Keys.VK_RETURN then
            LEKSpaceActiveConfirmAction = nil
            HideWindow()
            return true
        end
    end
    if LEKOriginalPopupInputConfirm then
        return LEKOriginalPopupInputConfirm(uiMsg, wParam, lParam)
    end
end

LuaEvents.LEKSpaceAutomateTick.Add(function()
    if not ContextPtr:IsHidden() and LEKSpaceActiveConfirmAction ~= nil then
        LuaEvents.LEKSpaceAutomateModalHandled(1.7)
        pcall(LEKSpaceExecuteConfirmCommand)
    end
end)
'@
    foreach($confirmPath in $confirmCandidates){
        Backup-LEKFileOnce $confirmPath $backupRoot ([IO.Path]::GetFileName($confirmPath)) | Out-Null
        Set-LEKMarkedBlock $confirmPath $ConfirmBegin $ConfirmEnd $confirmBody.Trim()
    }

    # Civ V loads whichever GameMenu.xml the active DLC combination overrides
    # with (base game, Gods and Kings, or Brave New World each ship their own
    # copy of this exact screen's layout, all driven by the SAME GameMenu.lua)
    # so the button has to be added to every copy that exists, not just the
    # base one, or it silently won't appear in a BNW/G&K game. This mirrors
    # exactly what the MP Reroll/Rehost button already does in this file.
    $menuXmlCandidates=@(
        (Join-LEKPath $civ 'Assets\UI\InGame\Menus\GameMenu.xml'),
        (Join-LEKPath $civ 'Assets\DLC\Expansion\UI\InGame\Menus\GameMenu.xml'),
        (Join-LEKPath $civ 'Assets\DLC\Expansion2\UI\InGame\Menus\GameMenu.xml')
    ) | Where-Object { Test-LEKPath $_ }
    if($menuXmlCandidates.Count -eq 0){ throw 'No GameMenu.xml copy was found.' }
    $buttonXml=@'
        <GridButton Anchor="C,T" ID="LekAutomateButton" Size="320,45" Style="ZoomButton" String="AUTOMATE" ToolTip="Repeats Space's turn actions automatically until you press any key.">
          <ShowOnMouseOver>
            <AlphaAnim Anchor="L,T" Size="320,48" Pause="0" Cycle="Bounce" Speed="1" AlphaStart="1.5" AlphaEnd="1">
              <Grid   Size="320,48" Offset="0,-2" Padding="0,0" Style="Grid9FrameTurnsHL" />
            </AlphaAnim>
          </ShowOnMouseOver>
          <Image Anchor="C,B" AnchorSide="I.O" Offset="0,0" Texture="bar300x2.dds" Size="300.1" />
        </GridButton>
'@
    foreach($menuXml in $menuXmlCandidates){
        $mt=[IO.File]::ReadAllText($menuXml)
        if(!$mt.Contains('ID="RetireButton"')){ throw "Unexpected GameMenu.xml layout (RetireButton not found): $menuXml" }
        Backup-LEKFileOnce $menuXml $backupRoot ('GameMenu-'+([IO.Path]::GetFileName((Split-Path (Split-Path $menuXml -Parent) -Parent)))+'.xml') | Out-Null
        $mt=Remove-LEKMarkedBlock $mt $MenuButtonBegin $MenuButtonEnd
        $riIdx=$mt.IndexOf('ID="RetireButton"')
        $closeTag='</GridButton>'
        $closeIdx=$mt.IndexOf($closeTag,$riIdx)
        if($closeIdx -lt 0){ throw "RetireButton closing tag not found in GameMenu.xml: $menuXml" }
        $insertAt=$closeIdx+$closeTag.Length
        $insertBlock="`r`n$MenuButtonBegin`r`n      $($buttonXml.Trim())`r`n      $MenuButtonEnd"
        $mt=$mt.Insert($insertAt,$insertBlock)
        Write-LEKUtf8NoBom $menuXml $mt
    }

    $menuLua=Join-LEKPath $civ 'Assets\UI\InGame\Menus\GameMenu.lua'
    if(!(Test-LEKPath $menuLua)){ throw 'GameMenu.lua was not found.' }
    if(!(Test-LEKContains $menuLua 'Controls.ReturnButton:RegisterCallback( Mouse.eLClick, OnReturn );')){ throw 'Unexpected GameMenu.lua layout.' }
    Backup-LEKFileOnce $menuLua $backupRoot 'GameMenu.lua' | Out-Null
    $menuBody=@'
do
    local LEKAutomateDB=nil
    pcall(function() LEKAutomateDB=Modding.OpenUserData("LEK_SPACE_AUTOMATE",1) end)
    local function LEKAutomateIsActive()
        if not LEKAutomateDB then return false end
        local ok,v = pcall(function() return LEKAutomateDB.GetValue("Active") end)
        return ok and v==1
    end
    local function LEKAutomateSetActive(active)
        if LEKAutomateDB then pcall(function() LEKAutomateDB.SetValue("Active", active and 1 or 0) end) end
    end
    local function LEKAutomateRefreshButton()
        if not Controls.LekAutomateButton then return end
        if LEKAutomateIsActive() then
            Controls.LekAutomateButton:SetText("STOP AUTOMATING")
        else
            Controls.LekAutomateButton:SetText("AUTOMATE")
        end
    end
    local function LEKAutomateClick()
        if LEKAutomateIsActive() then
            LEKAutomateSetActive(false)
            LEKAutomateRefreshButton()
        else
            LEKAutomateSetActive(true)
            LEKAutomateRefreshButton()
            OnReturn()
        end
    end
    -- Defensive: this XML layout should always define the button (installed
    -- into base/G&K/BNW GameMenu.xml alike), but never let a missing control
    -- on some other layout throw and break the rest of this file's chunk.
    if Controls.LekAutomateButton then
        Controls.LekAutomateButton:RegisterCallback(Mouse.eLClick, LEKAutomateClick)
    end

    -- Chain onto whatever OnShowHide currently is (native, or another
    -- component's own wrap of it) rather than replacing it outright.
    local oldShow = OnShowHide
    function OnShowHide(hide, init)
        if oldShow then oldShow(hide, init) end
        if not hide then LEKAutomateRefreshButton() end
    end
    ContextPtr:SetShowHideHandler(OnShowHide)
end
'@
    Set-LEKMarkedBlock $menuLua $MenuLogicBegin $MenuLogicEnd $menuBody.Trim()

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Verify.ps1') -CivPath $civ
    if($LASTEXITCODE -ne 0){ throw 'Space Next Action was written, but verification failed.' }
    W 'SPACE NEXT ACTION v0.7 INSTALLED.' Green
    exit 0
} catch { W ('ERROR: '+$_.Exception.Message) Red; exit 1 }
