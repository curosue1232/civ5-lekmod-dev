-- LEKMOD 30.7 Fair Trades v1.0.10
-- Silent native-value proactive trade engine for frozen LEK Core v1.3.
-- Direct native trade-offer handoff: never opens the default leader/greeting state.

print("LEK Fair Trades v1.0.10: loading")
ContextPtr:SetHide(true)
MapModData = MapModData or {}

local VERSION=110
local DB_VERSION=1
local MAX_EVALS=8
local MAX_SEEDS=2
local MAX_SWAP_PAIRS=3
local MIN_OFFER_GAP=2

if MapModData.LEK_FAIR_TRADES_RUNTIME_VERSION==VERSION then return end
MapModData.LEK_FAIR_TRADES_RUNTIME_VERSION=VERSION

local db=nil
pcall(function() db=Modding.OpenUserData("LEK_FAIR_TRADES",DB_VERSION) end)
local function S(k,v) if db then pcall(function() db.SetValue(k,v) end) end end

-- LEK_FAIR_TRADES_CANDIDATE_ENGINE_V110
S("RuntimePatch","V110_MULTI_SWAP_LAZY_PRICE_CALIBRATION")
S("AILuxuryOfferPolicy","ALLOW_SINGLE_COPY_IF_NATIVE_LEGAL_AND_FAIR")
S("HumanLuxuryOfferPolicy","PRESERVE_LAST_COPY")
S("LoadSafety","WAIT_FOR_REAL_HUMAN_TURN_START")
S("OfferScanReason","V110_LOADED_WAITING_FOR_REAL_TURN_START")
S("OfferScanTrail","")
S("OfferScanTurn",-1)
S("OfferNativeEvals",0)
S("OfferDueAIs",0)
S("OfferDueAIIDs","")
S("NativeUIHeartbeat","IDLE")
S("CandidateSearch","UP_TO_3_LUX_SWAP_PAIRS_THEN_ONE_GOLD_BALANCE")
S("PricingOrder","FLAT_GOLD_BEFORE_LAZY_GPT_CALIBRATION")

local trail={}
local function Reason(r)
  S("OfferScanReason",r)
  local t,h=-1,-1
  pcall(function() t=Game.GetGameTurn() end)
  pcall(function() h=Game.GetActivePlayer() end)
  table.insert(trail,tostring(t)..":"..tostring(h)..":"..tostring(r))
  while #trail>16 do table.remove(trail,1) end
  S("OfferScanTrail",table.concat(trail," | "))
end

local lastScanTurn,lastScanHuman,lastShownTurn=-99999,-1,-99999
local evals=0
local retryArmed,retryRegistered=false,false
local retryTurn,retryHuman,retrySignals=-1,-1,0

local function Duration()
  local d=Game.GetDealDuration()
  if not d or d<=0 then d=30 end
  return d
end
local function HumanMajor(id)
  local p=Players[id]
  return p and p:IsAlive() and p:IsHuman() and not p:IsMinorCiv() and not p:IsBarbarian()
end
local function AIMajor(id)
  local p=Players[id]
  return p and p:IsAlive() and not p:IsHuman() and not p:IsMinorCiv() and not p:IsBarbarian()
end
local function Luxury(id)
  return id~=nil and Game.GetResourceUsageType(id)==ResourceUsageTypes.RESOURCEUSAGE_LUXURY
end
local function Hash(x)
  x=tostring(x or "")
  local h=104729
  for i=1,#x do h=(h*131+string.byte(x,i))%2147483629 end
  return h
end

local function Approach(ai,h)
  local p=Players[ai]
  if p and p.GetMajorCivApproach then
    local ok,v=pcall(function() return p:GetMajorCivApproach(h) end)
    if ok and v~=nil then return v end
  end
  return MajorCivApproachTypes.MAJOR_CIV_APPROACH_NEUTRAL
