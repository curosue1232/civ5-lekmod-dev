-- LEKMOD 30.7 Fair Trades v1.0.4
-- Clean extension runtime for the frozen LEK Core v1.3 stack.
--
-- Architecture:
--   * One hidden context loaded by one stable InGame.lua loader block.
--   * No EUI file patch in v1.0.
--   * One authoritative scan at ActivePlayerTurnStart.
--   * No ContextPtr:SetUpdate. GameDataDirty is used only as a transient turn-ready wake signal.
--   * Native Civ V deal AI constructs the counter-price through
--       UI.DoWhatWillAIGive / UI.DoWhatDoesAIWant.
--   * Hard single-digit native-helper budget per human turn.
--   * Generated proactive offers are limited to luxury / gold / GPT in v1.0.
--   * Strategic resources are never accepted into a generated offer.
--   * Final simple-value gate guarantees AI-gives >= human-gives.
--   * Relationship affects proactive frequency, not the AI's native price.

print("LEK Fair Trades v1.0.4: loading")
-- LEK_FAIR_TRADES_TRANSIENT_READY_SIGNAL_V104
-- Event-driven runtime. The context can remain hidden because Civ V still sends
-- registered events to it. No per-frame update handler is used in v1.0.4.
ContextPtr:SetHide(true)
MapModData = MapModData or {}

local RUNTIME_VERSION = 104
local STATE_SCHEMA_VERSION = 1
local MAX_NATIVE_HELPER_CALLS_PER_TURN = 8
local MAX_LUXURY_SEEDS_PER_SIDE = 2
local MIN_TURNS_BETWEEN_LOCAL_OFFERS = 2
local LUXURY_SIMPLE_VALUE = 240

if MapModData.LEK_FAIR_TRADES_RUNTIME_VERSION == RUNTIME_VERSION then
    return
end
MapModData.LEK_FAIR_TRADES_RUNTIME_VERSION = RUNTIME_VERSION

local g_lastScanTurn = -99999
local g_lastScanHuman = -1
local g_lastShownTurn = -99999
local g_pendingOffer = nil
local g_nativeCalls = 0
local g_retryArmed = false
local g_retryRegistered = false
local g_retryTurn = -1
local g_retryHuman = -1
local g_retrySignals = 0

local STATE_DB = nil
pcall(function()
    STATE_DB = Modding.OpenUserData("LEK_FAIR_TRADES", STATE_SCHEMA_VERSION)
end)

local function StateSet(key, value)
    if STATE_DB == nil then return end
    pcall(function() STATE_DB.SetValue(key, value) end)
end

local function DealDuration()
    local d = Game.GetDealDuration()
    if d == nil or d <= 0 then d = 30 end
    return d
end

local function IsLivingHumanMajor(playerID)
    local p = Players[playerID]
    return p ~= nil and p:IsAlive() and p:IsHuman() and not p:IsMinorCiv() and not p:IsBarbarian()
end

local function IsLivingAIMajor(playerID)
    local p = Players[playerID]
    return p ~= nil and p:IsAlive() and not p:IsHuman() and not p:IsMinorCiv() and not p:IsBarbarian()
end

local function IsLuxury(resourceID)
    return resourceID ~= nil and Game.GetResourceUsageType(resourceID) == ResourceUsageTypes.RESOURCEUSAGE_LUXURY
end

local function HashString(text)
    local h = 104729
    text = tostring(text or "")
    for i = 1, #text do
        h = (h * 131 + string.byte(text, i)) % 2147483629
    end
    return h
end

local function CurrentApproach(aiID, humanID)
    local ai = Players[aiID]
    if ai ~= nil and ai.GetMajorCivApproach ~= nil then
        local ok, v = pcall(function() return ai:GetMajorCivApproach(humanID) end)
        if ok and v ~= nil then return v end
    end
    return MajorCivApproachTypes.MAJOR_CIV_APPROACH_NEUTRAL
end

