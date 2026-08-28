-- LEKMOD 30.7 Fair Trades v1.0.7 SAFE DIAGNOSTIC
-- Crash-isolation observer for frozen LEK Core v1.3.
-- IMPORTANT: this build never opens, hooks, rewrites, or injects diplomacy UI.
-- It only records eligible AIs and duplicate-luxury inventory at real human turn start.

print("LEK Fair Trades v1.0.7 SAFE DIAGNOSTIC: loading")
ContextPtr:SetHide(true)
MapModData = MapModData or {}

local VERSION = 107
local DB_VERSION = 1

if MapModData.LEK_FAIR_TRADES_RUNTIME_VERSION == VERSION then return end
MapModData.LEK_FAIR_TRADES_RUNTIME_VERSION = VERSION

local db = nil
pcall(function() db = Modding.OpenUserData("LEK_FAIR_TRADES", DB_VERSION) end)
local function S(k,v)
  if db then pcall(function() db.SetValue(k,v) end) end
end

-- LEK_FAIR_TRADES_SAFE_OBSERVER_V107
S("Loaded",1)
S("RuntimeVersion",VERSION)
S("StateSchemaVersion",DB_VERSION)
S("RuntimePatch","V107_SAFE_OBSERVER_NO_DIPLOMACY")
S("OfferEngine","SAFE_OBSERVER_INVENTORY_ONLY_V107")
S("NativeUIBridge","DISABLED_FOR_CRASH_ISOLATION")
S("LoadSafety","NO_LOADTIME_SCAN_NO_DIPLOMACY_HOOK")
S("PerformanceModel","ONE_REAL_TURN_EVENT_INVENTORY_ONLY")
S("AllowedItems","OBSERVE_LUXURY_INVENTORY_ONLY")
S("StrategicResources","NEVER")
S("OfferScanReason","V107_LOADED_WAITING_FOR_REAL_TURN_START")
S("OfferScanTrail","")
S("OfferScanTurn",-1)
S("ObserverWouldHaveTradePairs",0)

local trail = {}
local lastTurn = -99999
local lastHuman = -1

local function Reason(r)
  S("OfferScanReason",r)
  local t,h=-1,-1
  pcall(function() t=Game.GetGameTurn() end)
  pcall(function() h=Game.GetActivePlayer() end)
  table.insert(trail,tostring(t)..":"..tostring(h)..":"..tostring(r))
  while #trail > 16 do table.remove(trail,1) end
  S("OfferScanTrail",table.concat(trail," | "))
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

local function CanTrade(ai,h)
  if not AIMajor(ai) or not HumanMajor(h) then return false end
  local ap,hp=Players[ai],Players[h]
  local team=Teams[ap:GetTeam()]
  if not team:IsHasMet(hp:GetTeam()) then return false end
  if team:IsAtWar(hp:GetTeam()) then return false end
  if ap.IsTradeSanctioned then
    local ok,v=pcall(function() return ap:IsTradeSanctioned(h) end)
    if ok and v then return false end
  end
  return true
end

local function SpareLux(playerID,otherID)
  local p,o=Players[playerID],Players[otherID]
  local out={}
  if not p or not o then return out end
  for r in GameInfo.Resources() do
    if Luxury(r.ID) then
      local ours=p:GetNumResourceAvailable(r.ID,true) or 0
      local theirs=o:GetNumResourceAvailable(r.ID,true) or 0
      if ours>1 and theirs<=0 then table.insert(out,r.ID) end
    end
  end
  table.sort(out)
  return out
end

local function Scan()
  if not Game.IsNetworkMultiPlayer() then
    Reason("NOT_NETWORK_MULTIPLAYER")
    return
  end

  local h=Game.GetActivePlayer()
  if not HumanMajor(h) then
    Reason("ACTIVE_PLAYER_NOT_HUMAN_MAJOR")
    return
  end
  if not Players[h]:IsTurnActive() then
    Reason("TURN_START_NOT_ACTIVE")
    return
  end

  local turn=Game.GetGameTurn()
  if turn==lastTurn and h==lastHuman then
    Reason("ALREADY_OBSERVED_THIS_TURN")
    return
  end
  lastTurn,lastHuman=turn,h

  S("OfferScanTurn",turn)
  S("OfferScanHuman",h)

  local eligible={}
  local possiblePairs=0

  for ai=0,GameDefines.MAX_MAJOR_CIVS-1 do
    if CanTrade(ai,h) then
      table.insert(eligible,ai)

      local hl=SpareLux(h,ai)
      local al=SpareLux(ai,h)
      local a=Approach(ai,h)

      S("AI_"..ai.."_Approach",ApproachName(a))
      S("AI_"..ai.."_HumanLuxCount",#hl)
      S("AI_"..ai.."_AILuxCount",#al)
      S("AI_"..ai.."_HumanLuxIDs",table.concat(hl,","))
      S("AI_"..ai.."_AILuxIDs",table.concat(al,","))

      if #hl>0 or #al>0 then possiblePairs=possiblePairs+1 end
    end
  end

  S("OfferScanEligibleAIs",#eligible)
  S("OfferScanEligibleAIIDs",table.concat(eligible,","))
  S("ObserverWouldHaveTradePairs",possiblePairs)

  if #eligible==0 then
    Reason("NO_ELIGIBLE_AI")
  elseif possiblePairs==0 then
    Reason("SAFE_OBSERVER_NO_DUPLICATE_LUXURY_OPPORTUNITY")
  else
    Reason("SAFE_OBSERVER_TRADE_OPPORTUNITY_PRESENT")
  end
end

-- Real turn start only. No load bootstrap, no dirty-event retry, no frame update.
Events.ActivePlayerTurnStart.Add(Scan)

print("LEK Fair Trades v1.0.7 SAFE DIAGNOSTIC: ready")
