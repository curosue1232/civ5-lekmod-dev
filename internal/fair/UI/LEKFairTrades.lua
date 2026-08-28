-- LEKMOD 30.7 Fair Trades v1.0.9
-- Silent native-value proactive trade engine for frozen LEK Core v1.3.
-- Direct native trade-offer handoff: never opens the default leader/greeting state.

print("LEK Fair Trades v1.0.9: loading")
ContextPtr:SetHide(true)
MapModData = MapModData or {}

local VERSION=109
local DB_VERSION=1
local MAX_EVALS=8
local MAX_SEEDS=2
local MIN_OFFER_GAP=2

if MapModData.LEK_FAIR_TRADES_RUNTIME_VERSION==VERSION then return end
MapModData.LEK_FAIR_TRADES_RUNTIME_VERSION=VERSION

local db=nil
pcall(function() db=Modding.OpenUserData("LEK_FAIR_TRADES",DB_VERSION) end)
local function S(k,v) if db then pcall(function() db.SetValue(k,v) end) end end

-- LEK_FAIR_TRADES_EUI_LUX_BRIDGE_V109
S("RuntimePatch","V109_EUI_LUX_OFFER_BRIDGE")
S("AILuxuryOfferPolicy","ALLOW_SINGLE_COPY_IF_NATIVE_LEGAL_AND_FAIR")
S("HumanLuxuryOfferPolicy","PRESERVE_LAST_COPY")
S("LoadSafety","WAIT_FOR_REAL_HUMAN_TURN_START")
S("OfferScanReason","V108_LOADED_WAITING_FOR_REAL_TURN_START")
S("OfferScanTrail","")
S("OfferScanTurn",-1)
S("OfferNativeEvals",0)
S("OfferDueAIs",0)
S("OfferDueAIIDs","")
S("NativeUIHeartbeat","IDLE")

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
  local ok,why=Structural(items,ai,h); if not ok then return nil,why end
  local v; v,why=Values(d,ai,h); if not v then return nil,why end
  S("AI_"..ai.."_LastAIValueMy",v.aiMy); S("AI_"..ai.."_LastAIValueThey",v.aiThey)
  S("AI_"..ai.."_LastHumanValueMy",v.hMy); S("AI_"..ai.."_LastHumanValueThey",v.hThey)
  ok,why=Accepted(v); if not ok then return nil,why end
  return {aiID=ai,humanID=h,items=items,aiGives=v.hThey,humanGives=v.hMy,seed=name},"OK"
end

local function AddGold(d,from,to,n)
  n=math.floor(n or 0); local p=Players[from]
  if n<=0 or not p or not p.GetGold or (p:GetGold() or 0)<n then return false end
  if not Possible(d,from,to,TradeableItems.TRADE_ITEM_GOLD,n,0) then return false end
  d:AddGoldTrade(from,n); return true
end
local function AddGPT(d,from,to,n)
  n=math.floor(n or 0); if n<=0 then return false end
  if not Possible(d,from,to,TradeableItems.TRADE_ITEM_GOLD_PER_TURN,n+0,0) then return false end
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

  local unitGPT,unitWhy=GPTValue(ai,h,payer,recv)
  if not unitGPT then why=unitWhy end

  local function reset()
    Prep(d,h,ai); local from=fromHuman and h or ai; local to=fromHuman and ai or h
    if not Possible(d,from,to,TradeableItems.TRADE_ITEM_RESOURCES,res,1) then return false end
    d:AddResourceTrade(from,res,1,Duration()); return true
  end
  local label=fromHuman and "HUMAN_LUX_FOR_AI_" or "AI_LUX_FOR_HUMAN_"

  if evals<MAX_EVALS and reset() and AddGold(d,payer,recv,math.ceil(need)) then
    local o,r=Candidate(d,ai,h,label.."GOLD"); if o then return o,r else why=r end
  end
  if unitGPT and evals<MAX_EVALS and reset() and AddGPT(d,payer,recv,math.max(1,math.ceil(need/unitGPT))) or then
    local o,r=Candidate(d,ai,h,label.."GPT"); if o then return o,r else why=r end
  end
  if unitGPT and evals<MAX_EVALS and reset() then
    local p=Players[payer]; local gold=math.min(math.floor(need),(p and p.GetGold and (p:GetGold() or 0) or 0))
    local rem=math.max(0,need-gold); local gpt=rem>0 and math.max(1,math.ceil(rem/unitGPT)) or 0
    local added=false
    if gold>0 then added=AddGold(d,payer,recv,gold) or added end
    if gpt>0 then added=AddGPT(d,payer,recv,gpt) or added end
    if added then local o,r=Candidate(d,ai,h,label.."MIXED"); if o then return o,r else why=r end end
  end
  return nil,why or "NO_SILENT_NATIVE_PRICE_CANDIDATE"