end
local function ApproachName(a)
  local T=MajorCivApproachTypes
  if a==T.MAJOR_CIV_APPROACH_WAR then return "WAR" end
  if a==T.MAJOR_CIV_APPROACH_HOSTILE then return "HOSTILE" end
  if a==T.MAJOR_CIV_APPROACH_DECEPTIVE then return "DECEPTIVE" end
  if a==T.MAJOR_CIV_APPROACH_GUARDED then return "GUARDED" end
  if a==T.MAJOR_CIV_APPROACH_AFRAID then return "AFRAID" end
  if a==T.MAJOR_CIV_APPROACH_FRIENDLY then return "FRIENDLY" end
  if a==T.MAJOR_CIV_APPROACH_NEUTRAL then return "NEUTRAL" end
  return tostring(a)
end
local function Due(ai,h,turn)
  local a=Approach(ai,h)
  S("AI_"..ai.."_Approach",ApproachName(a))
  local T=MajorCivApproachTypes
  if a==T.MAJOR_CIV_APPROACH_WAR or a==T.MAJOR_CIV_APPROACH_HOSTILE or a==T.MAJOR_CIV_APPROACH_DECEPTIVE then
    S("AI_"..ai.."_RelationshipDue",0); return false
  end
  local n=(a==T.MAJOR_CIV_APPROACH_GUARDED and 5)
       or (a==T.MAJOR_CIV_APPROACH_NEUTRAL and 3)
       or ((a==T.MAJOR_CIV_APPROACH_FRIENDLY or a==T.MAJOR_CIV_APPROACH_AFRAID) and 2)
       or 4
  S("AI_"..ai.."_RelationshipInterval",n)
  local yes=((turn+(Hash(ai.."|"..h.."|REL")%n))%n)==0
  S("AI_"..ai.."_RelationshipDue",yes and 1 or 0)
  return yes
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
local function AIs(h)
  local a={}
  for i=0,GameDefines.MAX_MAJOR_CIVS-1 do if CanTrade(i,h) then table.insert(a,i) end end
  table.sort(a); return a
end

local function Possible(d,from,to,item,x,y)
  local ok,v=pcall(function() return d:IsPossibleToTradeItem(from,to,item,x or 0,y or 0) end)
  return ok and v==true
end
local function OfferableLux(pID,oID,preserveLastCopy)
  local p,o=Players[pID],Players[oID]
  local a={}
  if not p or not o then return a end
  local minOwned=preserveLastCopy and 2 or 1
  for r in GameInfo.Resources() do
    if Luxury(r.ID) and (p:GetNumResourceAvailable(r.ID,true) or 0)>=minOwned
       and (o:GetNumResourceAvailable(r.ID,true) or 0)<=0 then table.insert(a,r.ID) end
  end
  table.sort(a); return a
end
local function Prep(d,h,ai) d:ClearItems(); d:SetFromPlayer(h); d:SetToPlayer(ai) end

local function Snapshot(d)
  local a={}; d:ResetIterator()
  while true do
    local x={d:GetNextItem()}; local n=#x
    if n<1 or x[1]==nil then break end
    table.insert(a,{itemType=x[1],duration=x[2] or 0,data1=x[4] or 0,data2=x[5] or 0,fromPlayer=x[n]})
  end
  return a
end

local function Structural(items,ai,h)
  local ac,hc=0,0
  if not items or #items==0 then return false,"EMPTY_DEAL" end
  for _,x in ipairs(items) do
    if x.fromPlayer~=ai and x.fromPlayer~=h then return false,"THIRD_PARTY_ITEM" end
    if x.itemType==TradeableItems.TRADE_ITEM_RESOURCES then
      if not Luxury(x.data1) then return false,"UNSUPPORTED_OR_STRATEGIC_ITEM" end
      local q=math.max(1,x.data2 or 1)
      if x.fromPlayer==h and (Players[h]:GetNumResourceAvailable(x.data1,true) or 0)<=q then
        return false,"HUMAN_LAST_LUXURY_COPY"
      end
    elseif x.itemType~=TradeableItems.TRADE_ITEM_GOLD and x.itemType~=TradeableItems.TRADE_ITEM_GOLD_PER_TURN then
      return false,"UNSUPPORTED_OR_STRATEGIC_ITEM"
    end
    if x.fromPlayer==ai then ac=ac+1 else hc=hc+1 end
  end
  if ac==0 or hc==0 then return false,"ONE_SIDED_DEAL" end
  return true,"OK"