local function ApproachName(a)
    if a == MajorCivApproachTypes.MAJOR_CIV_APPROACH_WAR then return "WAR" end
    if a == MajorCivApproachTypes.MAJOR_CIV_APPROACH_HOSTILE then return "HOSTILE" end
    if a == MajorCivApproachTypes.MAJOR_CIV_APPROACH_DECEPTIVE then return "DECEPTIVE" end
    if a == MajorCivApproachTypes.MAJOR_CIV_APPROACH_GUARDED then return "GUARDED" end
    if a == MajorCivApproachTypes.MAJOR_CIV_APPROACH_AFRAID then return "AFRAID" end
    if a == MajorCivApproachTypes.MAJOR_CIV_APPROACH_FRIENDLY then return "FRIENDLY" end
    if a == MajorCivApproachTypes.MAJOR_CIV_APPROACH_NEUTRAL then return "NEUTRAL" end
    return tostring(a)
end

local function RelationshipInterval(aiID, humanID)
    local a = CurrentApproach(aiID, humanID)
    if a == MajorCivApproachTypes.MAJOR_CIV_APPROACH_WAR
        or a == MajorCivApproachTypes.MAJOR_CIV_APPROACH_HOSTILE
        or a == MajorCivApproachTypes.MAJOR_CIV_APPROACH_DECEPTIVE then
        return nil, a
    end
    if a == MajorCivApproachTypes.MAJOR_CIV_APPROACH_GUARDED then return 5, a end
    if a == MajorCivApproachTypes.MAJOR_CIV_APPROACH_NEUTRAL then return 3, a end
    if a == MajorCivApproachTypes.MAJOR_CIV_APPROACH_FRIENDLY
        or a == MajorCivApproachTypes.MAJOR_CIV_APPROACH_AFRAID then return 2, a end
    return 4, a
end

local function RelationshipOfferDue(aiID, humanID, turn)
    local interval, approach = RelationshipInterval(aiID, humanID)
    StateSet("AI_" .. tostring(aiID) .. "_Approach", ApproachName(approach))
    if interval == nil then return false end
    local offset = HashString(tostring(aiID) .. "|" .. tostring(humanID) .. "|REL") % interval
    return ((turn + offset) % interval) == 0
end

local function CanAITradeWithHuman(aiID, humanID)
    if not IsLivingAIMajor(aiID) or not IsLivingHumanMajor(humanID) then return false end
    local ai = Players[aiID]
    local human = Players[humanID]
    local aiTeam = Teams[ai:GetTeam()]
    local humanTeamID = human:GetTeam()
    if not aiTeam:IsHasMet(humanTeamID) then return false end
    if aiTeam:IsAtWar(humanTeamID) then return false end
    if ai.IsTradeSanctioned ~= nil then
        local ok, v = pcall(function() return ai:IsTradeSanctioned(humanID) end)
        if ok and v then return false end
    end
    return true
end

local function EligibleAIs(humanID)
    local out = {}
    for i = 0, GameDefines.MAX_MAJOR_CIVS - 1 do
        if CanAITradeWithHuman(i, humanID) then table.insert(out, i) end
    end
    table.sort(out)
    return out
end

local function Possible(deal, fromID, toID, itemType, data1, data2)
    local ok, v = pcall(function()
        return deal:IsPossibleToTradeItem(fromID, toID, itemType, data1 or 0, data2 or 0)
    end)
    return ok and v == true
end

local function SpareLuxuries(playerID, otherID)
    local p = Players[playerID]
    local other = Players[otherID]
    local out = {}
    if p == nil or other == nil then return out end
    local deal = UI.GetScratchDeal()
    for res in GameInfo.Resources() do
        local rid = res.ID
        if IsLuxury(rid) then
            local ours = p:GetNumResourceAvailable(rid, true) or 0
            local theirs = other:GetNumResourceAvailable(rid, true) or 0
            if ours > 1 and theirs <= 0
                and Possible(deal, playerID, otherID, TradeableItems.TRADE_ITEM_RESOURCES, rid, 1) then
                table.insert(out, rid)
            end
        end
    end
    table.sort(out)
    return out
end