end

local function Swap(ai,h,hr,ar)
  local d=UI.GetScratchDeal(); Prep(d,h,ai)
  if not Possible(d,h,ai,TradeableItems.TRADE_ITEM_RESOURCES,hr,1)
     or not Possible(d,ai,h,TradeableItems.TRADE_ITEM_RESOURCES,ar,1) then return nil,"LUX_SWAP_NOT_POSSIBLE" end
  d:AddResourceTrade(h,hr,1,Duration()); d:AddResourceTrade(ai,ar,1,Duration())
  return Candidate(d,ai,h,"LUXURY_FOR_LUXURY")
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
  if not o or Game.GetActivePlayer()~=o.humanID or not Players[Лљ[X[’QN’\Х\›ђXЭ]™J
H[€™]\›€[ЩH[™€Y€Ш[YK’\Ф›ШЩ\ЬЪ[™УY\ЬШYЩ\И[™Ш[YK’\Ф›ШЩ\ЬЪ[™УY\ЬШYЩ\К
H[€™]\›€[ЩH[™€Y€RK‘Щ]XY\’XY›ЫЭ\[€ШШ[ЪЛ\\Ш[
RK‘Щ]XY\’XY›ЫЭ\
NИY€ЪИ[™\[€™]\›€[ЩH[™[™‚€К“]]™URRX\ќ™X]‹‘T‘PХХђQWУФS—Р‘QТS€ЉB€К“\ЭЪЭЫђRH‹ЛZRQ
NИК“\ЭЪЭЫ•\›€‹Ш[YK‘Щ]Ш[YU\›Љ
JNИК“\ЭЪЭЫ”ЩYY‹ЛњЩYY
B€KHH[њЭ[YURH[ќ[ќ[Ы[H\ШШ\™ИЬ™[\ћHRH^\ћHЩ™™\њЛ‚€KHZ\€Y\ИX\љЬИЫ›H]И[™XYK][Y]YЮ[ќ]XИЩ™™\€ЫИH[ћB€KHYSЩЪXИњљYЩHШ[€]\ИЫ™HЩ™™\€›ЭYЪЪ]Э]™KY[X›[™ИЪ]\‹‚€X\[Щ]K“RЧСђRT—ХђQTЧРSХЧУVУС‘‘TЏ^ШZRQ[ЛZRQ\›ЏQШ[YK‘Щ]Ш[YU\›Љ
_B€К“]]™URRX\ќ™X]‹‘URWРSХЧС“QЧРT“QQЉB€ШШ[ЪЛO\Ш[
ќ[Э[ЫЉ
B€^Y\њЦЫЛZRQN‘ХYTШЬ™Y[“Ь[™Y

B€RK“Ы–[X[“Ь[™YYTШЬ™Y[ЉЛZRQ
B€™XќZ[
RK‘Щ]ШЬ]ЪX[

KКB€К“]]™URRX\ќ™X]‹‘T‘PХФРФђUТФ‘P•RSЉB€]™[ќЛђRSXY\“Y\ЬШYЩJЛZRQ\ХRTЭ]U\\Л‘TЧХRWФХUWХђQWРRWУPRСTЧУС‘‘T‹€’H
]™HHYH›ЬЬШ[]H™[Y]™H\ИZ\€И›ЭЩ€\Л€‹LK
B€[™
B€X\[Щ]K“RЧСђRT—ХђQTЧРSХЧУVУС‘‘TЏ[љ[€Y€›ЭЪИ[‚€К“]]™URRX\ќ™X]‹‘T‘PХХђQWУФS—СT”“Ф€ЉB€К“]]™URQ\њ›Ь€‹ЬЭљ[™КJJB€Ш[
ќ[Э[ЫЉ
H^Y\њЦЫЛZRQN‘ХYTШЬ™Y[ђЫЬЩY
[ЩJH[™
B€™]\›€[ЩB€[™€К“]]™URRX\ќ™X]‹‘URWХђQWУС‘‘T—СU‘S•ФСS•ЉB€™]\›€ќYB™[™‚›ШШ[ќ[Э[Ы€ћPRJZK\›ЉB€ШШ[[SЩ™™\X›S^
ZKќYJKЩ™™\X›S^
ZK[ЩJB€КђRWИ‹‹ZK‹€—Т[X[“^ЫЭ[ќ‹Ъ
NИКђRWИ‹‹ZK‹€—РRS^ЫЭ[ќ‹Ш[
B€КђRWИ‹‹ZK‹€—Т[X[“^QИ‹X›KЫЫШ]
‹ЉJNИКђRWИ‹‹ZK‹€—РRS^QИ‹X›KЫЫШ]
[‹ЉJB€ШШ[Щ™ЏR\Ъ
\›‹‹€џ‹‹ZK‹€џСQQЉNИШШ[][\ПLИШШ[ЪOH““ЧУVT–WФСQQИ‚€Y€ЪЊ[™Ш[Њ[™][ПPVСUђSИ[‚€][\ПX][\КМNИШШ[ЛЏTЭШ\
ZKКЩ™‰HЪ
JМWK[КЩ™‰HШ[
JМWJNИЪO\‚€Y€И[€КђRWИ‹‹ZK‹€—ФЩYY][\И‹][\КNИ™]\›€И[™€[™€ШШ[ќ[Э[Ы€\Э
њ›ЫR[X[‹JB€ШШ[Џ[X]›Z[ЉШKPVФСQQКNИY€ЏOL[€™]\›€љ[[™€ШШ[ЭJЩ™‰HШJJМB€›Ь€ПL‹LHВ€Y€][ПЏSPVСUђSИ[€њ™XZИ[™€][\ПX][\КМNИШШ[YJ
ЭLJЪКIHШJJМB€ШШ[ЛЏTљXЩS^
ZKњ›ЫR[X[‹VЪYJNИЪO\ЋИКђRWИ‹‹ZK‹€—У\ЭЩYY™\Э[‹ЉB€Y€И[€™]\›€И[™€[™€[™€ШШ[В€Y€Щ™‰LЏOL[€П[\Э
ќYK
NИY€›ЭИ[€П[\Э
[ЩK[
H[™€[ЩHП[\Э
[ЩK[
NИY€›ЭИ[€П[\Э
ќYK
H[™[™€КђRWИ‹‹ZK‹€—ФЩYY][\И‹][\КNИКђRWИ‹‹ZK‹€—У\ЭЩYY™\Э[‹ЪJNИ™]\›€В™[™‚›ШШ[ќ[Э[Ы€ШШ[Љ
B€Y€›ЭШ[YK’\У™]ЫЬљУ][T^Y\Љ
H[€™X\ЫЫЉ““ХУ‘UУФ’ЧУUSTVQT€ЉNИ™]\›€[™€ШШ[QШ[YK‘Щ]XЭ]™T^Y\Љ
B€Y€›Э[X[“XZ›ЬЉ
H[€™X\ЫЫЉђPХU‘WФVQT—У“ХТSPS—УPR“Ф€ЉNИ™]\›€[™€Y€›Э^Y\њЦЪN’\Х\›ђXЭ]™J
H[€™X\ЫЫЉ•T“—ФХT•У“ХРPХU‘HЉNИ™]\›€[™€Y€Ш[YK’\Ф›ШЩ\ЬЪ[™УY\ЬШYЩ\И[™Ш[YK’\Ф›ШЩ\ЬЪ[™УY\ЬШYЩ\К
H[‚€™X\ЫЫЉ•T“—ФХT•УQTФРQСWФUQUQWР•TЦWФ‘PQWФТQУђSРT“QQЉB€™]ћP\›YY]ќYNИ™]ћU\›ЏQШ[YK‘Щ]Ш[YU\›Љ
NИ™]ћR[X[ЏZИ™]ћTЪYЫ[ПLИ™]\›‚€[™€Y€RK‘Щ]XY\’XY›ЫЭ\[€ШШ[ЪЛ\\Ш[
RK‘Щ]XY\’XY›ЫЭ\
NИY€ЪИ[™\[€™X\ЫЫЉ“PQT—ФРФ‘QS—РS‘PQWУФS€ЉNИ™]\›€[™[™‚€ШШ[\›ЏQШ[YK‘Щ]Ш[YU\›Љ
B€Y€\›ЏO[\ЭШШ[•\›€[™O[\ЭШШ[’[X[€[€™X\ЫЫЉђS‘PQWФРРS“‘QХTЧХT“€ЉNИ™]\›€[™€\ЭШШ[•\›‹\ЭШШ[’[X[‹][П]\›‹€К“Щ™™\”ШШ[•\›€‹\›ЉNИК“Щ™™\”ШШ[’[X[€‹
NИК“]]™Q][ќYЩ]‹PVСUђSКB€Y€\›‹[\ЭЪЭЫ•\›ЏRS—УС‘‘T—СРT[€™X\ЫЫЉ“РРSУС‘‘T—РУУУХУ€ЉNИ™]\›€[™‚€ШШ[Z\ПPR\К
NИК“Щ™™\”ШШ[‘[YЪX›PR\И‹ШZ\КNИК“Щ™™\”ШШ[‘[YЪX›PRRQИ‹X›KЫЫШ]
Z\Л‹ЉJB€Y€ШZ\ПOL[€™X\ЫЫЉ““ЧСSQТP“WРRHЉNИ™]\›€[™€ШШ[ЭJ\Ъ
\›‹‹€џ‹‹љ‹€џRHЉIHШZ\КJМNИШШ[YOLИШШ[YП^ЯB€›Ь€ЏLШZ\ЛLHВ€Y€][ПЏSPVСUђSИ[€њ™XZИ[™€ШШ[ZOXZ\ЦК
ЭLJЫЉIHШZ\КJМWB€Y€YJZK\›ЉH[‚€YOYYJМNИX›Kљ[њЩ\ќ
YЛZJNИК“Щ™™\‘YPRRQИ‹X›KЫЫШ]
YЛ‹ЉJB€ШШ[ПUћPRJZK\›ЉB€Y€И[‚€™X\ЫЫЉ‘ђRT—ФТSS•УђUU‘WРРS‘QUWС“ХS‘ЉNИК“Щ™™\“]]™Q][И‹][КNИК“Щ™™\‘YPR\И‹YJB€Y€ЪЭККH[€\ЭЪЭЫ•\›Џ]\›ЋИ™X\ЫЫЉ‘T‘PХУђUU‘WУС‘‘T—ФСS•ЉH[ЩH™X\ЫЫЉђРS‘QUWХRWУ“ХФРQ‘HЉH[™€™]\›‚€[™€[™€[™€К“Щ™™\“]]™Q][И‹][КNИК“Щ™™\‘YPR\И‹YJB€Y€YOOL[€™X\ЫЫЉ”‘SUSУ”ТTФРТQSWУ“ХСQHЉB€[ЩZY€][ПЏSPVСUђSИ[€™X\ЫЫЉ“ђUU‘WСUђSР•QСUФ‘PPТQУ“ЧХђSQСPSЉB€[ЩH™X\ЫЫЉ““ЧФТSS•УђUU‘WСђRT—СPSЉH[™™[™‚›ШШ[™XYB›ШШ[ќ[Э[Ы€[њ™XYJЉB€Y€™]ћT™YЪ\Э\™Y[™]™[ќЛ”Щ\љX[]™[ќШ[YQ]Q\ќH[€]™[ќЛ”Щ\љX[]™[ќШ[YQ]Q\ќK”™[[Э™J™XYJH[™€™]ћT™YЪ\Э\™Y™]ћP\›YYY[ЩK[ЩB€Y€€[€К“Щ™™\”™]ћRX\ќ™X]‹ЉH[™™[™”™XYOYќ[Э[ЫЉ
B€Y€›Э™]ћT™YЪ\Э\™Y[€™]\›€[™€™]ћTЪYЫ[П\™]ћTЪYЫ[КМNИК“Щ™™\”™]ћTЪYЫ[И‹™]ћTЪYЫ[КB€Y€›Э™]ћP\›YY[€[њ™XYJ”‘PQWФТQУђSСTРT“QQЉNИ™]\›€[™€Y€Ш[YK‘Щ]Ш[YU\›Љ
_Џ\™]ћU\›€Ь€Ш[YK‘Щ]XЭ]™T^Y\Љ
_Џ\™]ћR[X[€[€[њ™XYJ”‘PQWФТQУђSХT“—РТS‘СQЉNИ™]\›€[™€Y€›Э^Y\њЦЬ™]ћR[X[—HЬ€›Э^Y\њЦЬ™]ћR[X[—N’\Х\›ђXЭ]™J
H[€[њ™XYJ”‘PQWФТQУђSХT“—ТSђPХU‘HЉNИ™]\›€[™€Y€Ш[YK’\Ф›ШЩ\ЬЪ[™УY\ЬШYЩ\И[™Ш[YK’\Ф›ШЩ\ЬЪ[™УY\ЬШYЩ\К
H[€К“Щ™™\”™]ћRX\ќ™X]‹”‘PQWФТQУђSФХSР•TЦHЉNИ™]\›€[™€[њ™XYJ”‘PQWФТQУђSФUQUQWРУPT‘QЉNИ™X\ЫЫЉ•T“—ФХT•УQTФРQСWФUQUQWРУPT‘QФ‘PQWФТQУђSЉNИШШ[Љ
B™[™›ШШ[ќ[Э[Ы€Э\ќ

B€[њ™XYJљ[
NИ™]ћU\›‹™]ћR[X[‹™]ћTЪYЫ[ПKLKLKИШШ[Љ
B€Y€™]ћP\›YY[‚€Y€›Э]™[ќЛ”Щ\љX[]™[ќШ[YQ]Q\ќH[€™X\ЫЫЉ”‘PQWФТQУђSСU‘S•УRTФТS‘ИЉNИ™]ћP\›YYY[ЩNИ™]\›€[™€]™[ќЛ”Щ\љX[]™[ќШ[YQ]Q\ќKђY
™XYJNИ™]ћT™YЪ\Э\™Y]ќYNИК“Щ™™\”™]ћRX\ќ™X]‹”‘PQWФТQУђSФ‘QТTХT‘QЉB€[™™[™›ШШ[ќ[Э[Ы€љ[љ\Ъ

HY€™]ћT™YЪ\Э\™YЬ€™]ћP\›YY[€[њ™XYJ”‘PQWФТQУђSРРSђСSQХT“—СS‘ЉH[™[™‘]™[ќЛђXЭ]™T^Y\•\›”Э\ќђY
Э\ќ
BљY€]™[ќЛђXЭ]™T^Y\•\›‘[™[€]™[ќЛђXЭ]™T^Y\•\›‘[™ђY
љ[љ\Ъ
H[™‚”К“ШYY‹JNИК”ќ[ќ[YU™\њЪ[Ы€‹‘T”ТSУЉNИК”Э]TШЪ[XU™\њЪ[Ы€‹—Х‘T”ТSУЉB”К“Щ™™\‘[™Ъ[™H‹”ТSS•УђUU‘WФТQWХђSPUSУ—РРS‘QUTЧХЊLЉB”Кђ[ЭЩY][\И‹“VT–WСУУСФУУ“WХЊLЉNИК”Э]YЪXФ™\ЫЭ\Щ\И‹“‘U‘T€ЉB”К’[X[‘Z\›™\ЬИ‹’SPS—УђUU‘WХVWХђSQWСХWУVWХђSQWХЊLЉB”К”\™›Ь›X[ЩS[Щ[‹“У‘WХT“—ФРРS—УPVОУђUU‘WСUђSЧХђS”ТQS•Ф‘PQWФТQУђSХЊLЉB”К“]]™URPњљYЩH‹‘URWХђQSСТPЧРSХЧС“QЧУ“ЧСQђUSФ“УХХЊLHЉB”К”™[][ЫњЪ\[Щ[‹“УФСT—С”‘TUQSђЦWУђUU‘WФ’PСHЉBњљ[ќ
“RИZ\€Y\ИЊKЊЋN€™XYHЉ