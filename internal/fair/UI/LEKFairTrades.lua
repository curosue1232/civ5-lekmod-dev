-- LEKMOD 30.7 Fair Trades v1.1.2 SAFE CURRENCY
-- Safe proactive offers: spare luxury swaps plus native-valued flat Gold/GPT
-- luxury trades in either direction. Candidate search never opens diplomacy;
-- exactly one native trade session may open after a complete deal is chosen.

print("LEK Fair Trades v1.1.2 SAFE CURRENCY: loading")
ContextPtr:SetHide(true)
MapModData = MapModData or {}

local VERSION=112
local DB_VERSION=1
local MIN_OFFER_GAP=2
local MAX_EVALS=6

-- LEK_FAIR_TRADES_SAFE_CURRENCY_V112
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

S("RuntimePatch","V112_SAFE_LUX_SWAP_GOLD_GPT")
S("OfferEngine","SPARE_LUX_SWAP_PLUS_NATIVE_PRICED_GOLD_GPT_V112")
S("AllowedItems","LUXURY_FLAT_GOLD_GPT_ONLY_V112")
S("StrategicResources","NEVER")
S("LuxuryCopyPolicy","BOTH_SIDES_PRESERVE_LAST_COPY")
S("CurrencyDirections","LUXURY_FOR_GOLD_OR_GPT_BOTH_WAYS")
S("TradeSessionPolicy","OPEN_EXACTLY_ONE_SESSION_AFTER_CANDIDATE_CHOSEN")
S("ScratchDealPolicy","VALUATE_SILENTLY_THEN_BUILD_FRESH_IN_ONE_SESSION")
S("NativeHelperPolicy","NO_WHAT_WILL_AI_GIVE_NO_EQUALIZER")
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

-- A proactive luxury offer must leave the seller with at least one copy.
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

local function AddLux(d,from,to,res)
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
    if type(n)~="number" or n<0 or n>=999999 then return nil,"NATIVE_VALUE_INVALID" end
  end
  return v,"OK"
end

local function NativeFair(v)
  if not v then return false end
  return v.aiThey>=v.aiMy and v.hThey>=v.hMy
end

local function SideMy(v,id,ai)
  return id==ai and v.aiMy or v.hMy
end

local function SideThey(v,id,ai)
  return id==ai and v.aiThey or v.hThey
end

local function BuildSwapCandidate(ai,h,humanRes,aiRes)
  if evals>=MAX_EVALS then return nil,"NATIVE_EVAL_BUDGET" end
  local d=UI.GetScratchDeal()
  Prep(d,h,ai)
  if not AddLux(d,h,ai,humanRes) or not AddLux(d,ai,h,aiRes) then return nil,"LUX_SWAP_NOT_POSSIBLE" end
  local v,why=Eval(d,ai,h)
  if not v then return nil,why end
  if not NativeFair(v) then return nil,"NATIVE_SWAP_VALUE_GATE" end
  return {kind="SWAP",ai=ai,h=h,humanRes=humanRes,aiRes=aiRes},"OK"
end

-- Price one spare luxury against one currency type using each side's own native
-- value scale. Two silent calibration deals determine the fair range; a third
-- native valuation verifies the final amount before any diplomacy UI is opened.
local function BuildCurrencyCandidate(ai,h,seller,buyer,res,currency)
  if evals+3>MAX_EVALS then return nil,"NATIVE_EVAL_BUDGET" end
  local d=UI.GetScratchDeal()

  -- 1) Native value of the luxury itself.
  Prep(d,h,ai)
  if not AddLux(d,seller,buyer,res) then return nil,"LUXURY_NOT_POSSIBLE" end
  local luxV,why=Eval(d,ai,h)
  if not luxV then return nil,why end
  local sellerNeeds=SideMy(luxV,seller,ai)
  local buyerMaxValue=SideThey(luxV,buyer,ai)
  if sellerNeeds<=0 or buyerMaxValue<=0 then return nil,"LUXURY_NATIVE_VALUE_ZERO" end

  -- 2) Native value of one unit of the chosen currency to each side.
  Prep(d,h,ai)
  local unitAdded=false
  if currency=="GOLD" then unitAdded=AddGold(d,buyer,seller,1)
  else unitAdded=AddGPT(d,buyer,seller,1) end
  if not unitAdded then return nil,"CURRENCY_UNIT_NOT_POSSIBLE" end
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
    local available=(payer and payer.GetGold and (payer:GetGold() or 0)) or 0
    maxAmount=math.min(maxAmount,math.floor(available))
  end
  if maxAmount<minAmount then
    S("AI_"..ai.."_LastPriceMin",minAmount)
    S("AI_"..ai.."_LastPriceMax",maxAmount)
    return nil,"NO_MUTUALLY_FAIR_CURRENCY_RANGE"
  end

  -- Use the middle of the native-acceptable range: fair to the seller without
  -- automatically charging the buyer's absolute maximum.
  local amount=math.floor((minAmount+maxAmount)/2)
  if amount<minAmount then amount=minAmount end

  -- 3) Final native validation of the exact deal we would display.
  Prep(d,h,ai)
  if not AddLux(d,seller,buyer,res) then return nil,"FINAL_LUXURY_NOT_POSSIBLE" end
  local paid=false
  if currency=="GOLD" then paid=AddGold(d,buyer,seller,amount)
  else paid=AddGPT(d,buyer,seller,amount) end
  if not paid then return nil,"FINAL_CURRENCY_NOT_POSSIBLE" end
  local finalV
  finalV,why=Eval(d,ai,h)
  if not finalV then return nil,why end
  if not NativeFair(finalV) then return nil,"FINAL_NATIVE_VALUE_GATE" end

  S("AI_"..ai.."_LastPriceMin",minAmount)
  S("AI_"..ai.."_LastPriceMax",maxAmount)
  S("AI_"..ai.."_LastPriceAmount",amount)
  S("AI_"..ai.."_LastPriceCurrency",currency)

  return {
    kind=currency,
    ai=ai,h=h,
    seller=seller,buyer=buyer,
    res=res,amount=amount
  },"OK"
