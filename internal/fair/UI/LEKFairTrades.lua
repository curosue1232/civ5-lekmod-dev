-- LEKMOD 30.7 Fair Trades v1.1.3 SAFE ONE-SESSION NATIVE
-- Pick one AI without opening diplomacy, then open exactly one trade session.
-- Seed a spare luxury and let Civ V's own trade helper fill/equalize the deal.
-- If the native result is not a simple luxury/Gold/GPT deal, close silently.

print("LEK Fair Trades v1.1.3 SAFE ONE-SESSION NATIVE: loading")
ContextPtr:SetHide(true)
MapModData = MapModData or {}

local VERSION=113
local DB_VERSION=1
local MIN_OFFER_GAP=2
local MAX_HELPER_TRIES=3

-- LEK_FAIR_TRADES_ONE_SESSION_NATIVE_V113
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

S("RuntimePatch","V113_ONE_SESSION_NATIVE_HELPER")
S("OfferEngine","ONE_AI_ONE_SESSION_NATIVE_HELPER_V113")
S("AllowedItems","LUXURY_FLAT_GOLD_GPT_ONLY_V113")
S("StrategicResources","NEVER")
S("LuxuryCopyPolicy","BOTH_SIDES_PRESERVE_LAST_COPY")
S("CurrencyDirections","LUXURY_FOR_GOLD_OR_GPT_BOTH_WAYS")
S("TradeSessionPolicy","ONE_AI_SESSION_MAX_PER_TURN")
S("ScratchDealPolicy","NO_SNAPSHOT_REBUILD_SHOW_NATIVE_SCRATCH_IN_PLACE")
S("NativeHelperPolicy","HELPERS_ONLY_INSIDE_THE_ONE_SELECTED_AI_SESSION")
S("CustomValueMath","NONE")

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

-- Only proactive-offer luxuries that leave the seller with at least one copy.
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

local function Prep(d,h,ai)
  d:ClearItems()
  d:SetFromPlayer(h)
  d:SetToPlayer(ai)
end

local function PossibleLux(d,from,to,res)
  local ok,v=pcall(function()
    return d:IsPossibleToTradeItem(from,to,TradeableItems.TRADE_ITEM_RESOURCES,res,1)
  end)
  return ok and v==true
end

local function AddLuxSeed(d,from,to,res)
  if not PossibleLux(d,from,to,res) then return false end
  d:AddResourceTrade(from,res,1,Duration())
  return true
end

local function CloseSession(ai)
  pcall(function() Players[ai]:DoTradeScreenClosed(false) end)
end

local function Snapshot(d)
  local a={}
  d:ResetIterator()
  while true do
    local x={d:GetNextItem()}
    local n=#x
    if n<1 or x[1]==nil then break end
    table.insert(a,{
      itemType=x[1],
      duration=x[2] or 0,
      data1=x[4] or 0,
      data2=x[5] or 0,
      fromPlayer=x[n]
    })
  end
  return a
end

