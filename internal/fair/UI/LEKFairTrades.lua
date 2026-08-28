-- LEKMOD 30.7 Fair Trades v1.1.0 SIMPLE NATIVE
-- Keep this small: seed a useful luxury trade and let Civ V build the price.

print("LEK Fair Trades v1.1.0 SIMPLE NATIVE: loading")
ContextPtr:SetHide(true)
MapModData = MapModData or {}

local VERSION=110
local MAX_ATTEMPTS=4
local MIN_OFFER_GAP=2

-- LEK_FAIR_TRADES_SIMPLE_NATIVE_V110
if MapModData.LEK_FAIR_TRADES_RUNTIME_VERSION==VERSION then return end
MapModData.LEK_FAIR_TRADES_RUNTIME_VERSION=VERSION

local db=nil
pcall(function() db=Modding.OpenUserData("LEK_FAIR_TRADES",1) end)
local function S(k,v) if db then pcall(function() db.SetValue(k,v) end) end end
local function Reason(r)
  S("OfferScanReason",r)
  S("OfferScanTurn",Game.GetGameTurn())
  S("OfferScanHuman",Game.GetActivePlayer())
end

S("RuntimePatch","V110_SIMPLE_NATIVE_EQUALIZER")
S("OfferEngine","SEED_THEN_NATIVE_HELPER_V110")
S("AllowedItems","LUXURY_GOLD_GPT_ONLY_V110")
S("StrategicResources","NEVER")
S("HumanLuxuryOfferPolicy","PRESERVE_LAST_COPY")
S("NativeBuildAttempts",0)

local lastScanTurn=-1
local lastShownTurn=-9999
local attempts=0
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

local function Due(ai,h,turn)
  local a=MajorCivApproachTypes.MAJOR_CIV_APPROACH_NEUTRAL
  if Players[ai].GetMajorCivApproach then
    local ok,v=pcall(function() return Players[ai]:GetMajorCivApproach(h) end)
    if ok and v~=nil then a=v end
  end
  local T=MajorCivApproachTypes
  if a==T.MAJOR_CIV_APPROACH_WAR or a==T.MAJOR_CIV_APPROACH_HOSTILE or a==T.MAJOR_CIV_APPROACH_DECEPTIVE then return false end
  local n=(a==T.MAJOR_CIV_APPROACH_GUARDED and 5)
       or ((a==T.MAJOR_CIV_APPROACH_FRIENDLY or a==T.MAJOR_CIV_APPROACH_AFRAID) and 2)
       or 3
  return ((turn+(Hash(ai.."|"..h.."|REL")%n))%n)==0
end

local function OfferableLux(from,to,preserveLast)
  local a={}
  local minOwned=preserveLast and 2 or 1
  for r in GameInfo.Resources() do
    if Luxury(r.ID)
      and (Players[from]:GetNumResourceAvailable(r.ID,true) or 0)>=minOwned
      and (Players[to]:GetNumResourceAvailable(r.ID,true) or 0)<=0 then
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

local function Possible(d,from,to,item,a,b)
  local ok,v=pcall(function() return d:IsPossibleToTradeItem(from,to,item,a or 0,b or 0) end)
  return ok and v==true
end

local function Snapshot(d)
  local out={}
  d:ResetIterator()
  while true do
    local x={d:GetNextItem()}
    local n=#x
    if n<1 or x[1]==nil then break end
    table.insert(out,{itemType=x[1],duration=x[2] or 0,data1=x[4] or 0,data2=x[5] or 0,fromPlayer=x[n]})
  end
  return out
end

local function SafeDeal(items,ai,h)
  if not items or #items==0 then return false,"EMPTY_DEAL" end
  local aiGives,hGives=0,0
  for _,x in ipairs(items) do
    if x.fromPlayer~=ai and x.fromPlayer~=h then return false,"THIRD_PARTY_ITEM" end
    if x.itemType==TradeableItems.TRADE_ITEM_RESOURCES then
      if not Luxury(x.data1) then return false,"NON_LUXURY_RESOURCE" end
      local q=math.max(1,x.data2 or 1)
      if x.fromPlayer==h and (Players[h]:GetNumResourceAvailable(x.data1,true) or 0)<=q then
        return false,"HUMAN_LAST_LUXURY_COPY"
      end
    elseif x.itemType~=TradeableItems.TRADE_ITEM_GOLD and x.itemType~=TradeableItems.TRADE_ITEM_GOLD_PER_TURN then
      return false,"UNSUPPORTED_NATIVE_ITEM"
    end
    if x.fromPlayer==ai then aiGives=aiGives+1 else hGives=hGives+1 end
  end
  if aiGives==0 or hGives==0 then return false,"ONE_SIDED_DEAL" end
  return true,"OK"