local function SnapshotDeal(deal)
    local out = {}
    deal:ResetIterator()
    while true do
        local raw = { deal:GetNextItem() }
        local n = #raw
        if n < 1 or raw[1] == nil then break end
        table.insert(out, {
            itemType = raw[1],
            duration = raw[2] or 0,
            finalTurn = raw[3] or 0,
            data1 = raw[4] or 0,
            data2 = raw[5] or 0,
            data3 = raw[6] or 0,
            flag1 = raw[7] or false,
            fromPlayer = raw[n]
        })
    end
    return out
end

local function EconomicItemValue(item)
    if item.itemType == TradeableItems.TRADE_ITEM_GOLD then
        return math.max(0, item.data1 or 0)
    elseif item.itemType == TradeableItems.TRADE_ITEM_GOLD_PER_TURN then
        local duration = item.duration or 0
        if duration <= 0 then duration = DealDuration() end
        return math.max(0, item.data1 or 0) * duration
    elseif item.itemType == TradeableItems.TRADE_ITEM_RESOURCES then
        if not IsLuxury(item.data1) then return nil end
        return LUXURY_SIMPLE_VALUE * math.max(1, item.data2 or 1)
    end
    return nil
end

local function ValidateSnapshot(items, aiID, humanID)
    local aiGives = 0
    local humanGives = 0
    local aiItemCount = 0
    local humanItemCount = 0

    if items == nil or #items == 0 then return false, "EMPTY_DEAL" end

    for _, item in ipairs(items) do
        if item.fromPlayer ~= aiID and item.fromPlayer ~= humanID then
            return false, "THIRD_PARTY_ITEM"
        end
        local value = EconomicItemValue(item)
        if value == nil then
            return false, "UNSUPPORTED_OR_STRATEGIC_ITEM"
        end

        if item.itemType == TradeableItems.TRADE_ITEM_RESOURCES then
            local p = Players[item.fromPlayer]
            local qty = math.max(1, item.data2 or 1)
            local available = p and (p:GetNumResourceAvailable(item.data1, true) or 0) or 0
            if available <= qty then return false, "LAST_LUXURY_COPY" end
        end

        if item.fromPlayer == aiID then
            aiGives = aiGives + value
            aiItemCount = aiItemCount + 1
        else
            humanGives = humanGives + value
            humanItemCount = humanItemCount + 1
        end
    end

    if aiItemCount == 0 or humanItemCount == 0 then return false, "ONE_SIDED_DEAL" end
    if aiGives < humanGives then return false, "HUMAN_FAIRNESS_GATE" end
    return true, "OK", aiGives, humanGives
end

local function NativeDealValues(deal, aiID, humanID)
    local humanValue, aiValue = nil, nil
    local hp, ap = Players[humanID], Players[aiID]
    if hp ~= nil and hp.GetDealMyValue ~= nil then
        local ok, v = pcall(function() return hp:GetDealMyValue(deal) end)
        if ok then humanValue = v end
    end
    if ap ~= nil and ap.GetDealMyValue ~= nil then
        local ok, v = pcall(function() return ap:GetDealMyValue(deal) end)
        if ok then aiValue = v end
    end
    return humanValue, aiValue
end

local function CloseHeadlessTrade(aiID)
    local ai = Players[aiID]
    if ai ~= nil and ai.DoTradeScreenClosed ~= nil then
        pcall(function() ai:DoTradeScreenClosed(false) end)
    end
    if UI.SetOfferTradeRepeatCount ~= nil then pcall(function() UI.SetOfferTradeRepeatCount(0) end) end
end

