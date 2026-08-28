-- LEKMOD 30.7 Fair Trades v1.1.5 EUI DIRECT OFFER BRIDGE
-- Search/value exact Luxury / Gold / GPT candidates before opening the AI trade session.
-- The visible offer is handed directly to EUI TradeLogic through a private LuaEvents bridge.
-- No UI.OnHumanOpenedTradeScreen and no spoofed Events.AILeaderMessage call.

print("LEK Fair Trades v1.1.5 EUI DIRECT OFFER BRIDGE: loading")
ContextPtr:SetHide(true)
MapModData = MapModData or {}

local VERSION=115
local DB_VERSION=1
local MIN_OFFER_GAP=2
local MAX_EVALS=8
local SEARCH_EVAL_LIMIT=MAX_EVALS
local FAIR_MESSAGE="I have a trade proposal that I believe is fair to both of us."

-- LEK_FAIR_TRADES_EUI_DIRECT_OFFER_V115
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
  S("OfferScanTurn",t); S("OfferScanHuman",h)
end

S("RuntimePatch","V115_EUI_DIRECT_OFFER_BRIDGE")
S("RuntimeHotfix","V115_NO_HUMAN_OPEN_NO_FAKE_AI_EVENT")
S("OfferEngine","ONE_AI_PRESESSION_SEARCH_EUI_DIRECT_OFFER_V115")
S("AllowedItems","LUXURY_FLAT_GOLD_GPT_ONLY_V115")
S("StrategicResources","NEVER")
S("LuxuryCopyPolicy","BOTH_SIDES_PRESERVE_LAST_COPY")
S("CurrencyDirections","LUXURY_FOR_GOLD_OR_GPT_BOTH_WAYS")
S("TradeSessionPolicy","PRESESSION_SEARCH_THEN_BACKEND_OPEN_DIRECT_EUI_HANDLER")
S("NativeHelperPolicy","NONE_NO_DOWHATWILLGIVE_NO_DOWHATWANT_NO_EQUALIZE")
S("ScratchDealPolicy","DIRECT_BUILD_VALIDATE_REBUILD_THEN_EUI_HANDLER")
S("EUIBridgePolicy","NO_ONHUMANOPENED_NO_FAKE_AILEADERMESSAGE")
S("NativeEvalBudget",MAX_EVALS)
S("SearchNativeEvalBudget",SEARCH_EVAL_LIMIT)

local lastScanTurn=-99999
local lastScanHuman=-1
local lastShownTurn=-99999
local retryArmed=false
local retryRegistered=false
local retryTurn=-1
local retryHuman=-1
local evals=0

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
  if a==T.MAJOR_CIV_APPROACH_WAR or a==T.MAJOR_CIV_APPROACH_HOSTILE or a==T.MAJOR_CIV_APPROACH_DECEPTIVE then return false end
  local n=(a==T.MAJOR_CIV_APPROACH_GUARDED and 5)
       or ((a==T.MAJOR_CIV_APPROACH_FRIENDLY or a==T.MAJOR_CIV_APPROACH_AFRAID) and 2)
       or 3
  return ((turn+(Hash(ai.."|"..h.."|REL")%n))%n)==0
end

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
  d:ClearItems(); d:SetFromPlayer(h); d:SetToPlayer(ai)
end
local function Possible(d,from,to,item,a,b)
  local ok,v=pcall(function() return d:IsPossibleToTradeItem(from,to,item,a or 0,b or 0) end)
  return ok and v==true
end
local function AddLux(d,from,to,res)
  if not res or not Luxury(res) then return false end
  local p=Players[from]
  if not p or (p:GetNumResourceAvailable(res,true) or 0)<2 then return false end
  if not Possible(d,from,to,TradeableItems.TRADE_ITEM_RESOURCES,res,1) then return false end
  d:AddResourceTrade(from,res,1,Duration())
  return true