end

local function Rebuild(d,o)
  Prep(d,o.humanID,o.aiID)
  for _,x in ipairs(o.items) do
    if x.itemType==TradeableItems.TRADE_ITEM_GOLD then
      d:AddGoldTrade(x.fromPlayer,x.data1)
    elseif x.itemType==TradeableItems.TRADE_ITEM_GOLD_PER_TURN then
      d:AddGoldPerTurnTrade(x.fromPlayer,x.data1,x.duration>0 and x.duration or Duration())
    elseif x.itemType==TradeableItems.TRADE_ITEM_RESOURCES then
      d:AddResourceTrade(x.fromPlayer,x.data1,math.max(1,x.data2),x.duration>0 and x.duration or Duration())
    end
  end
end

local function OpenTrade(ai)
  local ok,e=pcall(function()
    Players[ai]:DoTradeScreenOpened()
    UI.OnHumanOpenedTradeScreen(ai)
  end)
  if not ok then S("NativeUIError",tostring(e)) end
  return ok
end

local function CloseTrade(ai)
  pcall(function() Players[ai]:DoTradeScreenClosed(false) end)
end

local function NativeBuild(fromHuman)
  local helper="NONE"
  local ok=false
  if fromHuman and UI.DoWhatWillAIGive then
    helper="DoWhatWillAIGive"
    ok=pcall(UI.DoWhatWillAIGive)
  elseif (not fromHuman) and UI.DoWhatDoesAIWant then
    helper="DoWhatDoesAIWant"
    ok=pcall(UI.DoWhatDoesAIWant)
  end
  if not ok and UI.DoEqualizeDealWithHuman then
    helper="DoEqualizeDealWithHuman"
    ok=pcall(UI.DoEqualizeDealWithHuman)
  end
  S("LastNativeHelper",helper)
  return ok,helper
end

local function SeedAndBuild(ai,h,fromHuman,res)
  if attempts>=MAX_ATTEMPTS then return nil,"ATTEMPT_BUDGET" end
  attempts=attempts+1
  S("NativeBuildAttempts",attempts)

  local d=UI.GetScratchDeal()
  Prep(d,h,ai)
  local from=fromHuman and h or ai
  local to=fromHuman and ai or h
  if not Possible(d,from,to,TradeableItems.TRADE_ITEM_RESOURCES,res,1) then return nil,"SEED_NOT_POSSIBLE" end
  d:AddResourceTrade(from,res,1,Duration())

  local ran,helper=NativeBuild(fromHuman)
  if not ran then return nil,"NATIVE_HELPER_FAILED" end

  local items=Snapshot(d)
  local valid,why=SafeDeal(items,ai,h)
  if not valid and helper~="DoEqualizeDealWithHuman" and UI.DoEqualizeDealWithHuman then
    if pcall(UI.DoEqualizeDealWithHuman) then
      items=Snapshot(d)
      valid,why=SafeDeal(items,ai,h)
    end
  end
  if not valid then return nil,why end
  return {aiID=ai,humanID=h,items=items,helper=helper},"OK"
end