local function RunNativeSeed(aiID, humanID, seedFromHuman, resourceID)
    if g_nativeCalls >= MAX_NATIVE_HELPER_CALLS_PER_TURN then
        return nil, "HELPER_BUDGET_EXHAUSTED"
    end
    if UI.DoWhatWillAIGive == nil or UI.DoWhatDoesAIWant == nil then
        return nil, "NATIVE_HELPERS_MISSING"
    end

    g_nativeCalls = g_nativeCalls + 1
    local deal = UI.GetScratchDeal()
    local opened = false
    local snapshot = nil
    local reason = "UNKNOWN"
    local nativeHumanValue, nativeAIValue = nil, nil

    local ok, err = pcall(function()
        Players[aiID]:DoTradeScreenOpened()
        UI.OnHumanOpenedTradeScreen(aiID)
        opened = true

        deal:ClearItems()
        deal:SetFromPlayer(humanID)
        deal:SetToPlayer(aiID)
        local fromID = seedFromHuman and humanID or aiID
        local toID = seedFromHuman and aiID or humanID
        if not Possible(deal, fromID, toID, TradeableItems.TRADE_ITEM_RESOURCES, resourceID, 1) then
            reason = "SEED_NOT_POSSIBLE"
            return
        end

        deal:AddResourceTrade(fromID, resourceID, 1, DealDuration())
        if seedFromHuman then
            UI.DoWhatWillAIGive()
        else
            UI.DoWhatDoesAIWant()
        end
        snapshot = SnapshotDeal(deal)
        nativeHumanValue, nativeAIValue = NativeDealValues(deal, aiID, humanID)
        reason = "NATIVE_HELPER_RETURNED"
    end)

    if opened then CloseHeadlessTrade(aiID) end
    if not ok then
        return nil, "NATIVE_HELPER_ERROR:" .. tostring(err)
    end
    if snapshot == nil then return nil, reason end

    local valid, why, aiGives, humanGives = ValidateSnapshot(snapshot, aiID, humanID)
    StateSet("AI_" .. tostring(aiID) .. "_LastNativeHumanValue", nativeHumanValue or "NA")
    StateSet("AI_" .. tostring(aiID) .. "_LastNativeAIValue", nativeAIValue or "NA")
    StateSet("AI_" .. tostring(aiID) .. "_LastSimpleAIGives", aiGives or -1)
    StateSet("AI_" .. tostring(aiID) .. "_LastSimpleHumanGives", humanGives or -1)
    if not valid then return nil, why end

    return {
        aiID = aiID,
        humanID = humanID,
        items = snapshot,
        aiGives = aiGives,
        humanGives = humanGives,
        seed = seedFromHuman and "HUMAN_LUX_WHAT_WILL_AI_GIVE" or "AI_LUX_WHAT_DOES_AI_WANT"
    }, "OK"
end

local function RebuildSnapshot(deal, offer)
    deal:ClearItems()
    deal:SetFromPlayer(offer.humanID)
    deal:SetToPlayer(offer.aiID)
    for _, item in ipairs(offer.items) do
        local fromID = item.fromPlayer
        if item.itemType == TradeableItems.TRADE_ITEM_GOLD then
            deal:AddGoldTrade(fromID, item.data1)
        elseif item.itemType == TradeableItems.TRADE_ITEM_GOLD_PER_TURN then
            deal:AddGoldPerTurnTrade(fromID, item.data1, item.duration > 0 and item.duration or DealDuration())
        elseif item.itemType == TradeableItems.TRADE_ITEM_RESOURCES then
            deal:AddResourceTrade(fromID, item.data1, math.max(1, item.data2), item.duration > 0 and item.duration or DealDuration())
        end
    end
end

local function OfferMessage(offer)
    return "I have a trade proposal that I believe is fair to both of us."
end

local function QueueNativeOffer(offer)
    if offer == nil or Game.GetActivePlayer() ~= offer.humanID then return false end
    local active = Players[offer.humanID]
    if active == nil or not active:IsTurnActive() then return false end
    if Game.IsProcessingMessages ~= nil and Game.IsProcessingMessages() then return false end
    if UI.GetLeaderHeadRootUp ~= nil then
        local ok, up = pcall(function() return UI.GetLeaderHeadRootUp() end)
        if ok and up then return false end
    end

    g_pendingOffer = offer
    StateSet("NativeUIHeartbeat", "BEGIN_DIPLO")
    StateSet("LastShownAI", offer.aiID)
    StateSet("LastShownHuman", offer.humanID)
    StateSet("LastShownTurn", Game.GetGameTurn())
    StateSet("LastShownSeed", offer.seed or "")
    StateSet("LastShownSimpleAIGives", offer.aiGives or -1)
    StateSet("LastShownSimpleHumanGives", offer.humanGives or -1)

    local ok, err = pcall(function()
        Players[offer.aiID]:DoBeginDiploWithHuman()
    end)
    if not ok then
        StateSet("NativeUIHeartbeat", "BEGIN_DIPLO_ERROR")
        StateSet("NativeUIError", tostring(err))
        g_pendingOffer = nil
        return false
    end
    StateSet("NativeUIHeartbeat", "BEGIN_DIPLO_SENT")
    return true