end
local function AddGold(d,from,to,amount)
  amount=math.floor(amount or 0)
  local p=Players[from]
  if amount<=0 or not p or not p.GetGold or (p:GetGold() or 0)<amount then return false end
  if not Possible(d,from,to,TradeableItems.TRADE_ITEM_GOLD,amount,0) then return false end
  d:AddGoldTrade(from,amount)
  return true
end
local function AddGPT(d,from,to,amount)
  amount=math.floor(amount or 0)
  if amount<=0 then return false end
  if not Possible(d,from,to,TradeableItems.TRADE_ITEM_GOLD_PER_TURN,amount,0) then return false end
  d:AddGoldPerTurnTrade(from,amount,Duration())
  return true
end
local function GPTCap(id)
  local p=Players[id]
  if not p then return nil end
  local cap=nil
  if p.CalculateGoldRate then
    local ok,v=pcall(function() return p:CalculateGoldRate() end)
    if ok and type(v)=="number" then cap=math.floor(v) end
  end
  if (not cap or cap<1) and p.GetGoldPerTurn then
    local ok,v=pcall(function() return p:GetGoldPerTurn() end)
    if ok and type(v)=="number" then cap=math.floor(v) end
  end
  if cap and cap>0 then return cap end
  return nil
end

local function Eval(d,ai,h)
  if evals>=MAX_EVALS then return nil,"NATIVE_EVAL_BUDGET" end
  local ap,hp=Players[ai],Players[h]
  local hasAIMy=ap and ap.GetDealMyValue~=nil
  local hasAIThey=ap and ap.GetDealTheyreValue~=nil
  local hasHMy=hp and hp.GetDealMyValue~=nil
  local hasHThey=hp and hp.GetDealTheyreValue~=nil
  S("HasAIGetDealMyValue",hasAIMy and 1 or 0)
  S("HasAIGetDealTheyreValue",hasAIThey and 1 or 0)
  S("HasHumanGetDealMyValue",hasHMy and 1 or 0)
  S("HasHumanGetDealTheyreValue",hasHThey and 1 or 0)
  if not hasAIMy or not hasAIThey or not hasHMy or not hasHThey then return nil,"NATIVE_VALUE_API_MISSING" end
  evals=evals+1; S("OfferNativeEvals",evals)
  local v={}
  local ok,e=pcall(function()
    v.aiMy=ap:GetDealMyValue(d); v.aiThey=ap:GetDealTheyreValue(d)
    v.hMy=hp:GetDealMyValue(d); v.hThey=hp:GetDealTheyreValue(d)
  end)
  if not ok then return nil,"NATIVE_VALUE_ERROR:"..tostring(e) end
  for _,n in pairs(v) do
    if type(n)~="number" or n<0 or n>=999999 then return nil,"NATIVE_VALUE_INVALID" end
  end
  S("LastValueAIMy",v.aiMy); S("LastValueAIThey",v.aiThey)
  S("LastValueHumanMy",v.hMy); S("LastValueHumanThey",v.hThey)
  return v,"OK"