end

local function CloseSession(ai)
  pcall(function() Players[ai]:DoTradeScreenClosed(false) end)
end

local function CandidateStillSafe(c)
  if not c then return false,"NO_CANDIDATE" end
  if c.kind=="SWAP" then
    if (Players[c.h]:GetNumResourceAvailable(c.humanRes,true) or 0)<2 then return false,"HUMAN_NO_LONGER_HAS_SPARE" end
    if (Players[c.ai]:GetNumResourceAvailable(c.aiRes,true) or 0)<2 then return false,"AI_NO_LONGER_HAS_SPARE" end
    return true,"OK"
  end
  if (Players[c.seller]:GetNumResourceAvailable(c.res,true) or 0)<2 then return false,"SELLER_NO_LONGER_HAS_SPARE" end
  if c.kind=="GOLD" then
    local p=Players[c.buyer]
    if not p or not p.GetGold or (p:GetGold() or 0)<c.amount then return false,"BUYER_NO_LONGER_HAS_GOLD" end
  end
  return true,"OK"
end

local function BuildDisplayedDeal(d,c)
  Prep(d,c.h,c.ai)
  if c.kind=="SWAP" then
    if not AddLux(d,c.h,c.ai,c.humanRes) then return false,"DISPLAY_HUMAN_LUX_NOT_POSSIBLE" end
    if not AddLux(d,c.ai,c.h,c.aiRes) then return false,"DISPLAY_AI_LUX_NOT_POSSIBLE" end
    return true,"OK"
  end
  if not AddLux(d,c.seller,c.buyer,c.res) then return false,"DISPLAY_LUX_NOT_POSSIBLE" end
  if c.kind=="GOLD" then
    if not AddGold(d,c.buyer,c.seller,c.amount) then return false,"DISPLAY_GOLD_NOT_POSSIBLE" end
  else
    if not AddGPT(d,c.buyer,c.seller,c.amount) then return false,"DISPLAY_GPT_NOT_POSSIBLE" end
  end
  return true,"OK"
end

local function ShowCandidate(c)
  if Game.GetActivePlayer()~=c.h or not Players[c.h]:IsTurnActive() then return false,"HUMAN_TURN_NOT_ACTIVE" end
  if Game.IsProcessingMessages and Game.IsProcessingMessages() then return false,"MESSAGE_QUEUE_BUSY" end
  if UI.GetLeaderHeadRootUp then
    local ok,up=pcall(UI.GetLeaderHeadRootUp)
    if ok and up then return false,"LEADER_SCREEN_ALREADY_OPEN" end
  end
  local safe,why=CandidateStillSafe(c)
  if not safe then return false,why end

  S("NativeUIHeartbeat","ONE_SESSION_OPEN_BEGIN")
  local ok,e=pcall(function()
    Players[c.ai]:DoTradeScreenOpened()
    UI.OnHumanOpenedTradeScreen(c.ai)

    local d=UI.GetScratchDeal()
    local built,buildWhy=BuildDisplayedDeal(d,c)
    if not built then error(buildWhy) end

    S("LastShownAI",c.ai)
    S("LastShownTurn",Game.GetGameTurn())
    S("LastShownKind",c.kind)
    if c.kind=="SWAP" then
      S("LastShownHumanLuxury",c.humanRes)
      S("LastShownAILuxury",c.aiRes)
    else
      S("LastShownLuxurySeller",c.seller)
      S("LastShownLuxury",c.res)
      S("LastShownCurrencyAmount",c.amount)
    end
    S("NativeUIHeartbeat","ONE_SESSION_SCRATCH_READY")

    Events.AILeaderMessage(
      c.ai,
      DiploUIStateTypes.DIPLO_UI_STATE_TRADE_AI_MAKES_OFFER,
      "I have a trade proposal that I believe is fair to both of us.",
      -1,0
    )
  end)

  if not ok then
    S("NativeUIHeartbeat","ONE_SESSION_OPEN_ERROR")
    S("NativeUIError",tostring(e))
    CloseSession(c.ai)
    return false,tostring(e)
  end

  S("NativeUIHeartbeat","ONE_SESSION_OFFER_SENT")
  return true,"OK"
