-- LEKMOD 30.7 Fair Trades v1.1.1 SAFE SWAP
-- Deliberately simple: find one spare luxury-for-luxury swap, then open exactly
-- one native trade session and build the scratch deal fresh inside that session.

print("LEK Fair Trades v1.1.1 SAFE SWAP: loading")
ContextPtr:SetHide(true)
MapModData = MapModData or {}

local VERSION=111
local DB_VERSION=1
local MIN_OFFER_GAP=2

-- LEK_FAIR_TRADES_SAFE_SWAP_V111
if MapModData.LEK_FAIR_TRADES_RUNTIME_VERSION==VERSION then return end
MapModData.LEK_FAIR_TRADES_RUNTIME_VERSION=VERSION

local db=nil
pcall(function() db=Modding.OpenUserData("LEK_FAIR_TRADES",DB_VERSION) end)
local function S(k,v) if db then pcall(function() db.SetValue(k,v) end) end end
local function Reason(r)
  S("OfferScanReason",r)
  local t,h=-1,-1
  pcall(function() t=Game.GetGameTurn() end)
  pcall(function() h=Game.GetActivePlayer() end)
  S("OfferScanTurn",t)
  S("OfferScanHuman",h)
end

S("RuntimePatch","V111_SAFE_SPARE_LUX_SWAP")
S("OfferEngine","DIRECT_SPARE_LUX_SWAP_V111")
S("AllowedItems","SPARE_LUXURY_SWAP_ONLY_V111")
S("StrategicResources","NEVER")
S("LuxuryCopyPolicy","BOTH_SIDES_PRESERVE_LAST_COPY")
S("TradeSessionPolicy","OPEN_EXACTLY_ONE_SESSION_AFTER_CANDIDATE_CHOSEN")
S("ScratchDealPolicy","BUILD_FRESH_AFTER_ON_HUMAN_OPENED_TRADE_SCREEN")
S("NativeHelperPolicy","NO_WHAT_WILL_AI_GIVE_NO_EQUALIZER")

local lastScanTurn=-99999
local lastScanHuman=-1
local lastShownTurn=-99999
local retryArmed=false
local retryRegistered=false
local retryTurn=-1
local retryHuman=-1

local function Duration()
  local d=Game.GetDealDuration()
  if not d or d<=0 then d=30 end
  return d
end

local function Luxury(id)
  return id~=nil and Game.GetResourceUsageType(id)==ResourceUsageTypes.RESOURCEUSAGE_LUXURY
end

local function HumanMajor(id)
  local p=Players[id]
  return p and p:IsAlive() and p:IsHuman() and not p:IsMinorCiv() and not p:IsBarbarian()
end

local function AIMajor(id)
  local p=Players[id]
  return p and p:IsAlive() and not p:IsHuman() and not p:IsMinorCiv() and not p:IsBarbarian()
end

local function Hash(x)
  x=tostring(x or "")
  local h=104729
  for i=1,#x do h=(h*131+string.byte(x,i))%2147483629 end
  return h
end

local function CanTrade(ai,h)
  if not AIMajor(ai) or not HumanMajor(h) then return false end
  local ap,hp=Players[ai],Players[h]
  local team=Teams[ap:GetTeam()]
  if not team:IsHasMet(hp:GetTeam()) or team:IsAtWar(hp:GetTeam()) then return false end
  if ap.IsTradeSanctioned then
    local ok,v=pcall(function() return ap:IsTradeSanctioned(h) end)
    if ok and v then return false end
  end
  return true
end

local function Approach(ai,h)
  local p=Players[ai]
  if p and p.GetMajorCivApproach then
    local ok,v=pcall(function() return p:GetMajorCivApproach(h) end)
    if ok and v~=nil then return v end
  end
  return MajorCivApproachTypes.MAJOR_CIV_APPROACH_NEUTRAL
end

local function Due(ai,h,turn)
  local a=Approach(ai,h)
  local T=MajorCivApproachTypes
  if a==T.MAJOR_CIV_APPROACH_WAR or a==T.MAJOR_CIV_APPROACH_HOSTILE or a==T.MAJOR_CIV_APPROACH_DECEPTIVE then
    return false
  end
  local n=(a==T.MAJOR_CIV_APPROACH_GUARDED and 5)
       or ((a==T.MAJOR_CIV_APPROACH_FRIENDLY or a==T.MAJOR_CIV_APPROACH_AFRAID) and 2)
       or 3
  return ((turn+(Hash(ai.."|"..h.."|REL")%n))%n)==0
end

