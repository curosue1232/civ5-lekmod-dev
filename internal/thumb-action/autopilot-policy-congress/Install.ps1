param([string]$CivPath='')
$ErrorActionPreference='Stop'
$Internal=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $Internal 'LekTools.ps1')
$PB='-- LEK_EXT_SPACE_AUTOPILOT_POLICY_V04_BEGIN'; $PE='-- LEK_EXT_SPACE_AUTOPILOT_POLICY_V04_END'
$LB='-- LEK_EXT_SPACE_AUTOPILOT_LEAGUE_V04_BEGIN'; $LE='-- LEK_EXT_SPACE_AUTOPILOT_LEAGUE_V04_END'
$NB='-- LEK_EXT_SPACE_AUTOPILOT_PANTHEON_V05_BEGIN'; $NE='-- LEK_EXT_SPACE_AUTOPILOT_PANTHEON_V05_END'
$RB='-- LEK_EXT_SPACE_AUTOPILOT_RELIGION_V06_BEGIN'; $RE='-- LEK_EXT_SPACE_AUTOPILOT_RELIGION_V06_END'
$FB='-- LEK_EXT_SPACE_AUTOPILOT_FREEITEM_V07_BEGIN'; $FE='-- LEK_EXT_SPACE_AUTOPILOT_FREEITEM_V07_END'
$GB='-- LEK_EXT_SPACE_AUTOPILOT_FAITHGP_V07_BEGIN'; $GE='-- LEK_EXT_SPACE_AUTOPILOT_FAITHGP_V07_END'
$MB='-- LEK_EXT_SPACE_AUTOPILOT_MAYA_V07_BEGIN'; $ME='-- LEK_EXT_SPACE_AUTOPILOT_MAYA_V07_END'
$AB='-- LEK_EXT_SPACE_AUTOPILOT_ARCHAEOLOGY_V07_BEGIN'; $AE='-- LEK_EXT_SPACE_AUTOPILOT_ARCHAEOLOGY_V07_END'
$CB='-- LEK_EXT_SPACE_AUTOPILOT_CITYCAPTURE_V07_BEGIN'; $CE='-- LEK_EXT_SPACE_AUTOPILOT_CITYCAPTURE_V07_END'
$IB='-- LEK_EXT_SPACE_AUTOPILOT_IDEOLOGY_V08_BEGIN'; $IE='-- LEK_EXT_SPACE_AUTOPILOT_IDEOLOGY_V08_END'
function Insert-Before([string]$text,[string]$needle,[string]$block){ $i=$text.IndexOf($needle,[StringComparison]::Ordinal); if($i-lt 0){throw "Missing anchor: $needle"}; $text.Insert($i,$block+"`r`n") }
try {
 if(Test-LEKCivRunning){throw 'Civilization V appears to be running. Close it before installing.'}; $civ=Find-LEKCivV $CivPath; if(!$civ){throw 'Civilization V install folder not found.'}
 $backup=Join-Path (Split-Path $Internal -Parent) 'local\backups\thumb-action'
 $policy=Join-LEKPath $civ 'Assets\DLC\UI_bc1\Improvements\SocialPolicyPopup.lua'; $t=[IO.File]::ReadAllText($policy); if(!$t.Contains('ContextPtr:SetInputHandler( InputHandler );')){throw 'Unexpected SocialPolicyPopup layout.'}; Backup-LEKFileOnce $policy $backup 'SocialPolicyPopup.lua'|Out-Null; $t=Remove-LEKMarkedBlock $t $PB $PE
 $body=@'
local LEKAutopilotDB=nil
pcall(function() LEKAutopilotDB=Modding.OpenUserData("LEK_SPACE_AUTOPILOT",1) end)
local function LEKAutopilotLog(k,v) if LEKAutopilotDB then pcall(function() LEKAutopilotDB.SetValue(k,v) end) end end
local function LEKSpacePolicyWeights(player)
 local w,leader={},GameInfo.Leaders[player:GetLeaderType()]
 if leader then for row in GameInfo.Leader_Flavors{LeaderType=leader.Type} do w[row.FlavorType]=row.Flavor or 0 end end
 return w
end
local function LEKSpacePolicyScore(policy,w)
 local score=0; for row in GameInfo.Policy_Flavors{PolicyType=policy.Type} do score=score+(w[row.FlavorType] or 0)*(row.Flavor or 0) end; return score
end
local function LEKSpacePolicyBetter(p,s,b,bs) return not b or s>bs or (s==bs and p.Type<b.Type) end
local function LEKSpaceFinishPolicy()
 LuaEvents.LEKSpaceAutomateModalHandled(1.7)
 OnClose()
 -- EUI's queue dequeue can leave this context visibly alive when called
 -- from a cross-context LuaEvent. Force the same hide transition that its
 -- ShowHideHandler uses to acknowledge BUTTONPOPUP_CHOOSEPOLICY.
 if not ContextPtr:IsHidden() then ContextPtr:SetHide(true) end
end
local function LEKSpaceChoosePolicy()
 LEKAutopilotLog("PC_LastPressTurn",Game.GetGameTurn())
 local player=Players[Game.GetActivePlayer()]; if not player or not player:IsTurnActive() or Game.IsProcessingMessages() then LEKAutopilotLog("PC_LastResult","PLAYER_TURN_NOT_ACTIVE");return false end
 if not Controls.TenetConfirm:IsHidden() then LEKAutopilotLog("PC_LastResult","CONFIRMED_TENET");OnTenetConfirmYes(); LEKSpaceFinishPolicy(); return true end
 if not Controls.PolicyConfirm:IsHidden() then LEKAutopilotLog("PC_LastResult","CONFIRMED_POLICY");OnYes(); LEKSpaceFinishPolicy(); return true end
 if not Controls.ChangeIdeologyConfirm:IsHidden() then LEKAutopilotLog("PC_LastResult","CONFIRMED_IDEOLOGY_CHANGE_ALREADY_OPEN");OnChangeIdeologyConfirmYes(); return true end
 -- The switch target isn't a free strategic pick -- Network.SendChangeIdeology()
 -- always moves to whatever GetPublicOpinionPreferredIdeology() computes from
 -- world pressure. Initiating one only happens under the exact condition that
 -- would enable the native Switch Ideology button itself (an existing ideology
 -- plus active public-opinion unhappiness); the confirm opened here is picked
 -- up by the check above on the next press.
 if bnw_mode and player:GetLateGamePolicyTree()>=0 and player:GetPublicOpinionUnhappiness()>0 then
  LEKAutopilotLog("PC_LastResult","INITIATED_IDEOLOGY_SWITCH")
  ChooseChangeIdeology(); return true
 end
 local w,best,bs=LEKSpacePolicyWeights(player),nil,nil
 if bnw_mode and player:GetLateGamePolicyTree()>=0 then
  for level=1,3 do for _,id in ipairs(player:GetAvailableTenets(level)) do local p=GameInfo.Policies[id]; if p then local s=LEKSpacePolicyScore(p,w); if LEKSpacePolicyBetter(p,s,best,bs) then best,bs=p,s end end end end
  if best then
   LEKAutopilotLog("PC_LastResult","ADOPTED_TENET");LEKAutopilotLog("PC_LastPolicyID",best.ID)
   Network.SendUpdatePolicies(best.ID,true,true); Events.AudioPlay2DSound("AS2D_INTERFACE_POLICY"); LEKSpaceFinishPolicy(); return true
  end
 end
 best,bs=nil,nil
 for p in GameInfo.Policies() do if (not p.Level or p.Level<=0) and player:CanAdoptPolicy(p.ID) and not player:IsPolicyBlocked(p.ID) then local s=LEKSpacePolicyScore(p,w); if LEKSpacePolicyBetter(p,s,best,bs) then best,bs=p,s end end end
 if best then
  LEKAutopilotLog("PC_LastResult","ADOPTED_POLICY");LEKAutopilotLog("PC_LastPolicyID",best.ID)
  Network.SendUpdatePolicies(best.ID,true,true); Events.AudioPlay2DSound("AS2D_INTERFACE_POLICY"); LEKSpaceFinishPolicy(); return true
 end
 local branch,bscore=nil,nil
 for br in GameInfo.PolicyBranchTypes() do
  if player:CanUnlockPolicyBranch(br.ID) and not player:IsPolicyBranchBlocked(br.ID) and not player:IsPolicyBranchUnlocked(br.ID) then
   local s=0; for p in GameInfo.Policies{PolicyBranchType=br.Type} do s=s+LEKSpacePolicyScore(p,w) end
   if not branch or s>bscore or (s==bscore and br.Type<branch.Type) then branch,bscore=br,s end
  end
 end
 if branch then
  LEKAutopilotLog("PC_LastResult","UNLOCKED_BRANCH");LEKAutopilotLog("PC_LastBranchID",branch.ID)
  Network.SendUpdatePolicies(branch.ID,false,true); Events.AudioPlay2DSound("AS2D_INTERFACE_POLICY"); LEKSpaceFinishPolicy(); return true
 end
 -- Nothing left to legally adopt right now -- close the screen instead of
 -- leaving Space with nothing more to do on it.
 LEKAutopilotLog("PC_LastResult","NO_LEGAL_CHOICE_CLOSING")
 LEKSpaceFinishPolicy()
 return true
end
local LEKSpaceOriginalPolicyInput=InputHandler
function InputHandler(uiMsg,wParam)
 if uiMsg==KeyEvents.KeyDown and wParam==Keys.VK_SPACE and LEKSpaceChoosePolicy() then return true end
 return LEKSpaceOriginalPolicyInput(uiMsg,wParam)
end
LuaEvents.LEKSpaceAutomateTick.Add(function()
 if not ContextPtr:IsHidden() then
  LuaEvents.LEKSpaceAutomateModalHandled(1.7)
  local ok,err=pcall(LEKSpaceChoosePolicy)
 end
end)
'@
 $t=Insert-Before $t 'ContextPtr:SetInputHandler( InputHandler );' "$PB`r`n$($body.Trim())`r`n$PE`r`n"; Write-LEKUtf8NoBom $policy $t
 $league=Join-LEKPath $civ 'Assets\DLC\Expansion2\UI\InGame\Popups\LeagueOverview.lua'; $t=[IO.File]::ReadAllText($league); if(!$t.Contains('ContextPtr:SetInputHandler( InputHandler );')){throw 'Unexpected LeagueOverview layout.'}; Backup-LEKFileOnce $league $backup 'LeagueOverview.lua'|Out-Null; $t=Remove-LEKMarkedBlock $t $LB $LE
 $body=@'
local LEKAutopilotDB=nil
pcall(function() LEKAutopilotDB=Modding.OpenUserData("LEK_SPACE_AUTOPILOT",1) end)
local function LEKAutopilotLog(k,v) if LEKAutopilotDB then pcall(function() LEKAutopilotDB.SetValue(k,v) end) end end
local function LEKSpacePickPlayerTarget(choices)
 local activePlayerID=Game.GetActivePlayer()
 local activeTeam=Teams[Players[activePlayerID]:GetTeam()]
 local warTarget,warTargetID,fallback,fallbackID=nil,nil,nil,nil
 for _,c in ipairs(choices) do
  if not c.Disabled and c.PlayerId and c.PlayerId~=activePlayerID then
   local p=Players[c.PlayerId]
   if p and p:IsAlive() then
    if activeTeam:IsAtWar(p:GetTeam()) and (not warTarget or c.Id<warTargetID) then warTarget,warTargetID=c,c.Id end
    if not fallback or c.Id<fallbackID then fallback,fallbackID=c,c.Id end
   end
  end
 end
 return warTarget or fallback
end
local function LEKSpaceProposalCandidate(c,used)
 local out={}
 for _,p in ipairs(c.ActiveResolutions or {}) do if not p.Disabled and not used['R:'..p.Id] then table.insert(out,{Direction='Repeal',Id=p.Id,Type=p.Type,ChoiceId=kChoiceNone,Text=p.Text,ToolTip=p.ToolTip}) end end
 for _,p in ipairs(c.InactiveResolutions or {}) do
  if not p.Disabled and not used['E:'..p.Type] then
   if not (p.ProposerChoices and #p.ProposerChoices>0) then
    table.insert(out,{Direction='Enact',Id=p.Id,Type=p.Type,ChoiceId=kChoiceNone,Text=p.Text,ToolTip=p.ToolTip})
   elseif p.ProposerChoices[1].PlayerId then
    -- Only a player-targeted choice (embargo/denounce-style) is auto-picked --
    -- a luxury or religion choice is still skipped, since there's no safe
    -- default for those. Prefer whoever we're at war with; otherwise the
    -- lowest-ID eligible player, matching every other deterministic tie-break
    -- in this autopilot.
    local target=LEKSpacePickPlayerTarget(p.ProposerChoices)
    if target then table.insert(out,{Direction='Enact',Id=p.Id,Type=p.Type,ChoiceId=target.Id,Text=p.Text,ToolTip=p.ToolTip}) end
   end
  end
 end
 table.sort(out,function(a,b) if a.Direction~=b.Direction then return a.Direction<b.Direction end; if tostring(a.Type)~=tostring(b.Type) then return tostring(a.Type)<tostring(b.Type) end; return (a.Id or -1)<(b.Id or -1) end)
 return out[1]
end
local function LEKSpaceLeague()
 LEKAutopilotLog("LG_LastPressTurn",Game.GetGameTurn())
 local player=Players[Game.GetActivePlayer()]; if not player or not player:IsTurnActive() or Game.IsProcessingMessages() then LEKAutopilotLog("LG_LastResult","PLAYER_TURN_NOT_ACTIVE");return false end
 if not Controls.ChooseConfirm:IsHidden() then LEKAutopilotLog("LG_LastResult","CONFIRMED_PENDING_ACTION");OnConfirmYes(); return true end
 if ProposalController and ProposalController.PendingProposals and #ProposalController.PendingProposals>0 then
  local used={}; for _,q in ipairs(ProposalController.PendingProposals) do local p=q.SelectedProposal; if p then used[(p.Direction=='Repeal' and 'R:'..p.Id or 'E:'..p.Type)]=true end end
  for _,q in ipairs(ProposalController.PendingProposals) do if not q.SelectedProposal then local p=LEKSpaceProposalCandidate(ProposalController,used); if not p then LEKAutopilotLog("LG_LastResult","NO_PROPOSAL_CANDIDATE");return true end; q.SelectedProposal=p; used[(p.Direction=='Repeal' and 'R:'..p.Id or 'E:'..p.Type)]=true; ProposalController:UpdatePendingProposalInstance(q) end end
  LEKAutopilotLog("LG_LastResult","FILLED_PROPOSALS")
  ProposalController.CommitButton:SetDisabled(false); ProposalController.ResetButton:SetDisabled(false); ProposalController:CommitProposals(); return true
 end
 if VoteController and VoteController.VoteEntries and VoteController.VotesAvailable~=nil then
  local league=Game.GetLeague(VoteController.LeagueId)
  if league and league:GetTurnsUntilVictorySession()==0 then
   -- World Leader session: every available vote goes to ourselves. The native
   -- ballot for this session only ever contains the diplomatic-victory entry,
   -- so this always resolves to that one vote.
   local activePlayerID=Game.GetActivePlayer()
   local cast=false
   for _,entry in ipairs(VoteController.VoteEntries) do
    if VoteController.VotesAvailable<=0 then break end
    local selfChoice=nil
    for _,c in ipairs(entry.VoterChoices or {}) do if c.PlayerId==activePlayerID then selfChoice=c.Id; break end end
    if selfChoice then entry.Choice=selfChoice; entry.Votes=(entry.Votes or 0)+VoteController.VotesAvailable; VoteController.VotesAvailable=0; cast=true end
   end
   if cast then LEKAutopilotLog("LG_LastResult","SELF_VOTED_WORLD_LEADER");VoteController:CommitVotes(); return true end
   LEKAutopilotLog("LG_LastResult","NO_SELF_CHOICE_IN_VICTORY_SESSION");return false
  end
  LEKAutopilotLog("LG_LastResult","COMMITTED_VOTES")
  VoteController:CommitVotes(); return true
 end
 LEKAutopilotLog("LG_LastResult","NO_APPLICABLE_CONTROLLER")
 return false
end
local LEKSpaceOriginalLeagueInput=InputHandler
function InputHandler(uiMsg,wParam,lParam)
 if uiMsg==KeyEvents.KeyDown and wParam==Keys.VK_SPACE and LEKSpaceLeague() then return true end
 return LEKSpaceOriginalLeagueInput(uiMsg,wParam,lParam)
end
LuaEvents.LEKSpaceAutomateTick.Add(function()
 if not ContextPtr:IsHidden() then LuaEvents.LEKSpaceAutomateModalHandled(1.7); pcall(LEKSpaceLeague) end
end)
'@
 $t=Insert-Before $t 'ContextPtr:SetInputHandler( InputHandler );' "$LB`r`n$($body.Trim())`r`n$LE`r`n"; Write-LEKUtf8NoBom $league $t
 $pantheon=Join-LEKPath $civ 'Assets\DLC\Expansion2\UI\InGame\Popups\ChoosePantheonPopup.lua'; $t=[IO.File]::ReadAllText($pantheon); if(!$t.Contains('ContextPtr:SetInputHandler( InputHandler );')){throw 'Unexpected ChoosePantheonPopup layout.'}; Backup-LEKFileOnce $pantheon $backup 'ChoosePantheonPopup.lua'|Out-Null; $t=Remove-LEKMarkedBlock $t $NB $NE
 $body=@'
local LEKAutopilotDB=nil
pcall(function() LEKAutopilotDB=Modding.OpenUserData("LEK_SPACE_AUTOPILOT",1) end)
local function LEKAutopilotLog(k,v) if LEKAutopilotDB then pcall(function() LEKAutopilotDB.SetValue(k,v) end) end end
local function LEKSpaceChoosePantheon()
 LEKAutopilotLog("PN_LastPressTurn",Game.GetGameTurn())
 local player=Players[Game.GetActivePlayer()]; if not player or not player:IsTurnActive() or Game.IsProcessingMessages() then LEKAutopilotLog("PN_LastResult","PLAYER_TURN_NOT_ACTIVE");return false end
 if not Controls.ChooseConfirm:IsHidden() then LEKAutopilotLog("PN_LastResult","CONFIRMED_BELIEF");OnYes(); return true end
 local beliefs=(g_bPantheons and g_bPantheons>0) and Game.GetAvailablePantheonBeliefs() or Game.GetAvailableReformationBeliefs()
 if not beliefs or #beliefs==0 then LEKAutopilotLog("PN_LastResult","NO_LEGAL_BELIEF");return false end
 -- No native flavor table exists for beliefs; pick the lowest ID for a
 -- deterministic, reproducible choice rather than inventing a score.
 local bestID=nil
 for _,id in ipairs(beliefs) do if not bestID or id<bestID then bestID=id end end
 LEKAutopilotLog("PN_LastResult","SELECTED_BELIEF");LEKAutopilotLog("PN_LastBeliefID",bestID)
 SelectPantheon(bestID); return true
end
local LEKSpaceOriginalPantheonInput=InputHandler
function InputHandler(uiMsg,wParam,lParam)
 if uiMsg==KeyEvents.KeyDown and wParam==Keys.VK_SPACE and LEKSpaceChoosePantheon() then return true end
 return LEKSpaceOriginalPantheonInput(uiMsg,wParam,lParam)
end
LuaEvents.LEKSpaceAutomateTick.Add(function()
 if not ContextPtr:IsHidden() then LuaEvents.LEKSpaceAutomateModalHandled(1.7); pcall(LEKSpaceChoosePantheon) end
end)
'@
 $t=Insert-Before $t 'ContextPtr:SetInputHandler( InputHandler );' "$NB`r`n$($body.Trim())`r`n$NE`r`n"; Write-LEKUtf8NoBom $pantheon $t
 $religion=Join-LEKPath $civ 'Assets\DLC\Expansion2\UI\InGame\Popups\ChooseReligionPopup.lua'; $t=[IO.File]::ReadAllText($religion); if(!$t.Contains('ContextPtr:SetInputHandler( InputHandler );')){throw 'Unexpected ChooseReligionPopup layout.'}; Backup-LEKFileOnce $religion $backup 'ChooseReligionPopup.lua'|Out-Null; $t=Remove-LEKMarkedBlock $t $RB $RE
 $body=@'
local LEKAutopilotDB=nil
pcall(function() LEKAutopilotDB=Modding.OpenUserData("LEK_SPACE_AUTOPILOT",1) end)
local function LEKAutopilotLog(k,v) if LEKAutopilotDB then pcall(function() LEKAutopilotDB.SetValue(k,v) end) end end
local LEKSpaceReligionRetryTurn=-1
local function LEKSpaceLowestBelief(list,e1,e2,e3)
 local best=nil
 for _,id in ipairs(list or {}) do
  local taken=false
  for s=1,6 do if g_Beliefs[s]==id then taken=true; break end end
  if not taken and id~=e1 and id~=e2 and id~=e3 and (not best or id<best) then best=id end
 end
 return best
end
local function LEKSpaceSetBelief(slot,control,id)
 local belief=GameInfo.Beliefs[id]
 g_Beliefs[slot]=id
 Controls[control.."Name"]:SetText(Locale.Lookup(belief.ShortDescription))
 Controls[control.."Description"]:SetText(Locale.Lookup(belief.Description))
 CheckifCanCommit()
end
local function LEKSpaceOpenBeliefContext(contextName,openFn,result)
 if g_BeliefToggleContext~=contextName then
  openFn()
  LEKAutopilotLog("RL_LastResult",result)
  return true
 end
 return false
end
local function LEKSpacePickOpenBelief(slot,control,contextName,openFn,list,result)
 if LEKSpaceOpenBeliefContext(contextName,openFn,"OPENED_"..result.."_LIST") then return true end
 LEKAutopilotLog("RL_Last"..result.."Count",#(list or {}))
 local id=LEKSpaceLowestBelief(list,g_Beliefs[1],g_Beliefs[2],g_Beliefs[3])
 if not id then
  local turn=Game.GetGameTurn()
  if LEKSpaceReligionRetryTurn~=turn then
   LEKSpaceReligionRetryTurn=turn
   if g_BeliefToggleContext~=nil then ToggleBeliefContext(nil) end
   OnClose()
   LuaEvents.LEKSpaceAutomateModalHandled(1.7)
   LEKAutopilotLog("RL_LastResult","RETRY_POPUP_AFTER_EMPTY_"..result)
   return true
  end
  LEKAutopilotLog("RL_LastResult","NO_AVAILABLE_"..result.."_BELIEF_AFTER_RETRY")
  return false
 end
 LEKAutopilotLog("RL_LastResult","SELECTED_"..result.."_BELIEF")
 LEKSpaceSetBelief(slot,control,id)
 ToggleBeliefContext(nil)
 return true
end
local function LEKSpaceReligion()
 LEKAutopilotLog("RL_LastPressTurn",Game.GetGameTurn())
 local player=Players[Game.GetActivePlayer()]; if not player or not player:IsTurnActive() or Game.IsProcessingMessages() then LEKAutopilotLog("RL_LastResult","PLAYER_TURN_NOT_ACTIVE");return false end
 LEKAutopilotLog("RL_bFoundingReligion",g_bFoundingReligion and 1 or 0)
 LEKAutopilotLog("RL_Belief1",tostring(g_Beliefs[1]))
 LEKAutopilotLog("RL_Belief2",tostring(g_Beliefs[2]))
 LEKAutopilotLog("RL_Belief3",tostring(g_Beliefs[3]))
 LEKAutopilotLog("RL_Belief4",tostring(g_Beliefs[4]))
 LEKAutopilotLog("RL_Belief5",tostring(g_Beliefs[5]))
 LEKAutopilotLog("RL_Belief6",tostring(g_Beliefs[6]))
 LEKAutopilotLog("RL_FoundReligionDisabled",Controls.FoundReligion:IsDisabled() and 1 or 0)
 if not Controls.ChangeNamePopup:IsHidden() then LEKAutopilotLog("RL_LastResult","CANCELLED_RENAME");OnChangeNameCancel(); return true end
 if not Controls.ChooseConfirm:IsHidden() then LEKAutopilotLog("RL_LastResult","CONFIRMED_RELIGION");OnYes(); return true end
 if g_bFoundingReligion then
  if g_CurrentReligionID==nil then
   for row in GameInfo.Religions("Type <> 'RELIGION_PANTHEON'") do
    local taken=false
    for iPlayer=0,GameDefines.MAX_MAJOR_CIVS-1 do
     local p=Players[iPlayer]
     if p and p:IsEverAlive() and p:HasCreatedReligion() and p:GetReligionCreatedByPlayer()==row.ID then taken=true end
    end
    if not taken then
     LEKAutopilotLog("RL_LastResult","SELECTED_IDENTITY");LEKAutopilotLog("RL_LastReligionID",row.ID)
     SelectReligion(row.ID, Locale.Lookup(row.Description), row.IconAtlas, row.PortraitIndex)
     return true
    end
   end
   LEKAutopilotLog("RL_LastResult","NO_LEGAL_RELIGION_IDENTITY");return false
  end
  if not player:HasCreatedPantheon() and g_Beliefs[1]==nil then
   return LEKSpacePickOpenBelief(1,"PantheonBelief","PantheonBelief",OnPantheonBeliefClick,Game.GetAvailablePantheonBeliefs(),"PANTHEON")
  end
  if g_Beliefs[2]==nil then
   return LEKSpacePickOpenBelief(2,"FounderBelief","FounderBelief",OnFounderBeliefClick,Game.GetAvailableFounderBeliefs(),"FOUNDER")
  end
  if g_Beliefs[3]==nil then
   return LEKSpacePickOpenBelief(3,"FollowerBelief","FollowerBelief",OnFollowerBeliefClick,Game.GetAvailableFollowerBeliefs(),"FOLLOWER")
  end
  if player:IsTraitBonusReligiousBelief() and g_Beliefs[6]==nil then
   return LEKSpacePickOpenBelief(6,"BonusBelief","BonusBelief",OnBonusBeliefClick,Game.GetAvailableBonusBeliefs(),"BONUS")
  end
  if not Controls.FoundReligion:IsDisabled() then LEKAutopilotLog("RL_LastResult","OPENED_FOUND_CONFIRM");FoundReligion(); return true end
  LEKAutopilotLog("RL_LastResult","NO_LEGAL_FOUND_BELIEF");return false
 else
  if g_Beliefs[4]==nil then
   return LEKSpacePickOpenBelief(4,"FollowerBelief2","FollowerBelief2",OnFollowerBelief2Click,Game.GetAvailableFollowerBeliefs(),"FOLLOWER2")
  end
  if g_Beliefs[5]==nil then
   return LEKSpacePickOpenBelief(5,"EnhancerBelief","EnhancerBelief",OnEnhancerBeliefClick,Game.GetAvailableEnhancerBeliefs(),"ENHANCER")
  end
  if not Controls.FoundReligion:IsDisabled() then LEKAutopilotLog("RL_LastResult","OPENED_ENHANCE_CONFIRM");FoundReligion(); return true end
  LEKAutopilotLog("RL_LastResult","NO_LEGAL_ENHANCE_BELIEF");return false
 end
end
local LEKSpaceOriginalReligionInput=InputHandler
function InputHandler(uiMsg,wParam,lParam)
 if uiMsg==KeyEvents.KeyDown and wParam==Keys.VK_SPACE and LEKSpaceReligion() then return true end
 return LEKSpaceOriginalReligionInput(uiMsg,wParam,lParam)
end
LuaEvents.LEKSpaceAutomateTick.Add(function()
 if not ContextPtr:IsHidden() then
  LuaEvents.LEKSpaceAutomateModalHandled(1.7)
  local ok,result=pcall(LEKSpaceReligion)
  LEKAutopilotLog("RL_LastPcallOK",ok and 1 or 0)
  if not ok then LEKAutopilotLog("RL_LastError",tostring(result)) end
 end
end)
'@
 $t=Insert-Before $t 'ContextPtr:SetInputHandler( InputHandler );' "$RB`r`n$($body.Trim())`r`n$RE`r`n"; Write-LEKUtf8NoBom $religion $t

 $freeItem=Join-LEKPath $civ 'Assets\DLC\Expansion2\UI\InGame\Popups\ChooseFreeItem.lua'; $t=[IO.File]::ReadAllText($freeItem); if(!$t.Contains('ContextPtr:SetInputHandler( InputHandler );')){throw 'Unexpected ChooseFreeItem layout.'}; Backup-LEKFileOnce $freeItem $backup 'ChooseFreeItem.lua'|Out-Null; $t=Remove-LEKMarkedBlock $t $FB $FE
 $body=@'
local LEKAutopilotDB=nil
pcall(function() LEKAutopilotDB=Modding.OpenUserData("LEK_SPACE_AUTOPILOT",1) end)
local function LEKAutopilotLog(k,v) if LEKAutopilotDB then pcall(function() LEKAutopilotDB.SetValue(k,v) end) end end
local LEKSpaceClassType=nil
local LEKSpacePlayerID=nil
local LEKSpaceOriginalDisplayPopup=DisplayPopup
function DisplayPopup(playerID,classType,numberOfFreeItems)
 LEKSpaceClassType=classType; LEKSpacePlayerID=playerID
 return LEKSpaceOriginalDisplayPopup(playerID,classType,numberOfFreeItems)
end
local function LEKSpaceChooseFreeItem()
 LEKAutopilotLog("FI_LastPressTurn",Game.GetGameTurn())
 if not LEKSpaceClassType then LEKAutopilotLog("FI_LastResult","NO_ACTIVE_POPUP");return false end
 if g_NumberOfFreeItems>0 and #SelectedItems>=g_NumberOfFreeItems then
  LEKAutopilotLog("FI_LastResult","COMMITTED")
  CommitItems[LEKSpaceClassType](SelectedItems,LEKSpacePlayerID); OnClose(); LEKSpaceClassType=nil
  return true
 end
 if LEKSpaceClassType=="GreatPeople" then
  local player=Players[LEKSpacePlayerID]
  for info in GameInfo.Units{Special="SPECIALUNIT_PEOPLE"} do
   if player:CanTrain(info.ID,true,true,true,false) and (not info.FoundReligion or player:HasCreatedPantheon()) then
    local already=false
    for _,v in ipairs(SelectedItems) do if v[1]==info.Type then already=true end end
    if not already then
     table.insert(SelectedItems,{info.Type,nil})
     LEKAutopilotLog("FI_LastResult","SELECTED_UNIT")
     if #SelectedItems>=g_NumberOfFreeItems then CommitItems[LEKSpaceClassType](SelectedItems,LEKSpacePlayerID); OnClose(); LEKSpaceClassType=nil end
     return true
    end
   end
  end
 end
 LEKAutopilotLog("FI_LastResult","NO_LEGAL_ITEM")
 return false
end
local LEKSpaceOriginalFreeItemInput=InputHandler
function InputHandler(uiMsg,wParam,lParam)
 if uiMsg==KeyEvents.KeyDown and wParam==Keys.VK_SPACE and LEKSpaceChooseFreeItem() then return true end
 return LEKSpaceOriginalFreeItemInput(uiMsg,wParam,lParam)
end
LuaEvents.LEKSpaceAutomateTick.Add(function()
 if not ContextPtr:IsHidden() then LuaEvents.LEKSpaceAutomateModalHandled(1.7); pcall(LEKSpaceChooseFreeItem) end
end)
'@
 $t=Insert-Before $t 'ContextPtr:SetInputHandler( InputHandler );' "$FB`r`n$($body.Trim())`r`n$FE`r`n"; Write-LEKUtf8NoBom $freeItem $t

 $faithGP=Join-LEKPath $civ 'Assets\DLC\Expansion2\UI\InGame\Popups\ChooseFaithGreatPerson.lua'; $t=[IO.File]::ReadAllText($faithGP); if(!$t.Contains('function DisplayPopup(playerID, classType, numberOfFreeItems)')){throw 'Unexpected ChooseFaithGreatPerson layout.'}; Backup-LEKFileOnce $faithGP $backup 'ChooseFaithGreatPerson.lua'|Out-Null
 $body=@'
local LEKAutopilotDB=nil
pcall(function() LEKAutopilotDB=Modding.OpenUserData("LEK_SPACE_AUTOPILOT",1) end)
local function LEKAutopilotLog(k,v) if LEKAutopilotDB then pcall(function() LEKAutopilotDB.SetValue(k,v) end) end end
local LEKSpaceClassType=nil
local LEKSpacePlayerID=nil
local LEKSpaceOriginalDisplayPopup=DisplayPopup
function DisplayPopup(playerID,classType,numberOfFreeItems)
 LEKSpaceClassType=classType; LEKSpacePlayerID=playerID
 return LEKSpaceOriginalDisplayPopup(playerID,classType,numberOfFreeItems)
end
local function LEKSpaceChooseFaithGreatPerson()
 LEKAutopilotLog("FG_LastPressTurn",Game.GetGameTurn())
 if not LEKSpaceClassType then LEKAutopilotLog("FG_LastResult","NO_ACTIVE_POPUP");return false end
 if g_NumberOfFreeItems>0 and #SelectedItems>=g_NumberOfFreeItems then
  LEKAutopilotLog("FG_LastResult","COMMITTED")
  CommitItems[LEKSpaceClassType](SelectedItems,LEKSpacePlayerID); OnClose(); LEKSpaceClassType=nil
  return true
 end
 if LEKSpaceClassType=="GreatPeople" then
  local player=Players[LEKSpacePlayerID]
  for info in GameInfo.Units{Special="SPECIALUNIT_PEOPLE"} do
   if player:CanTrain(info.ID,true,true,true,false) then
    local already=false
    for _,v in ipairs(SelectedItems) do if v[1]==info.Type then already=true end end
    if not already then
     table.insert(SelectedItems,{info.Type,nil})
     LEKAutopilotLog("FG_LastResult","SELECTED_UNIT")
     if #SelectedItems>=g_NumberOfFreeItems then CommitItems[LEKSpaceClassType](SelectedItems,LEKSpacePlayerID); OnClose(); LEKSpaceClassType=nil end
     return true
    end
   end
  end
 end
 LEKAutopilotLog("FG_LastResult","NO_LEGAL_ITEM")
 return false
end
local function LEKSpaceFaithGPInputHandler(uiMsg,wParam,lParam)
 if uiMsg==KeyEvents.KeyDown and wParam==Keys.VK_SPACE and LEKSpaceChooseFaithGreatPerson() then return true end
 if uiMsg==KeyEvents.KeyDown and wParam==Keys.VK_ESCAPE then OnClose(); return true end
 return false
end
ContextPtr:SetInputHandler(LEKSpaceFaithGPInputHandler)
LuaEvents.LEKSpaceAutomateTick.Add(function()
 if not ContextPtr:IsHidden() then LuaEvents.LEKSpaceAutomateModalHandled(1.7); pcall(LEKSpaceChooseFaithGreatPerson) end
end)
'@
 $t=[IO.File]::ReadAllText($faithGP); $t=Remove-LEKMarkedBlock $t $GB $GE; Set-LEKMarkedBlock $faithGP $GB $GE $body.Trim()

 $maya=Join-LEKPath $civ 'Assets\DLC\Expansion2\UI\InGame\Popups\ChooseMayaBonus.lua'; $t=[IO.File]::ReadAllText($maya); if(!$t.Contains('function DisplayPopup(playerID, classType, numberOfFreeItems)')){throw 'Unexpected ChooseMayaBonus layout.'}; Backup-LEKFileOnce $maya $backup 'ChooseMayaBonus.lua'|Out-Null
 $body=@'
local LEKAutopilotDB=nil
pcall(function() LEKAutopilotDB=Modding.OpenUserData("LEK_SPACE_AUTOPILOT",1) end)
local function LEKAutopilotLog(k,v) if LEKAutopilotDB then pcall(function() LEKAutopilotDB.SetValue(k,v) end) end end
local LEKSpaceClassType=nil
local LEKSpacePlayerID=nil
local LEKSpaceOriginalDisplayPopup=DisplayPopup
function DisplayPopup(playerID,classType,numberOfFreeItems)
 LEKSpaceClassType=classType; LEKSpacePlayerID=playerID
 return LEKSpaceOriginalDisplayPopup(playerID,classType,numberOfFreeItems)
end
local function LEKSpaceChooseMayaBonus()
 LEKAutopilotLog("MB_LastPressTurn",Game.GetGameTurn())
 if not LEKSpaceClassType then LEKAutopilotLog("MB_LastResult","NO_ACTIVE_POPUP");return false end
 if g_NumberOfFreeItems>0 and #SelectedItems>=g_NumberOfFreeItems then
  LEKAutopilotLog("MB_LastResult","COMMITTED")
  CommitItems[LEKSpaceClassType](SelectedItems,LEKSpacePlayerID); OnClose(); LEKSpaceClassType=nil
  return true
 end
 if LEKSpaceClassType=="GreatPeople" then
  local player=Players[LEKSpacePlayerID]
  for info in GameInfo.Units{Special="SPECIALUNIT_PEOPLE"} do
   if player:CanTrain(info.ID,true,true,true,false) then
    local already=false
    for _,v in ipairs(SelectedItems) do if v[1]==info.Type then already=true end end
    if not already then
     table.insert(SelectedItems,{info.Type,nil})
     LEKAutopilotLog("MB_LastResult","SELECTED_UNIT")
     if #SelectedItems>=g_NumberOfFreeItems then CommitItems[LEKSpaceClassType](SelectedItems,LEKSpacePlayerID); OnClose(); LEKSpaceClassType=nil end
     return true
    end
   end
  end
 end
 LEKAutopilotLog("MB_LastResult","NO_LEGAL_ITEM")
 return false
end
local function LEKSpaceMayaInputHandler(uiMsg,wParam,lParam)
 if uiMsg==KeyEvents.KeyDown and wParam==Keys.VK_SPACE and LEKSpaceChooseMayaBonus() then return true end
 if uiMsg==KeyEvents.KeyDown and wParam==Keys.VK_ESCAPE then OnClose(); return true end
 return false
end
ContextPtr:SetInputHandler(LEKSpaceMayaInputHandler)
LuaEvents.LEKSpaceAutomateTick.Add(function()
 if not ContextPtr:IsHidden() then LuaEvents.LEKSpaceAutomateModalHandled(1.7); pcall(LEKSpaceChooseMayaBonus) end
end)
'@
 $t=[IO.File]::ReadAllText($maya); $t=Remove-LEKMarkedBlock $t $MB $ME; Set-LEKMarkedBlock $maya $MB $ME $body.Trim()

 $archaeology=Join-LEKPath $civ 'Assets\DLC\Expansion2\UI\InGame\Popups\ChooseArchaeologyPopup.lua'; $t=[IO.File]::ReadAllText($archaeology); if(!$t.Contains('ContextPtr:SetInputHandler( InputHandler );')){throw 'Unexpected ChooseArchaeologyPopup layout.'}; Backup-LEKFileOnce $archaeology $backup 'ChooseArchaeologyPopup.lua'|Out-Null; $t=Remove-LEKMarkedBlock $t $AB $AE
 $body=@'
local LEKAutopilotDB=nil
pcall(function() LEKAutopilotDB=Modding.OpenUserData("LEK_SPACE_AUTOPILOT",1) end)
local function LEKAutopilotLog(k,v) if LEKAutopilotDB then pcall(function() LEKAutopilotDB.SetValue(k,v) end) end end
local function LEKSpaceChooseArchaeology()
 LEKAutopilotLog("AR_LastPressTurn",Game.GetGameTurn())
 if not Controls.ChooseConfirm:IsHidden() then LEKAutopilotLog("AR_LastResult","CONFIRMED");OnConfirmYes(); return true end
 if g_iUnitIndex==nil or g_iUnitIndex<0 then LEKAutopilotLog("AR_LastResult","NO_ACTIVE_POPUP");return false end
 local pPlayer=Players[Game.GetActivePlayer()]
 local pPlot=pPlayer:GetNextDigCompletePlot()
 if not pPlot then LEKAutopilotLog("AR_LastResult","NO_DIG_PLOT");return false end
 -- The landmark/renaissance choice (1 for a normal artifact, 4 for a written
 -- one) is always legal regardless of open Great Work slots, unlike the
 -- artifact-to-a-slot choices -- the same safe, always-available default
 -- used elsewhere when no scored option applies.
 local bWrittenArtifact=pPlot:HasWrittenArtifact()
 LEKAutopilotLog("AR_LastResult","SELECTED_DEFAULT_CHOICE")
 SelectArchaeologyChoice(bWrittenArtifact and 4 or 1)
 return true
end
local LEKSpaceOriginalArchaeologyInput=InputHandler
function InputHandler(uiMsg,wParam,lParam)
 if uiMsg==KeyEvents.KeyDown and wParam==Keys.VK_SPACE and LEKSpaceChooseArchaeology() then return true end
 return LEKSpaceOriginalArchaeologyInput(uiMsg,wParam,lParam)
end
LuaEvents.LEKSpaceAutomateTick.Add(function()
 if not ContextPtr:IsHidden() then LuaEvents.LEKSpaceAutomateModalHandled(1.7); pcall(LEKSpaceChooseArchaeology) end
end)
'@
 $t=Insert-Before $t 'ContextPtr:SetInputHandler( InputHandler );' "$AB`r`n$($body.Trim())`r`n$AE`r`n"; Write-LEKUtf8NoBom $archaeology $t

 $declareWar=Join-LEKPath $civ 'Assets\DLC\Expansion2\UI\InGame\Popups\DeclareWarPopup.lua'; $t=[IO.File]::ReadAllText($declareWar); if(!$t.Contains('ContextPtr:SetInputHandler( InputHandler );')){throw 'Unexpected DeclareWarPopup layout.'}; Backup-LEKFileOnce $declareWar $backup 'DeclareWarPopup.lua'|Out-Null; $t=Remove-LEKMarkedBlock $t $CB $CE
 $body=@'
local LEKAutopilotDB=nil
pcall(function() LEKAutopilotDB=Modding.OpenUserData("LEK_SPACE_AUTOPILOT",1) end)
local function LEKAutopilotLog(k,v) if LEKAutopilotDB then pcall(function() LEKAutopilotDB.SetValue(k,v) end) end end
local function LEKSpaceCityCapture()
 LEKAutopilotLog("CC_LastPressTurn",Game.GetGameTurn())
 -- DeclareWarPopup.lua is the shared host Context for every "GenericPopup"
 -- type (PuppetCityPopup, DeclareWarMove, DeclareWarRangeStrike, etc.) --
 -- they all register into the same PopupLayouts table and set g_PopupInfo
 -- here, rather than owning their own Context/InputHandler. Only the city
 -- capture type is handled; anything else (in particular the DeclareWar*
 -- "does this mean war" confirmations sharing this same host) falls through
 -- to the original handler untouched, since auto-declaring war is exactly
 -- the kind of game-altering choice this autopilot never makes on its own.
 if not g_PopupInfo or g_PopupInfo.Type~=ButtonPopupTypes.BUTTONPOPUP_CITY_CAPTURED then LEKAutopilotLog("CC_LastResult","NOT_APPLICABLE");return false end
 -- Puppet has no legality gate here (unlike Annex's MayNotAnnex() check) and
 -- is normally the least drastic option -- it can still be annexed later by
 -- hand. But if puppeting this specific city would push the empire's net
 -- happiness negative, Raze instead where that's legal: the same forecast
 -- PuppetCityPopup itself shows on the Puppet button's tooltip.
 local cityID=g_PopupInfo.Data1
 local activePlayer=Players[Game.GetActivePlayer()]
 local newCity=activePlayer:GetCityByID(cityID)
 local action="PUPPETED"
 if newCity then
  local ok,forecastExcessHappiness=pcall(function()
   local iUnhappinessNoCity=activePlayer:GetUnhappiness()
   local iUnhappinessPuppetCity=activePlayer:GetUnhappinessForecast(nil,newCity)
   return activePlayer:GetExcessHappiness()-(iUnhappinessPuppetCity-iUnhappinessNoCity)
  end)
  -- Raze only for a clear, not marginal, happiness problem (a small dip
  -- under zero isn't worth burning a city for) and only a small city (a
  -- size 1-2 city is a much smaller loss than a developed one if the
  -- forecast turns out to be a bit pessimistic).
  if ok and forecastExcessHappiness<-5 and newCity:GetPopulation()<=2 and activePlayer:CanRaze(newCity) then action="RAZED" end
 end
 LEKAutopilotLog("CC_LastResult",action);LEKAutopilotLog("CC_LastCityID",cityID)
 if action=="RAZED" then
  Network.SendDoTask(cityID,TaskTypes.TASK_RAZE,-1,-1,false,false,false,false)
 else
  Network.SendDoTask(cityID,TaskTypes.TASK_CREATE_PUPPET,-1,-1,false,false,false,false)
 end
 HideWindow()
 return true
end
local LEKSpaceOriginalCityCaptureInput=InputHandler
function InputHandler(uiMsg,wParam,lParam)
 if uiMsg==KeyEvents.KeyDown and wParam==Keys.VK_SPACE and LEKSpaceCityCapture() then return true end
 return LEKSpaceOriginalCityCaptureInput(uiMsg,wParam,lParam)
end
LuaEvents.LEKSpaceAutomateTick.Add(function()
 if not ContextPtr:IsHidden() then LuaEvents.LEKSpaceAutomateModalHandled(1.7); pcall(LEKSpaceCityCapture) end
end)
'@
 $t=Insert-Before $t 'ContextPtr:SetInputHandler( InputHandler );' "$CB`r`n$($body.Trim())`r`n$CE`r`n"; Write-LEKUtf8NoBom $declareWar $t

 $ideology=Join-LEKPath $civ 'Assets\DLC\Expansion2\UI\InGame\Popups\ChooseIdeologyPopup.lua'; $t=[IO.File]::ReadAllText($ideology); if(!$t.Contains('ContextPtr:SetInputHandler( InputHandler );')){throw 'Unexpected ChooseIdeologyPopup layout.'}; Backup-LEKFileOnce $ideology $backup 'ChooseIdeologyPopup.lua'|Out-Null; $t=Remove-LEKMarkedBlock $t $IB $IE
 $body=@'
local LEKAutopilotDB=nil
pcall(function() LEKAutopilotDB=Modding.OpenUserData("LEK_SPACE_AUTOPILOT",1) end)
local function LEKAutopilotLog(k,v) if LEKAutopilotDB then pcall(function() LEKAutopilotDB.SetValue(k,v) end) end end
local function LEKSpaceIdeologyWeights(player)
 local w,leader={},GameInfo.Leaders[player:GetLeaderType()]
 if leader then for row in GameInfo.Leader_Flavors{LeaderType=leader.Type} do w[row.FlavorType]=row.Flavor or 0 end end
 return w
end
local function LEKSpaceIdeologyScore(branch,w)
 local score=0
 for p in GameInfo.Policies{PolicyBranchType=branch.Type} do
  for row in GameInfo.Policy_Flavors{PolicyType=p.Type} do score=score+(w[row.FlavorType] or 0)*(row.Flavor or 0) end
 end
 return score
end
local function LEKSpaceChooseIdeology()
 LEKAutopilotLog("ID_LastPressTurn",Game.GetGameTurn())
 if not Controls.ChooseConfirm:IsHidden() then LEKAutopilotLog("ID_LastResult","CONFIRMED");OnConfirmYes(); return true end
 local player=Players[Game.GetActivePlayer()]; if not player then LEKAutopilotLog("ID_LastResult","NO_ACTIVE_PLAYER");return false end
 local w=LEKSpaceIdeologyWeights(player)
 local best,bs=nil,nil
 for _,branchType in ipairs({"POLICY_BRANCH_AUTOCRACY","POLICY_BRANCH_FREEDOM","POLICY_BRANCH_ORDER"}) do
  local branch=GameInfo.PolicyBranchTypes[branchType]
  if branch then
   local s=LEKSpaceIdeologyScore(branch,w)
   if not best or s>bs or (s==bs and branch.ID<best.ID) then best,bs=branch,s end
  end
 end
 if not best then LEKAutopilotLog("ID_LastResult","NO_IDEOLOGY_FOUND");return false end
 LEKAutopilotLog("ID_LastResult","SELECTED_IDEOLOGY");LEKAutopilotLog("ID_LastBranchID",best.ID)
 SelectIdeologyChoice(best.ID); return true
end
local LEKSpaceOriginalIdeologyInput=InputHandler
function InputHandler(uiMsg,wParam,lParam)
 if uiMsg==KeyEvents.KeyDown and wParam==Keys.VK_SPACE and LEKSpaceChooseIdeology() then return true end
 return LEKSpaceOriginalIdeologyInput(uiMsg,wParam,lParam)
end
LuaEvents.LEKSpaceAutomateTick.Add(function()
 if not ContextPtr:IsHidden() then LuaEvents.LEKSpaceAutomateModalHandled(1.7); pcall(LEKSpaceChooseIdeology) end
end)
'@
 $t=Insert-Before $t 'ContextPtr:SetInputHandler( InputHandler );' "$IB`r`n$($body.Trim())`r`n$IE`r`n"; Write-LEKUtf8NoBom $ideology $t

 & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Verify.ps1') -CivPath $civ; if($LASTEXITCODE-ne 0){throw 'Verification failed.'}; Write-Host 'SPACE AUTOPILOT POLICY/CONGRESS v0.8 INSTALLED.' -ForegroundColor Green
} catch {Write-Host ('ERROR: '+$_.Exception.Message) -ForegroundColor Red; exit 1}