end

local function OnAILeaderMessage(iPlayer, iDiploUIState, szLeaderMessage, iAnimationAction, iData1)
    local offer = g_pendingOffer
    if offer == nil then return end
    if iPlayer ~= offer.aiID or Game.GetActivePlayer() ~= offer.humanID then return end
    if iDiploUIState ~= DiploUIStateTypes.DIPLO_UI_STATE_DEFAULT_ROOT then return end

    local ok, err = pcall(function()
        Players[iPlayer]:DoTradeScreenOpened()
        UI.OnHumanOpenedTradeScreen(iPlayer)
        RebuildSnapshot(UI.GetScratchDeal(), offer)
        StateSet("NativeUIHeartbeat", "SCRATCH_DEAL_REBUILT")

        local anim = -1
        if LeaderheadAnimationTypes ~= nil then
            anim = LeaderheadAnimationTypes.LEADERHEAD_ANIM_REQUEST
                or LeaderheadAnimationTypes.LEADERHEAD_ANIM_NEUTRAL_HELLO
                or -1
        end

        Events.AILeaderMessage(
            iPlayer,
            DiploUIStateTypes.DIPLO_UI_STATE_TRADE_AI_MAKES_OFFER,
            OfferMessage(offer),
            anim,
            0
        )
        StateSet("NativeUIHeartbeat", "AI_OFFER_STATE_SENT")
    end)

    if not ok then
        StateSet("NativeUIHeartbeat", "NATIVE_UI_ERROR")
        StateSet("NativeUIError", tostring(err))
        CloseHeadlessTrade(iPlayer)
    end
    g_pendingOffer = nil
end
Events.AILeaderMessage.Add(OnAILeaderMessage)