end

local function Values(d,ai,h)
  if evals>=MAX_EVALS then return nil,"NATIVE_EVAL_BUDGET_EXHAUSTED" end
  local a,p=Players[ai],Players[h]
  if not a or not p or not a.GetDealMyValue or not a.GetDealTheyreValue
     or not p.GetDealMyValue or not p.GetDealTheyreValue then return nil,"NATIVE_SIDE_VALUATION_MISSING" end
  evals=evals+1
  local v={}
  local ok,e=pcall(function()
    v.aiMy=a:GetDealMyValue(d); v.aiThey=a:GetDealTheyreValue(d)
    v.hMy=p:GetDealMyValue(d); v.hThey=p:GetDealTheyreValue(d)
  end)
  if not ok then return nil,"NATIVE_SIDE_VALUATION_ERROR:"..tostring(e) end
  for _,n in pairs(v) do if type(n)~="number" or n<0 or n>=999999 then return nil,"NATIVE_SIDE_VALUATION_INVALID" end end
  return v,"OK"
end
local function Accepted(v)
  if v.aiThey<v.aiMy then return false,"AI_NATIVE_VALUE_GATE" end
  if v.hThey<v.hMy then return false,"HUMAN_NATIVE_FAIRNESS_GATE" end
  return true,"OK"
end
local function Candidate(d,ai,h,name)
  local items=Snapshot(d)
  local ok,why=Structural(items,ai,h); if not ok then return nil,why,nil end
  local v; v,why=Values(d,ai,h); if not v then return nil,why,nil end
  S("AI_"..ai.."_LastAIValueMy",v.aiMy); S("AI_"..ai.."_LastAIValueThey",v.aiThey)
  S("AI_"..ai.."_LastHumanValueMy",v.hMy); S("AI_"..ai.."_LastHumanValueThey",v.hThey)
  ok,why=Accepted(v); if not ok then return nil,why,v end
  return {aiID=ai,humanID=h,items=items,aiGives=v.hThey,humanGives=v.hMy,seed=name},"OK",v
end

local function AddGold(d,from,to,n)
  n=math.floor(n or 0); local p=Players[from]
  if n<=0 or not p or not p.GetGold or (p:GetGold() or 0)<n then return false end
  if not Possible(d,from,to,TradeableItems.TRADE_ITEM_GOLD,n,0) then return false end
  d:AddGoldTrade(from,n); return true
end
local function AddGPT(d,from,to,n)
  n=math.floor(n or 0); if n<=0 then return false end
  if not Possible(d,from,to,TradeableItems.TRADE_ITEM_GOLD_PER_TURN,n,0) then return false end
  d:AddGoldPerTurnTrade(from,n,Duration()); return true
end
local function Seed(d,ai,h,fromHuman,res)
  Prep(d,h,ai); local from=fromHuman and h or ai; local to=fromHuman and ai or h
  if not Possible(d,from,to,TradeableItems.TRADE_ITEM_RESOURCES,res,1) then return nil,"SEED_NOT_POSSIBLE" end
  d:AddResourceTrade(from,res,1,Duration())
  return Values(d,ai,h)
end

local function GPTUnitValue(ai,h,payer,recv)
  local d=UI.GetScratchDeal(); Prep(d,h,ai)
  if not AddGPT(d,payer,recv,1) then return nil,"ONE_GPT_NOT_POSSIBLE" end
  local v,why=Values(d,ai,h); if not v then return nil,why end
  local unit=(payer==ai) and v.hThey or v.aiThey
  if type(unit)~="number" or unit<=0 then return nil,"ONE_GPT_NATIVE_VALUE_ZERO" end
  S("AI_"..ai.."_NativeOneGPTValue",unit)
  return unit,"OK"
end

