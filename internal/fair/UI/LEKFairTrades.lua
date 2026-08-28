-- LEKMOD 30.7 Fair Trades v1.1.4 DIRECT NATIVE VALUE
-- One selected AI session, no trade-helper UI calls.
-- Exact luxury / Gold / GPT candidates are built directly in the scratch deal
-- and accepted only when both players' native deal-value APIs accept them.

print("LEK Fair Trades v1.1.4 DIRECT NATIVE VALUE: loading")
ContextPtr:SetHide(true)
MapModData = MapModData or {}

local VERSION=114
local DB_VERSION=1
local MIN_OFFER_GAP=2
local MAX_EVALS=8

-- LEK_FAIR_TRADES_DIRECT_VALUE_V114
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

S("RuntimePatch","V114_DIRECT_NATIVE_VALUE_NO_TRADE_HELPERS")
S("OfferEngine","ONE_AI_ONE_SESSION_DIRECT_NATIVE_VALUE_V114")
S("AllowedItems","LUXURY_FLAT_GOLD_GPT_ONLY_V114")
S("StrategicResources","NEVER")
S("LuxuryCopyPolicy","BOTH_SIDES_PRESERVE_LAST_COPY")
S("CurrencyDirections","LUXURY_FOR_GOLD_OR_GPT_BOTH_WAYS")
S("TradeSessionPolicy","ONE_AI_SESSION_MAX_PER_TURN")
S("NativeHelperPolicy","NONE_NO_DOWHATWILLGIVE_NO_DOWHATWANT_NO_EQUALIZE")
S("ScratchDealPolicy","DIRECT_BUILD_VALIDATE_SHOW_SAME_SCRATCH")
S("NativeEvalBudget",MAX_EVALS)

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
  if a==T.MAJOR_CIV_APPROACH_WAR or a==T.MAJOR_CIV_APPROACH_HOSTILE or a==T.MAJOR_CIV_APPROACH_DECEPTIVE then
    return false
  end
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
  d:ClearItems()
  d:SetFromPlayer(h)
  d:SetToPlayer(ai)
end

local function Possible(d,from,to,item,a,b)
  local ok,v=pcall(function()
    return d:IsPossibleToTradeItem(from,to,item,a or 0,b or 0)
  end)
  return ok and v==true
end

local function AddLux(d,from,to,res)
  if not res or not Luxury(res) then return false end
  if (Players[from]:GetNumResourceAvailable(res,true) or 0)<2 then return false end
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
  if not ap or not hp or not ap.GetDealMyValue or not ap.GetDealTheyreValue
     or not hp.GetDealMyValue or not hp.GetDealTheyreValue then
    return nil,"NATIVE_VALUE_API_MISSING"
  end
  evals=evals+1
  S("OfferNativeEvals",evals)
  local v={}
  local ok,e=pcall(function()
    v.aiMy=ap:GetDealMyValue(d)
    v.aiThey=ap:GetDealTheyreValue(d)
    v.hMy=hp:GetDealMyValue(d)
    v.hThey=hp:GetDealTheyreValue(d)
  end)
  if not ok then return nil,"NATIVE_VALUE_ERROR:"..tostring(e) end
  for _,n in pairs(v) do
    if type(n)~="number" or n<0 or n>=999999 then
      return nil,"NATIVE_VALUE_INVALID"
    end
  end
  return v,"OK"
end

local function SideMy(v,id,ai)
  return id==ai and v.aiMy or v.hMy
end

local function SideThey(v,id,ai)
  return id==ai and v.aiThey or v.hThey
end

local function NativeFair(v)
  if not v then return false end
  return v.aiThey>=v.aiMy and v.hThey>=v.hMy
end