local function TryAI(ai,h,turn)
  local humanLux=OfferableLux(h,ai,true)
  local aiLux=OfferableLux(ai,h,false)
  S("AI_"..ai.."_HumanLuxCount",#humanLux)
  S("AI_"..ai.."_AILuxCount",#aiLux)
  if #humanLux==0 and #aiLux==0 then return nil,"NO_LUXURY_SEED" end
  if not OpenTrade(ai) then return nil,"TRADE_OPEN_FAILED" end

  local firstHuman=(Hash(turn.."|"..ai.."|DIR")%2)==0
  local function TryList(fromHuman,list)
    local count=math.min(#list,2)
    if count==0 then return nil end
    local start=(Hash(turn.."|"..ai.."|"..tostring(fromHuman))%#list)+1
    for k=0,count-1 do
      if attempts>=MAX_ATTEMPTS then break end
      local res=list[((start-1+k)%#list)+1]
      local o,why=SeedAndBuild(ai,h,fromHuman,res)
      if o then return o,"OK" end
      S("AI_"..ai.."_LastReject",why)
    end
    return nil,"NO_NATIVE_DEAL"
  end

  local o,why
  if firstHuman then
    o,why=TryList(true,humanLux)
    if not o then o,why=TryList(false,aiLux) end
  else
    o,why=TryList(false,aiLux)
    if not o then o,why=TryList(true,humanLux) end
  end
  if not o then CloseTrade(ai) end
  return o,why
end

local function Show(o)
  if not o or Game.GetActivePlayer()~=o.humanID or not Players[o.humanID]:IsTurnActive() then return false end
  if Game.IsProcessingMessages and Game.IsProcessingMessages() then return false end
  if UI.GetLeaderHeadRootUp then
    local ok,up=pcall(UI.GetLeaderHeadRootUp)
    if ok and up then return false end
  end

  Rebuild(UI.GetScratchDeal(),o)
  S("LastShownAI",o.aiID)
  S("LastShownTurn",Game.GetGameTurn())
  S("LastShownNativeHelper",o.helper or "")
  local ok,e=pcall(function()
    Events.AILeaderMessage(
      o.aiID,
      DiploUIStateTypes.DIPLO_UI_STATE_TRADE_AI_MAKES_OFFER,
      "I have a trade proposal that I believe is fair to both of us.",
      -1,0
    )
  end)
  if not ok then
    S("NativeUIError",tostring(e))
    CloseTrade(o.aiID)
  end
  return ok
end

local function Scan()
  if not Game.IsNetworkMultiPlayer() then Reason("NOT_NETWORK_MULTIPLAYER"); return end
  local h=Game.GetActivePlayer()
  if not HumanMajor(h) or not Players[h]:IsTurnActive() then Reason("NOT_ACTIVE_HUMAN_TURN"); return end
  if Game.IsProcessingMessages and Game.IsProcessingMessages() then Reason("MESSAGE_QUEUE_BUSY"); return end

  local turn=Game.GetGameTurn()
  if turn==lastScanTurn then Reason("ALREADY_SCANNED"); return end
  lastScanTurn=turn
  if turn-lastShownTurn<MIN_OFFER_GAP then Reason("LOCAL_OFFER_COOLDOWN"); return end
  attempts=0
  S("NativeBuildAttempts",0)

  local ais={}
  for ai=0,GameDefines.MAX_MAJOR_CIVS-1 do if CanTrade(ai,h) then table.insert(ais,ai) end end
  if #ais==0 then Reason("NO_ELIGIBLE_AI"); return end
  local start=(Hash(turn.."|"..h.."|AI")%#ais)+1
  local due=0

  for n=0,#ais-1 do
    if attempts>=MAX_ATTEMPTS then break end
    local ai=ais[((start-1+n)%#ais)+1]
    if Due(ai,h,turn) then
      due=due+1
      local o,why=TryAI(ai,h,turn)
      S("AI_"..ai.."_TryResult",why or "")
      if o then
        if Show(o) then
          lastShownTurn=turn
          Reason("DIRECT_NATIVE_OFFER_SENT")
        else
          Reason("OFFER_UI_NOT_SAFE")
        end
        return
      end
    end
  end
  if due==0 then Reason("RELATIONSHIP_SCHEDULE_NOT_DUE")
  elseif attempts>=MAX_ATTEMPTS then Reason("ATTEMPT_BUDGET_NO_DEAL")
  else Reason("NO_SIMPLE_NATIVE_DEAL") end
end

local Ready
local function RemoveRetry()
  if retryRegistered and Events.SerialEventGameDataDirty then Events.SerialEventGameDataDirty.Remove(Ready) end
  retryRegistered=false
end

Ready=function()
  if Game.GetGameTurn()~=retryTurn or Game.GetActivePlayer()~=retryHuman then RemoveRetry(); return end
  if Game.IsProcessingMessages and Game.IsProcessingMessages() then return end
  RemoveRetry()
  Scan()
end

local function Start()
  RemoveRetry()
  local h=Game.GetActivePlayer()
  if Game.IsProcessingMessages and Game.IsProcessingMessages() then
    retryTurn=Game.GetGameTurn()
    retryHuman=h
    Reason("TURN_START_MESSAGE_QUEUE_BUSY_READY_SIGNAL_ARMED")
    if Events.SerialEventGameDataDirty then
      Events.SerialEventGameDataDirty.Add(Ready)
      retryRegistered=true
    end
    return
  end
  Scan()
end

local function Finish() RemoveRetry() end

Events.ActivePlayerTurnStart.Add(Start)
if Events.ActivePlayerTurnEnd then Events.ActivePlayerTurnEnd.Add(Finish) end

S("Loaded",1)
S("RuntimeVersion",VERSION)
S("PerformanceModel","MAX_4_NATIVE_BUILD_ATTEMPTS_NO_CUSTOM_VALUE_MATH")
print("LEK Fair Trades v1.1.0 SIMPLE NATIVE: ready")