local function PriceLux(ai,h,fromHuman,res)
  local d=UI.GetScratchDeal(); local base,why=Seed(d,ai,h,fromHuman,res); if not base then return nil,why end
  local payer=fromHuman and ai or h; local recv=fromHuman and h or ai
  local need=fromHuman and base.hMy or base.aiMy
  local ceiling=fromHuman and base.aiThey or base.hThey
  S("AI_"..ai.."_LastSeedLuxuryValueMin",need); S("AI_"..ai.."_LastSeedLuxuryValueMax",ceiling)
  if need<=0 or ceiling<need then return nil,"NO_MUTUALLY_FAIR_PRICE_WINDOW" end

  local function reset()
    Prep(d,h,ai); local from=fromHuman and h or ai; local to=fromHuman and ai or h
    if not Possible(d,from,to,TradeableItems.TRADE_ITEM_RESOURCES,res,1) then return false end
    d:AddResourceTrade(from,res,1,Duration()); return true
  end
  local label=fromHuman and "HUMAN_LUX_FOR_AI_" or "AI_LUX_FOR_HUMAN_"

  -- Flat gold is the cheapest native candidate to test. v1.0.8 calibrated
  -- one GPT first, spending an evaluation even when the gold deal worked.
  if evals<MAX_EVALS and reset() and AddGold(d,payer,recv,math.ceil(need)) then
    S("AI_"..ai.."_LastPriceStrategy","GOLD_FIRST")
    local o,r=Candidate(d,ai,h,label.."GOLD"); if o then return o,r else why=r end
  end

  local unitGPT,unitWhy=nil,nil
  if evals<MAX_EVALS then
    unitGPT,unitWhy=GPTUnitValue(ai,h,payer,recv)
    if not unitGPT then why=unitWhy end
  end

  if unitGPT and evals<MAX_EVALS and reset() and AddGPT(d,payer,recv,math.max(1,math.ceil(need/unitGPT))) then
    S("AI_"..ai.."_LastPriceStrategy","GPT_AFTER_GOLD")
    local o,r=Candidate(d,ai,h,label.."GPT"); if o then return o,r else why=r end
  end
  if unitGPT and evals<MAX_EVALS and reset() then
    local p=Players[payer]; local gold=math.min(math.floor(need),(p and p.GetGold and (p:GetGold() or 0) or 0))
    local rem=math.max(0,need-gold); local gpt=rem>0 and math.max(1,math.ceil(rem/unitGPT)) or 0
    local added=false
    if gold>0 then added=AddGold(d,payer,recv,gold) or added end
    if gpt>0 then added=AddGPT(d,payer,recv,gpt) or added end
    if added then
      S("AI_"..ai.."_LastPriceStrategy","MIXED_AFTER_GOLD")
      local o,r=Candidate(d,ai,h,label.."MIXED"); if o then return o,r else why=r end
    end
  end
  return nil,why or "NO_SILENT_NATIVE_PRICE_CANDIDATE"
end

local function Swap(ai,h,hr,ar)
  local d=UI.GetScratchDeal(); Prep(d,h,ai)
  if not Possible(d,h,ai,TradeableItems.TRADE_ITEM_RESOURCES,hr,1)
     or not Possible(d,ai,h,TradeableItems.TRADE_ITEM_RESOURCES,ar,1) then return nil,"LUX_SWAP_NOT_POSSIBLE",nil end
  d:AddResourceTrade(h,hr,1,Duration()); d:AddResourceTrade(ai,ar,1,Duration())
  return Candidate(d,ai,h,"LUXURY_FOR_LUXURY")
end

local function SwapBalancePlan(v)
  if not v then return nil end
  local aiDef=math.max(0,(v.aiMy or 0)-(v.aiThey or 0))
  local hDef=math.max(0,(v.hMy or 0)-(v.hThey or 0))
  if aiDef>0 and hDef<=0 then
    local surplus=(v.hThey or 0)-(v.hMy or 0)
    if surplus>=aiDef then return math.max(1,math.ceil(aiDef)),"HUMAN_PAYS" end
  elseif hDef>0 and aiDef<=0 then
    local surplus=(v.aiThey or 0)-(v.aiMy or 0)
    if surplus>=hDef then return math.max(1,math.ceil(hDef)),"AI_PAYS" end
  end
  return nil