end
local function SideMy(v,id,ai) return id==ai and v.aiMy or v.hMy end
local function SideThey(v,id,ai) return id==ai and v.aiThey or v.hThey end
local function FairFor(v,id,ai) return v and SideThey(v,id,ai)>=SideMy(v,id,ai) end
local function BothFair(v) return v and v.aiThey>=v.aiMy and v.hThey>=v.hMy end
local function PickRes(list,seed)
  if not list or #list==0 then return nil end
  return list[(Hash(seed)%#list)+1]
end

local function TrySwap(d,ai,h,hr,ar)
  if evals+1>SEARCH_EVAL_LIMIT then return nil,"NATIVE_SEARCH_EVAL_BUDGET" end
  Prep(d,h,ai)
  if not AddLux(d,h,ai,hr) then return nil,"HUMAN_SWAP_LUX_NOT_POSSIBLE" end
  if not AddLux(d,ai,h,ar) then return nil,"AI_SWAP_LUX_NOT_POSSIBLE" end
  local v,why=Eval(d,ai,h)
  if not v then return nil,why end
  if not BothFair(v) then return nil,"NATIVE_SWAP_VALUE_GATE" end
  return {kind="SWAP",shape="LUXURY_FOR_LUXURY",humanRes=hr,aiRes=ar},"OK"
end

local function BuildCurrencyDeal(d,ai,h,seller,buyer,res,currency,amount)
  Prep(d,h,ai)
  if not AddLux(d,seller,buyer,res) then return false,"CURRENCY_LUXURY_NOT_POSSIBLE" end
  local paid=false
  if currency=="GOLD" then paid=AddGold(d,buyer,seller,amount)
  else paid=AddGPT(d,buyer,seller,amount) end
  if not paid then return false,"CURRENCY_PAYMENT_NOT_POSSIBLE" end
  return true,"OK"
end

local function TryCurrency(d,ai,h,seller,buyer,res,currency)
  if evals+3>SEARCH_EVAL_LIMIT then return nil,"NATIVE_SEARCH_EVAL_BUDGET" end
  Prep(d,h,ai)
  if not AddLux(d,seller,buyer,res) then return nil,"LUXURY_NOT_POSSIBLE" end
  local luxV,why=Eval(d,ai,h)
  if not luxV then return nil,why end
  local sellerNeeds=SideMy(luxV,seller,ai)
  local buyerMaxValue=SideThey(luxV,buyer,ai)
  if sellerNeeds<=0 or buyerMaxValue<=0 then return nil,"LUXURY_NATIVE_VALUE_ZERO" end

  Prep(d,h,ai)
  local unitAdded=false
  if currency=="GOLD" then unitAdded=AddGold(d,buyer,seller,1)
  else unitAdded=AddGPT(d,buyer,seller,1) end
  if not unitAdded then return nil,"CURRENCY_UNIT_NOT_POSSIBLE_PRESESSION" end
  local unitV
  unitV,why=Eval(d,ai,h)
  if not unitV then return nil,why end
  local buyerCostPer=SideMy(unitV,buyer,ai)
  local sellerValuePer=SideThey(unitV,seller,ai)
  if buyerCostPer<=0 or sellerValuePer<=0 then return nil,"CURRENCY_NATIVE_UNIT_ZERO" end

  local minAmount=math.max(1,math.ceil(sellerNeeds/sellerValuePer))
  local maxAmount=math.floor(buyerMaxValue/buyerCostPer)
  if currency=="GOLD" then
    local payer=Players[buyer]
    maxAmount=math.min(maxAmount,math.floor((payer and payer.GetGold and (payer:GetGold() or 0)) or 0))
  else
    local cap=GPTCap(buyer)
    if cap then maxAmount=math.min(maxAmount,cap) end
  end
  S("AI_"..ai.."_LastPriceMin",minAmount); S("AI_"..ai.."_LastPriceMax",maxAmount)
  S("AI_"..ai.."_LastPriceCurrency",currency)
  if maxAmount<minAmount then return nil,"NO_MUTUALLY_FAIR_CURRENCY_RANGE" end

  local amount=math.floor((minAmount+maxAmount)/2)
  if amount<minAmount then amount=minAmount end
  local built,buildWhy=BuildCurrencyDeal(d,ai,h,seller,buyer,res,currency,amount)
  if not built then return nil,"FINAL_"..buildWhy end
  local finalV
  finalV,why=Eval(d,ai,h)
  if not finalV then return nil,why end

  if not BothFair(finalV) and evals<SEARCH_EVAL_LIMIT then
    local retryAmount=nil
    local sellerOK=FairFor(finalV,seller,ai)
    local buyerOK=FairFor(finalV,buyer,ai)
    if not buyerOK and minAmount~=amount then retryAmount=minAmount
    elseif not sellerOK and maxAmount~=amount then retryAmount=maxAmount end
    if retryAmount then
      local retryBuilt=BuildCurrencyDeal(d,ai,h,seller,buyer,res,currency,retryAmount)
      if retryBuilt then
        local retryV
        retryV,why=Eval(d,ai,h)
        if retryV and BothFair(retryV) then
          amount=retryAmount; finalV=retryV
          S("AI_"..ai.."_PriceEndpointRetry",retryAmount)
        end
      end
    end
  end
  if not BothFair(finalV) then return nil,"FINAL_NATIVE_VALUE_GATE" end
  S("AI_"..ai.."_LastPriceAmount",amount)
  local shape
  if seller==h then shape=(currency=="GOLD") and "HUMAN_LUX_FOR_AI_GOLD" or "HUMAN_LUX_FOR_AI_GPT"
  else shape=(currency=="GOLD") and "AI_LUX_FOR_HUMAN_GOLD" or "AI_LUX_FOR_HUMAN_GPT" end
  return {kind=currency,shape=shape,seller=seller,buyer=buyer,res=res,amount=amount},"OK"
end

local function ShapeOrder(ai,h,turn,hl,al)
  local shapes={}
  if #hl>0 and #al>0 then table.insert(shapes,"SWAP") end
  if #hl>0 then table.insert(shapes,"HUMAN_GOLD"); table.insert(shapes,"HUMAN_GPT") end
  if #al>0 then table.insert(shapes,"AI_GOLD"); table.insert(shapes,"AI_GPT") end
  if #shapes<=1 then return shapes end
  local start=(Hash(turn.."|"..h.."|"..ai.."|SHAPE")%#shapes)+1
  local out={}
  for n=0,#shapes-1 do table.insert(out,shapes[((start-1+n)%#shapes)+1]) end
  return out
end
local function TryShapes(d,ai,h,turn,hl,al)
  local shapes=ShapeOrder(ai,h,turn,hl,al)
  local lastWhy="NO_SHAPES"
  for _,shape in ipairs(shapes) do
    local cost=(shape=="SWAP") and 1 or 3
    if evals+cost>SEARCH_EVAL_LIMIT then break end
    local c,why=nil,"UNKNOWN_SHAPE"
    if shape=="SWAP" then c,why=TrySwap(d,ai,h,PickRes(hl,turn.."|"..ai.."|SWAP_H"),PickRes(al,turn.."|"..ai.."|SWAP_A"))
    elseif shape=="HUMAN_GOLD" then c,why=TryCurrency(d,ai,h,h,ai,PickRes(hl,turn.."|"..ai.."|H_GOLD"),"GOLD")
    elseif shape=="HUMAN_GPT" then c,why=TryCurrency(d,ai,h,h,ai,PickRes(hl,turn.."|"..ai.."|H_GPT"),"GPT")
    elseif shape=="AI_GOLD" then c,why=TryCurrency(d,ai,h,ai,h,PickRes(al,turn.."|"..ai.."|A_GOLD"),"GOLD")
    elseif shape=="AI_GPT" then c,why=TryCurrency(d,ai,h,ai,h,PickRes(al,turn.."|"..ai.."|A_GPT"),"GPT") end
    S("AI_"..ai.."_LastShape",shape); S("AI_"..ai.."_LastShapeResult",why or "")
    lastWhy=why or lastWhy
    if c then return c,"OK" end
  end
  return nil,lastWhy
end

local function FindOneAI(h,turn)
  local ais={}
  for ai=0,GameDefines.MAX_MAJOR_CIVS-1 do if CanTrade(ai,h) then table.insert(ais,ai) end end
  table.sort(ais); S("OfferScanEligibleAIs",#ais)
  if #ais==0 then return nil,"NO_ELIGIBLE_AI" end
  local start=(Hash(turn.."|"..h.."|AI")%#ais)+1
  local due=0
  for n=0,#ais-1 do
    local ai=ais[((start-1+n)%#ais)+1]
    if Due(ai,h,turn) then
      due=due+1
      local hl,al=SpareLux(h,ai),SpareLux(ai,h)
      S("AI_"..ai.."_HumanSpareLuxCount",#hl); S("AI_"..ai.."_AISpareLuxCount",#al)
      if #hl>0 or #al>0 then S("OfferDueAIs",due); return {ai=ai,hl=hl,al=al},"OK" end
    end
  end
  S("OfferDueAIs",due)
  if due==0 then return nil,"RELATIONSHIP_SCHEDULE_NOT_DUE" end
  return nil,"NO_DUE_AI_WITH_SPARE_LUXURY"
end

-- Rebuild only an already-validated candidate after the backend AI session opens.
-- Deliberately performs no IsPossibleToTradeItem and no native valuation calls.
local function RebuildCandidate(d,c,h,ai)
  Prep(d,h,ai)
  if c.kind=="SWAP" then
    d:AddResourceTrade(h,c.humanRes,1,Duration())
    d:AddResourceTrade(ai,c.aiRes,1,Duration())
    return true,"OK"
  elseif c.kind=="GOLD" then
    d:AddResourceTrade(c.seller,c.res,1,Duration())
    d:AddGoldTrade(c.buyer,c.amount)
    return true,"OK"
  elseif c.kind=="GPT" then
    d:AddResourceTrade(c.seller,c.res,1,Duration())
    d:AddGoldPerTurnTrade(c.buyer,c.amount,Duration())
    return true,"OK"
  end
  return false,"DISPLAY_UNKNOWN_CANDIDATE_KIND"
end
local function CloseSession(ai) pcall(function() Players[ai]:DoTradeScreenClosed(false) end) end

local function ShowOneOffer(seed,h,turn)
  local ai=seed.ai
  if Game.GetActivePlayer()~=h or not Players[h]:IsTurnActive() then return false,"HUMAN_TURN_NOT_ACTIVE" end
  if Game.IsProcessingMessages and Game.IsProcessingMessages() then return false,"MESSAGE_QUEUE_BUSY" end
  if UI.GetLeaderHeadRootUp then local ok,up=pcall(UI.GetLeaderHeadRootUp); if ok and up then return false,"LEADER_SCREEN_ALREADY_OPEN" end end
  if not (MapModData and MapModData.LEK_FAIR_TRADES_EUI_OFFER_BRIDGE_READY) then
    S("EUIBridgeReady",0)
    return false,"EUI_OFFER_BRIDGE_NOT_READY"
  end
  S("EUIBridgeReady",1)

  local hl,al=SpareLux(h,ai),SpareLux(ai,h)
  if #hl==0 and #al==0 then return false,"NO_LONGER_HAS_SPARE_LUXURY" end

  evals=0; S("OfferNativeEvals",0); S("NativeUIHeartbeat","PRESESSION_SEARCH_BEGIN")
  S("EUIBridgeDispatch","NOT_REACHED")
  local backendOpened=false
  local candidate=nil
  local failWhy="NO_DIRECT_NATIVE_VALUE_DEAL"
  local ok,e=pcall(function()
    local d=UI.GetScratchDeal()
    candidate,failWhy=TryShapes(d,ai,h,turn,hl,al)
    if not candidate then
      pcall(function() d:ClearItems() end)
      return
    end

    S("NativeUIHeartbeat","VALID_CANDIDATE_PRESESSION")
    S("LastCandidateShape",candidate.shape or "")

    -- Open only the backend AI negotiation role. Do not use the human-opened
    -- trade entry point; EUI's own LeaderMessageHandler will open/render the UI.
    Players[ai]:DoTradeScreenOpened()
    backendOpened=true

    local built,buildWhy=RebuildCandidate(d,candidate,h,ai)
    if not built then error(buildWhy) end
    S("DisplayValidation","DIRECT_REBUILD_BEFORE_EUI_HANDLER")

    MapModData.LEK_FAIR_TRADES_EUI_OFFER_BRIDGE_LAST_HANDLED_AI=-1
    S("EUIBridgeDispatch","CALLING")
    LuaEvents.LEKFairTradesAIOffer(ai,FAIR_MESSAGE)
    if MapModData.LEK_FAIR_TRADES_EUI_OFFER_BRIDGE_LAST_HANDLED_AI~=ai then
      error("EUI_OFFER_BRIDGE_NOT_HANDLED")
    end
    S("EUIBridgeDispatch","HANDLED")
    S("EUIBridgeHandledAI",ai)
    S("LastShownAI",ai); S("LastShownTurn",Game.GetGameTurn()); S("LastShownShape",candidate.shape or "")
    S("NativeUIHeartbeat","EUI_AI_OFFER_HANDLER_CONFIRMED")
  end)
  if not ok then
    S("NativeUIHeartbeat","ONE_SESSION_ERROR"); S("NativeUIError",tostring(e))
    MapModData.LEK_FAIR_TRADES_EUI_OFFER_ACTIVE_AI=-1
    if backendOpened then CloseSession(ai) end
    return false,tostring(e)
  end
  if not candidate then
    S("LastNativeReject",failWhy or "")
    S("NativeUIHeartbeat","PRESESSION_NO_DEAL_NO_UI")
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
    Reason("TURN_START_MESSAGE_QUEUE_BUSY_READY_SIGNAL_ARMED"); retryArmed=true; retryTurn=Game.GetGameTurn(); retryHuman=h; return
  end
  if UI.GetLeaderHeadRootUp then local ok,up=pcall(UI.GetLeaderHeadRootUp); if ok and up then Reason("LEADER_SCREEN_ALREADY_OPEN"); return end end
  local turn=Game.GetGameTurn()
  if turn==lastScanTurn and h==lastScanHuman then Reason("ALREADY_SCANNED_THIS_TURN"); return end
  lastScanTurn,lastScanHuman=turn,h
  if turn-lastShownTurn<MIN_OFFER_GAP then Reason("LOCAL_OFFER_COOLDOWN"); return end
  local seed,why=FindOneAI(h,turn)
  if not seed then Reason(why); return end
  local shown,showWhy=ShowOneOffer(seed,h,turn)
  if shown then lastShownTurn=turn; Reason("EUI_DIRECT_AI_OFFER_SENT")
  else S("LastShowReject",showWhy or ""); Reason("ONE_SELECTED_AI_NO_EUI_DIRECT_DEAL") end
end

local Ready
local function RemoveRetry()
  if retryRegistered and Events.SerialEventGameDataDirty then Events.SerialEventGameDataDirty.Remove(Ready) end
  retryRegistered=false; retryArmed=false
end
Ready=function()
  if not retryRegistered then return end
  if Game.GetGameTurn()~=retryTurn or Game.GetActivePlayer()~=retryHuman then RemoveRetry(); return end
  if not Players[retryHuman] or not Players[retryHuman]:IsTurnActive() then RemoveRetry(); return end
  if Game.IsProcessingMessages and Game.IsProcessingMessages() then return end
  RemoveRetry(); Reason("TURN_START_MESSAGE_QUEUE_CLEARED_READY_SIGNAL"); Scan()
end
local function Start()
  RemoveRetry(); retryTurn,retryHuman=-1,-1; Scan()
  if retryArmed then
    if not Events.SerialEventGameDataDirty then Reason("READY_SIGNAL_EVENT_MISSING"); retryArmed=false; return end
    Events.SerialEventGameDataDirty.Add(Ready); retryRegistered=true; S("OfferRetryHeartbeat","READY_SIGNAL_REGISTERED")
  end
end
local function Finish() if retryRegistered or retryArmed then RemoveRetry() end end

Events.ActivePlayerTurnStart.Add(Start)
if Events.ActivePlayerTurnEnd then Events.ActivePlayerTurnEnd.Add(Finish) end
S("Loaded",1); S("RuntimeVersion",VERSION); S("StateSchemaVersion",DB_VERSION)
S("PerformanceModel","ONE_AI_PRESESSION_MAX_8_NATIVE_VALUE_CALLS_DIRECT_EUI_HANDLER")
S("RelationshipModel","GUARDED_5_NEUTRAL_3_FRIENDLY_AFRAID_2")
print("LEK Fair Trades v1.1.5 EUI DIRECT OFFER BRIDGE: ready")