local function TryAI(aiID, humanID, turn)
    local humanLux = SpareLuxuries(humanID, aiID)
    local aiLux = SpareLuxuries(aiID, humanID)
    StateSet("AI_" .. tostring(aiID) .. "_HumanLuxCount", #humanLux)
    StateSet("AI_" .. tostring(aiID) .. "_AILuxCount", #aiLux)

    local seedOffset = HashString(tostring(turn) .. "|" .. tostring(aiID) .. "|SEED")
    local attempts = 0

    local humanFirst = (seedOffset % 2) == 0
    local function tryList(seedFromHuman, list)
        local count = math.min(#list, MAX_LUXURY_SEEDS_PER_SIDE)
        if count <= 0 then return nil end
        local start = (seedOffset % #list) + 1
        for n = 0, count - 1 do
            if g_nativeCalls >= MAX_NATIVE_HELPER_CALLS_PER_TURN then break end
            local idx = ((start - 1 + n) % #list) + 1
            attempts = attempts + 1
            local offer, why = RunNativeSeed(aiID, humanID, seedFromHuman, list[idx])
            StateSet("AI_" .. tostring(aiID) .. "_LastSeedResult", why)
            if offer ~= nil then return offer end
        end
        return nil
    end

    local offer
    if humanFirst then
        offer = tryList(true, humanLux)
        if offer == nil then offer = tryList(false, aiLux) end
    else
        offer = tryList(false, aiLux)
        if offer == nil then offer = tryList(true, humanLux) end
    end
    StateSet("AI_" .. tostring(aiID) .. "_SeedAttempts", attempts)
    return offer
end

local function ScanForOffer()
    if not Game.IsNetworkMultiPlayer() then
        StateSet("OfferScanReason", "NOT_NETWORK_MULTIPLAYER")
        return
    end
    if g_pendingOffer ~= nil then
        StateSet("OfferScanReason", "OFFER_ALREADY_PENDING")
        return
    end

    local humanID = Game.GetActivePlayer()
    if not IsLivingHumanMajor(humanID) then
        StateSet("OfferScanReason", "ACTIVE_PLAYER_NOT_HUMAN_MAJOR")
        return
    end
    local human = Players[humanID]
    if human == nil or not human:IsTurnActive() then
        StateSet("OfferScanReason", "TURN_START_NOT_ACTIVE")
        return
    end
    if Game.IsProcessingMessages ~= nil and Game.IsProcessingMessages() then
        StateSet("OfferScanReason", "TURN_START_MESSAGE_QUEUE_BUSY_READY_SIGNAL_ARMED")
        StateSet("OfferRetryHeartbeat", "READY_SIGNAL_ARMED")
        g_retryArmed = true
        g_retryTurn = Game.GetGameTurn()
        g_retryHuman = humanID
        g_retrySignals = 0
        return
    end
    if UI.GetLeaderHeadRootUp ~= nil then
        local ok, up = pcall(function() return UI.GetLeaderHeadRootUp() end)
        if ok and up then
            StateSet("OfferScanReason", "LEADER_SCREEN_ALREADY_OPEN")
            return
        end
    end

    local turn = Game.GetGameTurn()
    if turn == g_lastScanTurn and humanID == g_lastScanHuman then
        StateSet("OfferScanReason", "ALREADY_SCANNED_THIS_TURN")
        return
    end
    g_lastScanTurn = turn
    g_lastScanHuman = humanID
    g_nativeCalls = 0

    StateSet("OfferScanTurn", turn)
    StateSet("OfferScanHuman", humanID)
    StateSet("OfferScanHeartbeat", "SCAN_STARTED")
    StateSet("NativeHelperBudget", MAX_NATIVE_HELPER_CALLS_PER_TURN)

    if turn - g_lastShownTurn < MIN_TURNS_BETWEEN_LOCAL_OFFERS then
        StateSet("OfferScanReason", "LOCAL_OFFER_COOLDOWN")
        return
    end

    local ais = EligibleAIs(humanID)
    StateSet("OfferScanEligibleAIs", #ais)
    if #ais == 0 then
        StateSet("OfferScanReason", "NO_ELIGIBLE_AI")
        return
    end

    local start = (HashString(tostring(turn) .. "|" .. tostring(humanID) .. "|AI") % #ais) + 1
    local due = 0
    for n = 0, #ais - 1 do
        if g_nativeCalls >= MAX_NATIVE_HELPER_CALLS_PER_TURN then break end
        local idx = ((start - 1 + n) % #ais) + 1
        local aiID = ais[idx]
        if RelationshipOfferDue(aiID, humanID, turn) then
            due = due + 1
            local offer = TryAI(aiID, humanID, turn)
            if offer ~= nil then
                StateSet("OfferScanReason", "FAIR_NATIVE_CANDIDATE_FOUND")
                StateSet("OfferNativeHelperCalls", g_nativeCalls)
                StateSet("OfferDueAIs", due)
                if QueueNativeOffer(offer) then
                    g_lastShownTurn = turn
                    StateSet("OfferScanReason", "NATIVE_OFFER_SENT")
                    return
                else
                    StateSet("OfferScanReason", "CANDIDATE_UI_NOT_SAFE")
                    return
                end
            end
        end
    end

    StateSet("OfferNativeHelperCalls", g_nativeCalls)
    StateSet("OfferDueAIs", due)
    if due == 0 then
        StateSet("OfferScanReason", "RELATIONSHIP_SCHEDULE_NOT_DUE")
    elseif g_nativeCalls >= MAX_NATIVE_HELPER_CALLS_PER_TURN then
        StateSet("OfferScanReason", "HELPER_BUDGET_REACHED_NO_VALID_DEAL")
    else
        StateSet("OfferScanReason", "NO_NATIVE_FAIR_SIMPLE_DEAL")
    end
end

-- LEK_FAIR_TRADES_TRANSIENT_READY_SIGNAL_V104_BEGIN
-- ActivePlayerTurnStart can fire while the MP message queue is still busy.
-- Instead of polling per frame, v1.0.4 temporarily subscribes to
-- SerialEventGameDataDirty only for that busy window. The callback performs no
-- deal search while the queue is busy. It removes itself immediately when the
-- queue becomes safe, or at ActivePlayerTurnEnd.
local OnTurnReadySignal

local function UnregisterTurnReadySignal(reason)
    if g_retryRegistered and Events.SerialEventGameDataDirty ~= nil then
        Events.SerialEventGameDataDirty.Remove(OnTurnReadySignal)
    end
    g_retryRegistered = false
    g_retryArmed = false
    if reason ~= nil then
        StateSet("OfferRetryHeartbeat", reason)
    end
end

OnTurnReadySignal = function()
    if not g_retryRegistered then return end
    g_retrySignals = g_retrySignals + 1
    StateSet("OfferRetrySignals", g_retrySignals)

    if not g_retryArmed then
        UnregisterTurnReadySignal("READY_SIGNAL_DISARMED")
        return
    end

    if Game.GetGameTurn() ~= g_retryTurn
        or Game.GetActivePlayer() ~= g_retryHuman then
        UnregisterTurnReadySignal("READY_SIGNAL_TURN_CHANGED")
        return
    end

    local human = Players[g_retryHuman]
    if human == nil or not human:IsTurnActive() then
        UnregisterTurnReadySignal("READY_SIGNAL_TURN_INACTIVE")
        return
    end

    if Game.IsProcessingMessages ~= nil and Game.IsProcessingMessages() then
        StateSet("OfferRetryHeartbeat", "READY_SIGNAL_STILL_BUSY")
        return
    end

    UnregisterTurnReadySignal("READY_SIGNAL_QUEUE_CLEARED")
    StateSet("OfferScanReason", "TURN_START_MESSAGE_QUEUE_CLEARED_READY_SIGNAL")
    ScanForOffer()
end

local function ArmTurnReadySignal()
    if not g_retryArmed or g_retryRegistered then return end
    if Events.SerialEventGameDataDirty == nil then
        StateSet("OfferScanReason", "READY_SIGNAL_EVENT_MISSING")
        StateSet("OfferRetryHeartbeat", "READY_SIGNAL_EVENT_MISSING")
        g_retryArmed = false
        return
    end
    Events.SerialEventGameDataDirty.Add(OnTurnReadySignal)
    g_retryRegistered = true
    StateSet("OfferRetryHeartbeat", "READY_SIGNAL_REGISTERED")
end

local function OnTurnStart()
    UnregisterTurnReadySignal(nil)
    g_retryTurn = -1
    g_retryHuman = -1
    g_retrySignals = 0

    ScanForOffer()
    if g_retryArmed then
        ArmTurnReadySignal()
    end
end

local function OnTurnEnd()
    if g_retryRegistered or g_retryArmed then
        UnregisterTurnReadySignal("READY_SIGNAL_CANCELLED_TURN_END")
    end
end

if Events.ActivePlayerTurnStart ~= nil then
    Events.ActivePlayerTurnStart.Add(OnTurnStart)
end
if Events.ActivePlayerTurnEnd ~= nil then
    Events.ActivePlayerTurnEnd.Add(OnTurnEnd)
end
-- LEK_FAIR_TRADES_TRANSIENT_READY_SIGNAL_V104_END

StateSet("Loaded", 1)
StateSet("RuntimeVersion", RUNTIME_VERSION)
StateSet("StateSchemaVersion", STATE_SCHEMA_VERSION)
StateSet("OfferEngine", "NATIVE_WHAT_WILL_GIVE_WHAT_DOES_WANT")
StateSet("AllowedItems", "LUXURY_GOLD_GPT_ONLY_V1")
StateSet("StrategicResources", "NEVER")
StateSet("HumanFairness", "AI_SIMPLE_VALUE_GTE_HUMAN_SIMPLE_VALUE")
StateSet("PerformanceModel", "ONE_TURN_SCAN_MAX_8_NATIVE_HELPERS_TRANSIENT_READY_SIGNAL")
StateSet("NativeUIBridge", "EVENT_ONLY_NO_EUI_FILE_PATCH")
StateSet("RelationshipModel", "LOOSER_FREQUENCY_NATIVE_PRICE")
StateSet("StartupPopupHidden", 1)
StateSet("RetryContext", "HIDDEN_EVENT_DRIVEN_CONTEXT_V104")

print("LEK Fair Trades v1.0.4: ready - native seed engine, transient turn-ready signal, max 8 helper calls/turn")