end

local function BalancedSwap(ai,h,hr,ar,amount,mode)
  local d=UI.GetScratchDeal(); Prep(d,h,ai)
  if not Possible(d,h,ai,TradeableItems.TRADE_ITEM_RESOURCES,hr,1)
     or not Possible(d,ai,h,TradeableItems.TRADE_ITEM_RESOURCES,ar,1) then return nil,"BALANCED_SWAP_NOT_POSSIBLE" end
  d:AddResourceTrade(h,hr,1,Duration()); d:AddResourceTrade(ai,ar,1,Duration())
  local payer=(mode=="HUMAN_PAYS") and h or ai
  local recv=(payer==h) and ai or h
  if not AddGold(d,payer,recv,amount) then return nil,"BALANCED_SWAP_GOLD_NOT_POSSIBLE" end
  return Candidate(d,ai,h,"LUXURY_SWAP_PLUS_GOLD")
end

local function Rebuild(d,o)
  Prep(d,o.humanID,o.aiID)
  for _,x in ipairs(o.items) do
    if x.itemType==TradeableItems.TRADE_ITEM_GOLD then d:AddGoldTrade(x.fromPlayer,x.data1)
    elseif x.itemType==TradeableItems.TRADE_ITEM_GOLD_PER_TURN then d:AddGoldPerTurnTrade(x.fromPlayer,x.data1,x.duration>0 and x.duration or Duration())
    elseif x.itemType==TradeableItems.TRADE_ITEM_RESOURCES then d:AddResourceTrade(x.fromPlayer,x.data1,math.max(1,x.data2),x.duration>0 and x.duration or Duration()) end
  end
end

local function Show(o)
  if not o or Game.GetActivePlayer()~=o.humanID or not Players[o.humanID]:IsTurnActive() then return false end
  if Game.IsProcessingMessages and Game.IsProcessingMessages() then return false end
  if UI.GetLeaderHeadRootUp then local ok,up=pcall(UI.GetLeaderHeadRootUp); if ok and up then return false end end

  S("NativeUIHeartbeat","DIRECT_TRADE_OPEN_BEGIN")
  S("LastShownAI",o.aiID); S("LastShownTurn",Game.GetGameTurn()); S("LastShownSeed",o.seed)
  local ok,e=pcall(function()
    Players[o.aiID]:DoTradeScreenOpened()
    UI.OnHumanOpenedTradeScreen(o.aiID)
    Rebuild(UI.GetScratchDeal(),o)
    S("NativeUIHeartbeat","DIRECT_SCRATCH_REBUILT")
    Events.AILeaderMessage(o.aiID,DiploUIStateTypes.DIPLO_UI_STATE_TRADE_AI_MAKES_OFFER,
      "I have a trade proposal that I believe is fair to both of us.",-1,0)
  end)
  if not ok then
    S("NativeUIHeartbeat","DIRECT_TRADE_OPEN_ERROR")
    S("NativeUIError",tostring(e))
    pcall(function() Players[o.aiID]:DoTradeScreenClosed(false) end)
    return false
  end
  S("NativeUIHeartbeat","DIRECT_TRADE_OFFER_EVENT_SENT")
  return true
end