-- Validate the native helper result in place. We never rebuild it afterward.
-- Allowed:
--   * luxury <-> luxury, optionally with Gold OR GPT as a sweetener
--   * luxury <-> flat Gold
--   * luxury <-> GPT
-- No strategics, treaties, cities, third parties, or last-copy luxuries.
local function ValidateNativeDeal(d,ai,h)
  local items=Snapshot(d)
  if #items==0 then return false,"EMPTY_NATIVE_DEAL" end

  local luxAI,luxH=0,0
  local goldAI,goldH=0,0
  local gptAI,gptH=0,0
  local other=0

  for _,x in ipairs(items) do
    if x.fromPlayer~=ai and x.fromPlayer~=h then
      return false,"THIRD_PARTY_NATIVE_ITEM"
    end

    if x.itemType==TradeableItems.TRADE_ITEM_RESOURCES then
      if not Luxury(x.data1) then return false,"UNSUPPORTED_NATIVE_RESOURCE" end
      local q=math.max(1,x.data2 or 1)
      local p=Players[x.fromPlayer]
      if not p or (p:GetNumResourceAvailable(x.data1,true) or 0)<=q then
        return false,"NATIVE_HELPER_USED_LAST_LUXURY"
      end
      if x.fromPlayer==ai then luxAI=luxAI+1 else luxH=luxH+1 end

    elseif x.itemType==TradeableItems.TRADE_ITEM_GOLD then
      local amt=math.max(0,x.data1 or 0)
      if amt<=0 then return false,"ZERO_GOLD_NATIVE_ITEM" end
      if x.fromPlayer==ai then goldAI=goldAI+1 else goldH=goldH+1 end

    elseif x.itemType==TradeableItems.TRADE_ITEM_GOLD_PER_TURN then
      local amt=math.max(0,x.data1 or 0)
      if amt<=0 then return false,"ZERO_GPT_NATIVE_ITEM" end
      if x.fromPlayer==ai then gptAI=gptAI+1 else gptH=gptH+1 end

    else
      other=other+1
    end
  end

  if other>0 then return false,"UNSUPPORTED_NATIVE_ITEM" end
  if luxAI+luxH==0 then return false,"NO_LUXURY_IN_NATIVE_DEAL" end
  if luxAI>1 or luxH>1 then return false,"TOO_MANY_LUXURIES" end

  -- Keep offers easy to read: native result may use flat Gold OR GPT, not both.
  local goldKinds=(goldAI+goldH>0 and 1 or 0)+(gptAI+gptH>0 and 1 or 0)
  if goldKinds>1 then return false,"MIXED_GOLD_AND_GPT" end
  if goldAI+goldH>1 or gptAI+gptH>1 then return false,"MULTIPLE_CURRENCY_ITEMS" end

  local aiHas=luxAI+goldAI+gptAI
  local hHas=luxH+goldH+gptH
  if aiHas==0 or hHas==0 then return false,"ONE_SIDED_NATIVE_DEAL" end

  local shape
  if luxAI==1 and luxH==1 then
    if goldAI+goldH+gptAI+gptH>0 then shape="LUX_SWAP_PLUS_CURRENCY"
    else shape="LUXURY_FOR_LUXURY" end
  elseif luxH==1 and luxAI==0 and (goldAI+gptAI)==1 and goldH+gptH==0 then
    shape=(goldAI==1) and "HUMAN_LUX_FOR_AI_GOLD" or "HUMAN_LUX_FOR_AI_GPT"
  elseif luxAI==1 and luxH==0 and (goldH+gptH)==1 and goldAI+gptAI==0 then
    shape=(goldH==1) and "AI_LUX_FOR_HUMAN_GOLD" or "AI_LUX_FOR_HUMAN_GPT"
  else
    return false,"UNSUPPORTED_SIMPLE_SHAPE"
  end

  return true,shape
end