local function PickRes(list,seed)
  if not list or #list==0 then return nil end
  return list[(Hash(seed)%#list)+1]
end

local function TrySwap(d,ai,h,hr,ar)
  if evals+1>MAX_EVALS then return false,"NATIVE_EVAL_BUDGET" end
  Prep(d,h,ai)
  if not AddLux(d,h,ai,hr) then return false,"HUMAN_SWAP_LUX_NOT_POSSIBLE" end
  if not AddLux(d,ai,h,ar) then return false,"AI_SWAP_LUX_NOT_POSSIBLE" end
  local v,why=Eval(d,ai,h)
  if not v then return false,why end
  if not NativeFair(v) then return false,"NATIVE_SWAP_VALUE_GATE" end
  return true,"LUXURY_FOR_LUXURY"
end

local function TryCurrency(d,ai,h,seller,buyer,res,currency)
  if evals+3>MAX_EVALS then return false,"NATIVE_EVAL_BUDGET" end

  Prep(d,h,ai)
  if not AddLux(d,seller,buyer,res) then return false,"LUXURY_NOT_POSSIBLE" end
  local luxV,why=Eval(d,ai,h)
  if not luxV then return false,why end

  local sellerNeeds=SideMy(luxV,seller,ai)
  local buyerMaxValue=SideThey(luxV,buyer,ai)
  if sellerNeeds<=0 or buyerMaxValue<=0 then return false,"LUXURY_NATIVE_VALUE_ZERO" end

  Prep(d,h,ai)
  local unitAdded=false
  if currency=="GOLD" then
    unitAdded=AddGold(d,buyer,seller,1)
  else
    unitAdded=AddGPT(d,buyer,seller,1)
  end
  if not unitAdded then return false,"CURRENCY_UNIT_NOT_POSSIBLE_IN_SESSION" end

  local unitV
  unitV,why=Eval(d,ai,h)
  if not unitV then return false,why end

  local buyerCostPer=SideMy(unitV,buyer,ai)
  local sellerValuePer=SideThey(unitV,seller,ai)
  if buyerCostPer<=0 or sellerValuePer<=0 then return false,"CURRENCY_NATIVE_UNIT_ZERO" end

  local minAmount=math.max(1,math.ceil(sellerNeeds/sellerValuePer))
  local maxAmount=math.floor(buyerMaxValue/buyerCostPer)

  if currency=="GOLD" then
    local payer=Players[buyer]
    local available=(payer and payer.GetGold and (payer:GetGold() or 0)) or 0
    maxAmount=math.min(maxAmount,math.floor(available))
  else
    local cap=GPTCap(buyer)
    if cap then maxAmount=math.min(maxAmount,cap) end
  end

  S("AI_"..ai.."_LastPriceMin",minAmount)
  S("AI_"..ai.."_LastPriceMax",maxAmount)
  S("AI_"..ai.."_LastPriceCurrency",currency)

  if maxAmount<minAmount then return false,"NO_MUTUALLY_FAIR_CURRENCY_RANGE" end

  local amount=math.floor((minAmount+maxAmount)/2)
  if amount<minAmount then amount=minAmount end

  Prep(d,h,ai)
  if not AddLux(d,seller,buyer,res) then return false,"FINAL_LUXURY_NOT_POSSIBLE" end
  local paid=false
  if currency=="GOLD" then
    paid=AddGold(d,buyer,seller,amount)
  else
    paid=AddGPT(d,buyer,seller,amount)
  end
  if not paid then return false,"FINAL_CURRENCY_NOT_POSSIBLE" end

  local finalV
  finalV,why=Eval(d,ai,h)
  if not finalV then return false,why end
  if not NativeFair(finalV) then return false,"FINAL_NATIVE_VALUE_GATE" end

  S("AI_"..ai.."_LastPriceAmount",amount)

  local shape
  if seller==h then
    shape=(currency=="GOLD") and "HUMAN_LUX_FOR_AI_GOLD" or "HUMAN_LUX_FOR_AI_GPT"
  else
    shape=(currency=="GOLD") and "AI_LUX_FOR_HUMAN_GOLD" or "AI_LUX_FOR_HUMAN_GPT"
  end
  return true,shape
end

local function ShapeOrder(ai,h,turn,hl,al)
  local shapes={}
  if #hl>0 and #al>0 then table.insert(shapes,"SWAP") end
  if #hl>0 then
    table.insert(shapes,"HUMAN_GOLD")
    table.insert(shapes,"HUMAN_GPT")
  end
  if #al>0 then
    table.insert(shapes,"AI_GOLD")
    table.insert(shapes,"AI_GPT")
  end
  if #shapes<=1 then return shapes end
  local start=(Hash(turn.."|"..h.."|"..ai.."|SHAPE")%#shapes)+1
  local out={}
  for n=0,#shapes-1 do
    table.insert(out,shapes[((start-1+n)%#shapes)+1])
  end
  return out
end

local function TryShapes(d,ai,h,turn,hl,al)
  local shapes=ShapeOrder(ai,h,turn,hl,al)
  local lastWhy="NO_SHAPES"

  for _,shape in ipairs(shapes) do
    local cost=(shape=="SWAP") and 1 or 3
    if evals+cost>MAX_EVALS then break end

    local ok,why=false,"UNKNOWN_SHAPE"
    if shape=="SWAP" then
      local hr=PickRes(hl,turn.."|"..ai.."|SWAP_H")
      local ar=PickRes(al,turn.."|"..ai.."|SWAP_A")
      ok,why=TrySwap(d,ai,h,hr,ar)
    elseif shape=="HUMAN_GOLD" then
      local r=PickRes(hl,turn.."|"..ai.."|H_GOLD")
      ok,why=TryCurrency(d,ai,h,h,ai,r,"GOLD")
    elseif shape=="HUMAN_GPT" then
      local r=PickRes(hl,turn.."|"..ai.."|H_GPT")
      ok,why=TryCurrency(d,ai,h,h,ai,r,"GPT")
    elseif shape=="AI_GOLD" then
      local r=PickRes(al,turn.."|"..ai.."|A_GOLD")
      ok,why=TryCurrency(d,ai,h,ai,h,r,"GOLD")
    elseif shape=="AI_GPT" then
      local r=PickRes(al,turn.."|"..ai.."|A_GPT")
      ok,why=TryCurrency(d,ai,h,ai,h,r,"GPT")
    end

    S("AI_"..ai.."_LastShape",shape)
    S("AI_"..ai.."_LastShapeResult",why or "")
    lastWhy=why or lastWhy
    if ok then return true,why end
  end

  return false,lastWhy
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

local function CloseSession(ai)
  pcall(function() Players[ai]:DoTradeScreenClosed(false) end)
end

local function ShowOneOffer(seed,h,turn)
  local ai=seed.ai
  if Game.GetActivePlayer()~=h or not Players[h]:IsTurnActive() then return false,"HUMAN_TURN_NOT_ACTIVE" end
  if Game.IsProcessingMessages and Game.IsProcessingMessages() then return false,"MESSAGE_QUEUE_BUSY" end
  if UI.GetLeaderHeadRootUp then
    local ok,up=pcall(UI.GetLeaderHeadRootUp)
    if ok and up then return false,"LEADER_SCREEN_ALREADY_OPEN" end
  end

  local hl=SpareLux(h,ai)
  local al=SpareLux(ai,h)
  if #hl==0 and #al==0 then return false,"NO_LONGER_HAS_SPARE_LUXURY" end

  S("NativeUIHeartbeat","ONE_SESSION_OPEN_BEGIN")
  evals=0
  S("OfferNativeEvals",0)

  local opened=false
  local success=false
  local finalShape=""
  local failWhy="NO_DIRECT_NATIVE_VALUE_DEAL"

  local ok,e=pcall(function()
    Players[ai]:DoTradeScreenOpened()
    UI.OnHumanOpenedTradeScreen(ai)
    opened=true

    local d=UI.GetScratchDeal()
    success,finalShape=TryShapes(d,ai,h,turn,hl,al)
    if not success then
      failWhy=finalShape or failWhy
      return
    end

    S("LastShownAI",ai)
    S("LastShownTurn",Game.GetGameTurn())
    S("LastShownShape",finalShape)
    S("NativeUIHeartbeat","ONE_SESSION_DIRECT_SCRATCH_READY")

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
    S("NativeUIHeartbeat","ONE_SESSION_CLOSED_NO_DIRECT_DEAL")
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

  local seed,why=FindOneAI(h,turn)
  if not seed then Reason(why); return end

  local shown,showWhy=ShowOneOffer(seed,h,turn)
  if shown then
    lastShownTurn=turn
    Reason("DIRECT_NATIVE_VALUE_OFFER_SENT")
  else
    S("LastShowReject",showWhy or "")
    Reason("ONE_SELECTED_AI_NO_DIRECT_NATIVE_VALUE_DEAL")
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
    if not Events.SerialEventGameDataDirty then
      Reason("READY_SIGNAL_EVENT_MISSING")
      retryArmed=false
      return
    end
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
S("PerformanceModel","ONE_AI_SESSION_MAX_8_NATIVE_VALUE_CALLS_ZERO_TRADE_HELPER_CALLS")
S("RelationshipModel","GUARDED_5_NEUTRAL_3_FRIENDLY_AFRAID_2")
print("LEK Fair Trades v1.1.4 DIRECT NATIVE VALUE: ready")