local function TryAI(ai,h,turn)
  local hl,al=OfferableLux(h,ai,true),OfferableLux(ai,h,false)
  S("AI_"..ai.."_HumanLuxCount",#hl); S("AI_"..ai.."_AILuxCount",#al)
  S("AI_"..ai.."_HumanLuxIDs",table.concat(hl,",")); S("AI_"..ai.."_AILuxIDs",table.concat(al,","))
  local off=Hash(turn.."|"..ai.."|SEED"); local attempts=0; local why="NO_LUXURY_SEEDS"
  local swapPairs=0; local bestBalance=nil

  -- Test several distinct luxury-for-luxury pairings before expensive pricing.
  -- Each straight swap costs one native evaluation and often mirrors the deal
  -- a human would find immediately by opening the normal diplomacy screen.
  if #hl>0 and #al>0 and evals<MAX_EVALS then
    local total=#hl*#al
    local n=math.min(total,MAX_SWAP_PAIRS)
    local st=off%total
    for k=0,n-1 do
      if evals>=MAX_EVALS then break end
      local pos=(st+k)%total
      local hi=math.floor(pos/#al)+1
      local aii=(pos%#al)+1
      attempts=attempts+1; swapPairs=swapPairs+1
      local o,r,v=Swap(ai,h,hl[hi],al[aii]); why=r
      S("AI_"..ai.."_LastSeedResult",r)
      if o then
        S("AI_"..ai.."_SwapPairsTried",swapPairs); S("AI_"..ai.."_SeedAttempts",attempts)
        return o
      end
      local amount,mode=SwapBalancePlan(v)
      if amount and (not bestBalance or amount<bestBalance.amount) then
        bestBalance={hr=hl[hi],ar=al[aii],amount=amount,mode=mode}
      end
    end
  end
  S("AI_"..ai.."_SwapPairsTried",swapPairs)

  -- If a straight swap was close on native values, try one exact flat-gold
  -- balancing candidate. Candidate() still applies both native fairness gates.
  if bestBalance and evals<MAX_EVALS then
    attempts=attempts+1
    S("AI_"..ai.."_SwapBalanceAmount",bestBalance.amount)
    S("AI_"..ai.."_SwapBalanceMode",bestBalance.mode)
    local o,r=BalancedSwap(ai,h,bestBalance.hr,bestBalance.ar,bestBalance.amount,bestBalance.mode)
    why=r; S("AI_"..ai.."_LastSeedResult",r)
    if o then S("AI_"..ai.."_SeedAttempts",attempts); return o end
  end

  local function list(fromHuman,a)
    local n=math.min(#a,MAX_SEEDS); if n==0 then return nil end
    local st=(off%#a)+1
    for k=0,n-1 do
      if evals>=MAX_EVALS then break end
      attempts=attempts+1; local idx=((st-1+k)%#a)+1
      local o,r=PriceLux(ai,h,fromHuman,a[idx]); why=r; S("AI_"..ai.."_LastSeedResult",r)
      if o then return o end
    end
  end
  local o
  if off%2==0 then o=list(true,hl); if not o then o=list(false,al) end
  else o=list(false,al); if not o then o=list(true,hl) end end
  S("AI_"..ai.."_SeedAttempts",attempts); S("AI_"..ai.."_LastSeedResult",why); return o
end

local function Scan()
  if not Game.IsNetworkMultiPlayer() then Reason("NOT_NETWORK_MULTIPLAYER"); return end
  local h=Game.GetActivePlayer()
  if not HumanMajor(h) then Reason("ACTIVE_PLAYER_NOT_HUMAN_MAJOR"); return end
  if not Players[h]:IsTurnActive() then Reason("TURN_START_NOT_ACTIVE"); return end
  if Game.IsProcessingMessages and Game.IsProcessingMessages() then
    Reason("TURN_START_MESSAGE_QUEUE_BUSY_READY_SIGNAL_ARMED")
    retryArmed=true; retryTurn=Game.GetGameTurn(); retryHuman=h; retrySignals=0; return
  end
  if UI.GetLeaderHeadRootUp then local ok,up=pcall(UI.GetLeaderHeadRootUp); if ok and up then Reason("LEADER_SCREEN_ALREADY_OPEN"); return end end

  local turn=Game.GetGameTurn()
  if turn==lastScanTurn and h==lastScanHuman then Reason("ALREADY_SCANNED_THIS_TURN"); return end
  lastScanTurn,lastScanHuman,evals=turn,h,0
  S("OfferScanTurn",turn); S("OfferScanHuman",h); S("NativeEvalBudget",MAX_EVALS)
  if turn-lastShownTurn<MIN_OFFER_GAP then Reason("LOCAL_OFFER_COOLDOWN"); return end

  local ais=AIs(h); S("OfferScanEligibleAIs",#ais); S("OfferScanEligibleAIIDs",table.concat(ais,","))
  if #ais==0 then Reason("NO_ELIGIBLE_AI"); return end
  local st=(Hash(turn.."|"..h.."|AI")%#ais)+1; local due=0; local ids={}
  for n=0,#ais-1 do
    if evals>=MAX_EVALS then break end
    local ai=ais[((st-1+n)%#ais)+1]
    if Due(ai,h,turn) then
      due=due+1; table.insert(ids,ai); S("OfferDueAIIDs",table.concat(ids,","))
      local o=TryAI(ai,h,turn)
      if o then
        Reason("FAIR_SILENT_NATIVE_CANDIDATE_FOUND"); S("OfferNativeEvals",evals); S("OfferDueAIs",due)
        if Show(o) then lastShownTurn=turn; Reason("DIRECT_NATIVE_OFFER_SENT") else Reason("CANDIDATE_UI_NOT_SAFE") end
        return
      end
    end
  end
  S("OfferNativeEvals",evals); S("OfferDueAIs",due)
  if due==0 then Reason("RELATIONSHIP_SCHEDULE_NOT_DUE")
  elseif evals>=MAX_EVALS then Reason("NATIVE_EVAL_BUDGET_REACHED_NO_VALID_DEAL")
  else Reason("NO_SILENT_NATIVE_FAIR_DEAL") end
end

local Ready
local function Unready(r)
  if retryRegistered and Events.SerialEventGameDataDirty then Events.SerialEventGameDataDirty.Remove(Ready) end
  retryRegistered,retryArmed=false,false
  if r then S("OfferRetryHeartbeat",r) end
end
Ready=function()
  if not retryRegistered then return end
  retrySignals=retrySignals+1; S("OfferRetrySignals",retrySignals)
  if not retryArmed then Unready("READY_SIGNAL_DISARMED"); return end
  if Game.GetGameTurn()~=retryTurn or Game.GetActivePlayer()~=retryHuman then Unready("READY_SIGNAL_TURN_CHANGED"); return end
  if not Players[retryHuman] or not Players[retryHuman]:IsTurnActive() then Unready("READY_SIGNAL_TURN_INACTIVE"); return end
  if Game.IsProcessingMessages and Game.IsProcessingMessages() then S("OfferRetryHeartbeat","READY_SIGNAL_STILL_BUSY"); return end
  Unready("READY_SIGNAL_QUEUE_CLEARED"); Reason("TURN_START_MESSAGE_QUEUE_CLEARED_READY_SIGNAL"); Scan()
end
local function Start()
  Unready(nil); retryTurn,retryHuman,retrySignals=-1,-1,0; Scan()
  if retryArmed then
    if not Events.SerialEventGameDataDirty then Reason("READY_SIGNAL_EVENT_MISSING"); retryArmed=false; return end
    Events.SerialEventGameDataDirty.Add(Ready); retryRegistered=true; S("OfferRetryHeartbeat","READY_SIGNAL_REGISTERED")
  end
end
local function Finish() if retryRegistered or retryArmed then Unready("READY_SIGNAL_CANCELLED_TURN_END") end end
Events.ActivePlayerTurnStart.Add(Start)
if Events.ActivePlayerTurnEnd then Events.ActivePlayerTurnEnd.Add(Finish) end

S("Loaded",1); S("RuntimeVersion",VERSION); S("StateSchemaVersion",DB_VERSION)
S("OfferEngine","SILENT_NATIVE_MULTI_SWAP_CANDIDATES_V110")
S("AllowedItems","LUXURY_GOLD_GPT_ONLY_V110"); S("StrategicResources","NEVER")
S("HumanFairness","HUMAN_NATIVE_THEY_VALUE_GTE_MY_VALUE_V110")
S("PerformanceModel","ONE_TURN_SCAN_MAX_8_NATIVE_EVALS_MULTI_SWAP_LAZY_GPT_V110")
S("NativeUIBridge","DIRECT_TRADE_STATE_NO_DEFAULT_ROOT_NO_DOBEGINDIPLO_V110")
S("RelationshipModel","LOOSER_FREQUENCY_NATIVE_PRICE")
print("LEK Fair Trades v1.0.10: ready")