local function PickRes(list,seed)
  if not list or #list==0 then return nil end
  return list[(Hash(seed)%#list)+1]
end

local function NativeHelper(name)
  local ok=false
  if name=="WILL_GIVE" and UI.DoWhatWillAIGive then
    ok=pcall(UI.DoWhatWillAIGive)
  elseif name=="WANTS" and UI.DoWhatDoesAIWant then
    ok=pcall(UI.DoWhatDoesAIWant)
  elseif name=="EQUALIZE" and UI.DoEqualizeDealWithHuman then
    ok=pcall(UI.DoEqualizeDealWithHuman)
  end
  S("LastNativeHelper",name)
  return ok
end

local function TrySeed(d,ai,h,kind,resA,resB)
  Prep(d,h,ai)

  if kind=="HUMAN_SELLS" then
    if not AddLuxSeed(d,h,ai,resA) then return false,"HUMAN_LUX_SEED_NOT_POSSIBLE" end
    if not NativeHelper("WILL_GIVE") then return false,"WHAT_WILL_AI_GIVE_FAILED" end

  elseif kind=="AI_SELLS" then
    if not AddLuxSeed(d,ai,h,resA) then return false,"AI_LUX_SEED_NOT_POSSIBLE" end
    if not NativeHelper("WANTS") then return false,"WHAT_DOES_AI_WANT_FAILED" end

  elseif kind=="SWAP" then
    if not AddLuxSeed(d,h,ai,resA) then return false,"HUMAN_SWAP_SEED_NOT_POSSIBLE" end
    if not AddLuxSeed(d,ai,h,resB) then return false,"AI_SWAP_SEED_NOT_POSSIBLE" end
    if not NativeHelper("EQUALIZE") then
      -- A raw 1-for-1 swap may already be usable even if equalize is unavailable.
      S("LastNativeHelper","RAW_SWAP")
    end
  else
    return false,"UNKNOWN_SEED_KIND"
  end

  local valid,shape=ValidateNativeDeal(d,ai,h)
  if valid then return true,shape end

  -- One bounded fallback inside the same AI session. This never opens another
  -- diplomacy session and never rebuilds a successful helper result.
  if kind~="SWAP" and UI.DoEqualizeDealWithHuman then
    S("LastNativeReject",shape)
    if NativeHelper("EQUALIZE") then
      valid,shape=ValidateNativeDeal(d,ai,h)
      if valid then return true,shape end
    end
  end

  return false,shape
end

local function SeedOrder(ai,h,turn,hl,al)
  local a={}
  if #hl>0 then table.insert(a,"HUMAN_SELLS") end
  if #al>0 then table.insert(a,"AI_SELLS") end
  if #hl>0 and #al>0 then table.insert(a,"SWAP") end
  if #a<=1 then return a end
  local start=(Hash(turn.."|"..h.."|"..ai.."|SEED_ORDER")%#a)+1
  local out={}
  for n=0,#a-1 do table.insert(out,a[((start-1+n)%#a)+1]) end
  return out
end

local function FindOneAI(h,turn)
  local ais={}
  for ai=0,GameDefines.MAX_MAJOR_CIVS-1 do
    if CanTrade(ai,h) then table.insert(ais,ai) end
  end
  table.sort(ais)
  S("OfferScanEligibleAIs",#ais)
  if #ais==0 then return nil,"NO_ELIGIBLE_AI" end

  local start=(Hash(turn.."|"..h.."|AI")%#ais)+1
  local due=0

  for n=0,#ais-1 do
    local ai=ais[((start-1+n)%#ais)+1]
    if Due(ai,h,turn) then
      due=due+1
      local hl=SpareLux(h,ai)
      local al=SpareLux(ai,h)
      S("AI_"..ai.."_HumanSpareLuxCount",#hl)
      S("AI_"..ai.."_AISpareLuxCount",#al)
      if #hl>0 or #al>0 then
        S("OfferDueAIs",due)
        return {ai=ai,hl=hl,al=al},"OK"
      end
    end
  end

  S("OfferDueAIs",due)
  if due==0 then return nil,"RELATIONSHIP_SCHEDULE_NOT_DUE" end
  return nil,"NO_DUE_AI_WITH_SPARE_LUXURY"
end

local function ShowOneNativeOffer(seed,h,turn)
  local ai=seed.ai
  if Game.GetActivePlayer()~=h or not Players[h]:IsTurnActive() then return false,"HUMAN_TURN_NOT_ACTIVE" end
  if Game.IsProcessingMessages and Game.IsProcessingMessages() then return false,"MESSAGE_QUEUE_BUSY" end
  if UI.GetLeaderHeadRootUp then
    local ok,up=pcall(UI.GetLeaderHeadRootUp)
    if ok and up then return false,"LEADER_SCREEN_ALREADY_OPEN" end
  end

  -- Re-read spare lists immediately before the one session opens.
  local hl=SpareLux(h,ai)
  local al=SpareLux(ai,h)
  if #hl==0 and #al==0 then return false,"NO_LONGER_HAS_SPARE_LUXURY" end

  S("NativeUIHeartbeat","ONE_SESSION_OPEN_BEGIN")
  local opened=false
  local success=false
  local finalShape=""
  local failWhy="NO_NATIVE_SIMPLE_DEAL"

  local ok,e=pcall(function()
    Players[ai]:DoTradeScreenOpened()
    UI.OnHumanOpenedTradeScreen(ai)
    opened=true

    local d=UI.GetScratchDeal()
    local order=SeedOrder(ai,h,turn,hl,al)
    local tries=0

    for _,kind in ipairs(order) do
      if tries>=MAX_HELPER_TRIES then break end
      tries=tries+1
      S("NativeHelperTries",tries)

      local r1,r2=nil,nil
      if kind=="HUMAN_SELLS" then
        r1=PickRes(hl,turn.."|"..ai.."|HS")
      elseif kind=="AI_SELLS" then
        r1=PickRes(al,turn.."|"..ai.."|AS")
      else
        r1=PickRes(hl,turn.."|"..ai.."|SH")
        r2=PickRes(al,turn.."|"..ai.."|SA")
      end

      local valid,why=TrySeed(d,ai,h,kind,r1,r2)
      S("AI_"..ai.."_LastSeedKind",kind)
      S("AI_"..ai.."_LastSeedResult",why or "")
      failWhy=why or failWhy

      if valid then
        success=true
        finalShape=why or "NATIVE_SIMPLE_DEAL"
        break
      end
    end

    if not success then return end

    S("LastShownAI",ai)
    S("LastShownTurn",Game.GetGameTurn())
    S("LastShownShape",finalShape)
    S("NativeUIHeartbeat","ONE_SESSION_NATIVE_SCRATCH_READY")

    -- Important: show the exact scratch deal the native helper produced.
    -- Do not snapshot/rebuild it; that was the source of stale/mismatched UI.
    Events.AILeaderMessage(
      ai,
      DiploUIStateTypes.DIPLO_UI_STATE_TRADE_AI_MAKES_OFFER,
      "I have a trade proposal that I believe is fair to both of us.",
      -1,0
    )
  end)

  if not ok then
    S("NativeUIHeartbeat","ONE_SESSION_ERROR")
    S("NativeUIError",tostring(e))
    if opened then CloseSession(ai) end
    return false,tostring(e)
  end

  if not success then
    S("LastNativeReject",failWhy)
    if opened then CloseSession(ai) end
    S("NativeUIHeartbeat","ONE_SESSION_CLOSED_NO_SIMPLE_DEAL")
    return false,failWhy
  end

  S("NativeUIHeartbeat","ONE_SESSION_OFFER_SENT")
  return true,"OK"
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

  S("NativeHelperTries",0)
  local seed,why=FindOneAI(h,turn)
  if not seed then Reason(why); return end

  -- Exactly one AI session is opened. If its native helper cannot produce an
  -- allowed simple deal, stop for this turn instead of touching another AI.
  local shown,showWhy=ShowOneNativeOffer(seed,h,turn)
  if shown then
    lastShownTurn=turn
    Reason("DIRECT_ONE_SESSION_NATIVE_OFFER_SENT")
  else
    S("LastShowReject",showWhy or "")
    Reason("ONE_SELECTED_AI_NO_SIMPLE_NATIVE_DEAL")
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
S("PerformanceModel","ONE_AI_SESSION_MAX_THREE_NATIVE_HELPER_TRIES_NO_CUSTOM_VALUE_LOOPS")
S("RelationshipModel","GUARDED_5_NEUTRAL_3_FRIENDLY_AFRAID_2")
print("LEK Fair Trades v1.1.3 SAFE ONE-SESSION NATIVE: ready")