end

local function RotatedShapes(ai,h,turn,hl,al)
  local shapes={}
  if #hl>0 and #al>0 then table.insert(shapes,"SWAP") end
  if #hl>0 then
    table.insert(shapes,"HUMAN_LUX_GOLD")
    table.insert(shapes,"HUMAN_LUX_GPT")
  end
  if #al>0 then
    table.insert(shapes,"AI_LUX_GOLD")
    table.insert(shapes,"AI_LUX_GPT")
  end
  if #shapes<=1 then return shapes end
  local start=(Hash(turn.."|"..h.."|"..ai.."|SHAPE")%#shapes)+1
  local out={}
  for n=0,#shapes-1 do table.insert(out,shapes[((start-1+n)%#shapes)+1]) end
  return out
end

local function PickRes(list,seed)
  if not list or #list==0 then return nil end
  return list[(Hash(seed)%#list)+1]
end

local function TryAI(ai,h,turn)
  local hl=SpareLux(h,ai)
  local al=SpareLux(ai,h)
  S("AI_"..ai.."_HumanSpareLuxCount",#hl)
  S("AI_"..ai.."_AISpareLuxCount",#al)
  if #hl==0 and #al==0 then return nil,"NO_SPARE_LUXURY" end

  local shapes=RotatedShapes(ai,h,turn,hl,al)
  local lastWhy="NO_SHAPES"
  for i,shape in ipairs(shapes) do
    if evals>=MAX_EVALS then break end
    local c,why=nil,"UNKNOWN"
    if shape=="SWAP" then
      local hr=PickRes(hl,turn.."|"..ai.."|HR")
      local ar=PickRes(al,turn.."|"..ai.."|AR")
      c,why=BuildSwapCandidate(ai,h,hr,ar)
    elseif shape=="HUMAN_LUX_GOLD" then
      local r=PickRes(hl,turn.."|"..ai.."|HG")
      c,why=BuildCurrencyCandidate(ai,h,h,ai,r,"GOLD")
    elseif shape=="HUMAN_LUX_GPT" then
      local r=PickRes(hl,turn.."|"..ai.."|HP")
      c,why=BuildCurrencyCandidate(ai,h,h,ai,r,"GPT")
    elseif shape=="AI_LUX_GOLD" then
      local r=PickRes(al,turn.."|"..ai.."|AG")
      c,why=BuildCurrencyCandidate(ai,h,ai,h,r,"GOLD")
    elseif shape=="AI_LUX_GPT" then
      local r=PickRes(al,turn.."|"..ai.."|AP")
      c,why=BuildCurrencyCandidate(ai,h,ai,h,r,"GPT")
    end
    S("AI_"..ai.."_LastShape",shape)
    S("AI_"..ai.."_LastShapeResult",why or "")
    lastWhy=why or lastWhy
    if c then return c,"OK" end
    if evals+3>MAX_EVALS and shape~="SWAP" then break end
  end
  return nil,lastWhy
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
  for n=0,#ais-1 do
    if evals>=MAX_EVALS then break end
    local ai=ais[((start-1+n)%#ais)+1]
    if Due(ai,h,turn) then
      due=due+1
      local c,why=TryAI(ai,h,turn)
      S("AI_"..ai.."_TryResult",why or "")
      if c then
        S("OfferDueAIs",due)
        return c,"OK"
      end
    end
  end

  S("OfferDueAIs",due)
  if due==0 then return nil,"RELATIONSHIP_SCHEDULE_NOT_DUE" end
  if evals>=MAX_EVALS then return nil,"NATIVE_EVAL_BUDGET_NO_DEAL" end
  return nil,"NO_SAFE_FAIR_LUXURY_DEAL"
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

  evals=0
  S("OfferNativeEvals",0)
  local c,why=FindCandidate(h,turn)
  if not c then Reason(why); return end

  -- Exactly one trade session can be opened in a scan. Failed display never
  -- falls through to another AI, preventing queued empty diplomacy windows.
  local shown,showWhy=ShowCandidate(c)
  if shown then
    lastShownTurn=turn
    Reason("DIRECT_SAFE_FAIR_OFFER_SENT")
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
S("PerformanceModel","MAX_6_NATIVE_EVALS_NO_PRICING_HELPERS_ONE_UI_SESSION_MAX_PER_TURN")
S("RelationshipModel","GUARDED_5_NEUTRAL_3_FRIENDLY_AFRAID_2")
print("LEK Fair Trades v1.1.2 SAFE CURRENCY: ready")