-- Both sides need at least two available copies. This prevents either civ from
-- proactively offering its final copy of a luxury.
local function SpareLux(from,to)
  local a={}
  local p,o=Players[from],Players[to]
  if not p or not o then return a end
  for r in GameInfo.Resources() do
    if Luxury(r.ID)
      and (p:GetNumResourceAvailable(r.ID,true) or 0)>=2
      and (o:GetNumResourceAvailable(r.ID,true) or 0)<=0 then
      table.insert(a,r.ID)
    end
  end
  table.sort(a)
  return a
end

local function Possible(d,from,to,item,a,b)
  local ok,v=pcall(function() return d:IsPossibleToTradeItem(from,to,item,a or 0,b or 0) end)
  return ok and v==true
end

local function Prep(d,h,ai)
  d:ClearItems()
  d:SetFromPlayer(h)
  d:SetToPlayer(ai)
end

local function CloseSession(ai)
  pcall(function() Players[ai]:DoTradeScreenClosed(false) end)
end

local function ShowSwap(ai,h,humanRes,aiRes)
  if Game.GetActivePlayer()~=h or not Players[h]:IsTurnActive() then return false,"HUMAN_TURN_NOT_ACTIVE" end
  if Game.IsProcessingMessages and Game.IsProcessingMessages() then return false,"MESSAGE_QUEUE_BUSY" end
  if UI.GetLeaderHeadRootUp then
    local ok,up=pcall(UI.GetLeaderHeadRootUp)
    if ok and up then return false,"LEADER_SCREEN_ALREADY_OPEN" end
  end

  -- Re-check copies immediately before opening the only trade session.
  if (Players[h]:GetNumResourceAvailable(humanRes,true) or 0)<2 then return false,"HUMAN_NO_LONGER_HAS_SPARE" end
  if (Players[ai]:GetNumResourceAvailable(aiRes,true) or 0)<2 then return false,"AI_NO_LONGER_HAS_SPARE" end

  S("NativeUIHeartbeat","ONE_SESSION_OPEN_BEGIN")
  local ok,e=pcall(function()
    Players[ai]:DoTradeScreenOpened()
    UI.OnHumanOpenedTradeScreen(ai)

    -- Build from scratch only after Civ V has initialized this AI's trade session.
    -- No snapshot/rebuild and no helper calls means no stale deal from another AI.
    local d=UI.GetScratchDeal()
    Prep(d,h,ai)
    if not Possible(d,h,ai,TradeableItems.TRADE_ITEM_RESOURCES,humanRes,1) then error("HUMAN_LUX_NOT_POSSIBLE") end
    if not Possible(d,ai,h,TradeableItems.TRADE_ITEM_RESOURCES,aiRes,1) then error("AI_LUX_NOT_POSSIBLE") end
    d:AddResourceTrade(h,humanRes,1,Duration())
    d:AddResourceTrade(ai,aiRes,1,Duration())

    S("LastShownAI",ai)
    S("LastShownTurn",Game.GetGameTurn())
    S("LastShownHumanLuxury",humanRes)
    S("LastShownAILuxury",aiRes)
    S("NativeUIHeartbeat","ONE_SESSION_SCRATCH_READY")

    Events.AILeaderMessage(
      ai,
      DiploUIStateTypes.DIPLO_UI_STATE_TRADE_AI_MAKES_OFFER,
      "I have a trade proposal that I believe is fair to both of us.",
      -1,0
    )
  end)

  if not ok then
    S("NativeUIHeartbeat","ONE_SESSION_OPEN_ERROR")
    S("NativeUIError",tostring(e))
    CloseSession(ai)
    return false,tostring(e)
  end

  S("NativeUIHeartbeat","ONE_SESSION_OFFER_SENT")
  return true,"OK"
end

local function FindCandidate(h,turn)
  local ais={}
  for ai=0,GameDefines.MAX_MAJOR_CIVS-1 do
    if CanTrade(ai,h) then table.insert(ais,ai) end
  end
  table.sort(ais)
  S("OfferScanEligibleAIs",#ais)
  if #ais==0 then return nil,"NO_ELIGIBLE_AI" end

  local start=(Hash(turn.."|"..h.."|AI")%#ais)+1
  local due=0
  local sparePairAIs=0

  for n=0,#ais-1 do
    local ai=ais[((start-1+n)%#ais)+1]
    if Due(ai,h,turn) then
      due=due+1
      local hl=SpareLux(h,ai)
      local al=SpareLux(ai,h)
      S("AI_"..ai.."_HumanSpareLuxCount",#hl)
      S("AI_"..ai.."_AISpareLuxCount",#al)
      if #hl>0 and #al>0 then
        sparePairAIs=sparePairAIs+1
        local seed=Hash(turn.."|"..h.."|"..ai.."|PAIR")
        local hr=hl[(seed%#hl)+1]
        local ar=al[((math.floor(seed/17))%#al)+1]
        S("OfferDueAIs",due)
        S("OfferSparePairAIs",sparePairAIs)
        return {ai=ai,humanRes=hr,aiRes=ar},"OK"
      end
    end
  end

  S("OfferDueAIs",due)
  S("OfferSparePairAIs",sparePairAIs)
  if due==0 then return nil,"RELATIONSHIP_SCHEDULE_NOT_DUE" end
  return nil,"NO_MUTUAL_SPARE_LUXURY_SWAP"
end

local function Scan()
  if not Game.IsNetworkMultiPlayer() then Reason("NOT_NETWORK_MULTIPLAYER"); return end
  local h=Game.GetActivePlayer()
  if not HumanMajor(h) then Reason("ACTIVE_PLAYER_NOT_HUMAN_MAJOR"); return end
  if not Players[h]:IsTurnActive() then Reason("TURN_START_NOT_ACTIVE"); return end
  if Game.IsProcessingMessages and Game.IsProcessingMessages() then
    Reason("TURN_START_MESSAGE_QUEUE_BUSY_READY_SIGNAL_ARMED")
    retryArmed=true
    retryTurn=Game.GetGameTurn()
    retryHuman=h
    return
  end
  if UI.GetLeaderHeadRootUp then
    local ok,up=pcall(UI.GetLeaderHeadRootUp)
    if ok and up then Reason("LEADER_SCREEN_ALREADY_OPEN"); return end
  end

  local turn=Game.GetGameTurn()
  if turn==lastScanTurn and h==lastScanHuman then Reason("ALREADY_SCANNED_THIS_TURN"); return end
  lastScanTurn,lastScanHuman=turn,h
  if turn-lastShownTurn<MIN_OFFER_GAP then Reason("LOCAL_OFFER_COOLDOWN"); return end

  local c,why=FindCandidate(h,turn)
  if not c then Reason(why); return end

  -- Exactly one trade session can be opened in a scan. If this candidate cannot
  -- be shown, stop for this turn rather than probing another AI and queuing UI.
  local shown,showWhy=ShowSwap(c.ai,h,c.humanRes,c.aiRes)
  if shown then
    lastShownTurn=turn
    Reason("DIRECT_SAFE_LUXURY_SWAP_SENT")
  else
    S("LastShowReject",showWhy or "")
    Reason("SINGLE_CANDIDATE_UI_FAILED")
  end
end

local Ready
local function RemoveRetry()
  if retryRegistered and Events.SerialEventGameDataDirty then
    Events.SerialEventGameDataDirty.Remove(Ready)
  end
  retryRegistered=false
  retryArmed=false
end

Ready=function()
  if not retryRegistered then return end
  if Game.GetGameTurn()~=retryTurn or Game.GetActivePlayer()~=retryHuman then RemoveRetry(); return end
  if not Players[retryHuman] or not Players[retryHuman]:IsTurnActive() then RemoveRetry(); return end
  if Game.IsProcessingMessages and Game.IsProcessingMessages() then return end
  RemoveRetry()
  Reason("TURN_START_MESSAGE_QUEUE_CLEARED_READY_SIGNAL")
  Scan()
end

local function Start()
  RemoveRetry()
  retryTurn,retryHuman=-1,-1
  Scan()
  if retryArmed then
    if not Events.SerialEventGameDataDirty then Reason("READY_SIGNAL_EVENT_MISSING"); retryArmed=false; return end
    Events.SerialEventGameDataDirty.Add(Ready)
    retryRegistered=true
    S("OfferRetryHeartbeat","READY_SIGNAL_REGISTERED")
  end
end

local function Finish()
  if retryRegistered or retryArmed then RemoveRetry() end
end

Events.ActivePlayerTurnStart.Add(Start)
if Events.ActivePlayerTurnEnd then Events.ActivePlayerTurnEnd.Add(Finish) end

S("Loaded",1)
S("RuntimeVersion",VERSION)
S("StateSchemaVersion",DB_VERSION)
S("PerformanceModel","NO_NATIVE_VALUE_LOOPS_NO_HELPER_LOOPS_ONE_UI_SESSION_MAX_PER_TURN")
S("RelationshipModel","GUARDED_5_NEUTRAL_3_FRIENDLY_AFRAID_2")
print("LEK Fair Trades v1.1.1 SAFE SWAP: ready")
