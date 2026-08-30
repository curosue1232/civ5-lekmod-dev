param([string]$CivPath='')
$ErrorActionPreference='Stop'
$Internal=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $Internal 'LekTools.ps1')
function Get-LEKMarkedBlockText([string]$Text,[string]$Begin,[string]$End){
 $bi=$Text.IndexOf($Begin); $ei=$Text.IndexOf($End)
 if($bi -lt 0 -or $ei -lt 0 -or $ei -lt $bi){ return $null }
 return $Text.Substring($bi,($ei-$bi)+$End.Length)
}
try {
 $civ=Find-LEKCivV $CivPath; if(!$civ){throw 'Civilization V install folder not found.'}
 $checks=@(
  @{
   P=Join-LEKPath $civ 'Assets\DLC\UI_bc1\Improvements\SocialPolicyPopup.lua'
   B='-- LEK_EXT_SPACE_AUTOPILOT_POLICY_V04_BEGIN';E='-- LEK_EXT_SPACE_AUTOPILOT_POLICY_V04_END'
   Require=@('LEKSpaceChoosePolicy','OnChangeIdeologyConfirmYes()','GameInfo.Policy_Flavors','LEKSpaceOriginalPolicyInput','NO_LEGAL_CHOICE_CLOSING','ChooseChangeIdeology()','GetPublicOpinionUnhappiness()>0','INITIATED_IDEOLOGY_SWITCH','LuaEvents.LEKSpaceAutomateTick.Add','pcall(LEKSpaceChoosePolicy)')
   Forbid=@('endlocal','endfunction')
  },
  @{
   P=Join-LEKPath $civ 'Assets\DLC\Expansion2\UI\InGame\Popups\LeagueOverview.lua'
   B='-- LEK_EXT_SPACE_AUTOPILOT_LEAGUE_V04_BEGIN';E='-- LEK_EXT_SPACE_AUTOPILOT_LEAGUE_V04_END'
   Require=@('LEKSpaceLeague','LEKSpaceProposalCandidate','GetTurnsUntilVictorySession()==0','VoteController:CommitVotes()','LEKSpaceOriginalLeagueInput','LEKSpacePickPlayerTarget','c.PlayerId==activePlayerID','SELF_VOTED_WORLD_LEADER','activeTeam:IsAtWar(p:GetTeam())','LuaEvents.LEKSpaceAutomateTick.Add','pcall(LEKSpaceLeague)')
   Forbid=@('LEKSpaceHostility','choice.Id==active','SKIPPED_VICTORY_SESSION','endlocal','endfunction')
  },
  @{
   P=Join-LEKPath $civ 'Assets\DLC\Expansion2\UI\InGame\Popups\ChoosePantheonPopup.lua'
   B='-- LEK_EXT_SPACE_AUTOPILOT_PANTHEON_V05_BEGIN';E='-- LEK_EXT_SPACE_AUTOPILOT_PANTHEON_V05_END'
   Require=@('LEKSpaceChoosePantheon','Game.GetAvailablePantheonBeliefs()','Game.GetAvailableReformationBeliefs()','SelectPantheon(bestID)','LEKSpaceOriginalPantheonInput','LuaEvents.LEKSpaceAutomateTick.Add','pcall(LEKSpaceChoosePantheon)')
   Forbid=@('endlocal','endfunction')
  },
  @{
   P=Join-LEKPath $civ 'Assets\DLC\Expansion2\UI\InGame\Popups\ChooseReligionPopup.lua'
   B='-- LEK_EXT_SPACE_AUTOPILOT_RELIGION_V06_BEGIN';E='-- LEK_EXT_SPACE_AUTOPILOT_RELIGION_V06_END'
   Require=@('LEKSpaceReligion','SelectReligion(row.ID','LEKSpaceOpenBeliefContext','LEKSpacePickOpenBelief','LEKSpaceReligionRetryTurn','RETRY_POPUP_AFTER_EMPTY_','NO_AVAILABLE_','OnFounderBeliefClick','OnFollowerBeliefClick','OnFollowerBelief2Click','OnEnhancerBeliefClick','OnBonusBeliefClick','Game.GetAvailableFounderBeliefs()','Game.GetAvailableFollowerBeliefs()','Game.GetAvailableEnhancerBeliefs()','Game.GetAvailableBonusBeliefs()','Controls[control.."Name"]','Controls[control.."Description"]','CheckifCanCommit()','ToggleBeliefContext(nil)','OnClose()','FoundReligion()','OnYes()','LEKSpaceOriginalReligionInput','LuaEvents.LEKSpaceAutomateTick.Add','LuaEvents.LEKSpaceAutomateModalHandled(1.7)','RL_Belief1','RL_Belief2','RL_Belief3','RL_Belief4','RL_Belief5','RL_Belief6','RL_FoundReligionDisabled','RL_LastPcallOK','RL_LastError','pcall(LEKSpaceReligion)')
   Forbid=@('endlocal','endfunction','_G["Controls"]')
  },
  @{
   P=Join-LEKPath $civ 'Assets\DLC\Expansion2\UI\InGame\Popups\ChooseFreeItem.lua'
   B='-- LEK_EXT_SPACE_AUTOPILOT_FREEITEM_V07_BEGIN';E='-- LEK_EXT_SPACE_AUTOPILOT_FREEITEM_V07_END'
   Require=@('LEKSpaceChooseFreeItem','SPECIALUNIT_PEOPLE','CommitItems[LEKSpaceClassType]','LEKSpaceOriginalFreeItemInput','LuaEvents.LEKSpaceAutomateTick.Add','pcall(LEKSpaceChooseFreeItem)')
   Forbid=@('endlocal','endfunction')
  },
  @{
   P=Join-LEKPath $civ 'Assets\DLC\Expansion2\UI\InGame\Popups\ChooseArchaeologyPopup.lua'
   B='-- LEK_EXT_SPACE_AUTOPILOT_ARCHAEOLOGY_V07_BEGIN';E='-- LEK_EXT_SPACE_AUTOPILOT_ARCHAEOLOGY_V07_END'
   Require=@('LEKSpaceChooseArchaeology','GetNextDigCompletePlot()','SelectArchaeologyChoice','LEKSpaceOriginalArchaeologyInput','LuaEvents.LEKSpaceAutomateTick.Add','pcall(LEKSpaceChooseArchaeology)')
   Forbid=@('endlocal','endfunction')
  },
  @{
   P=Join-LEKPath $civ 'Assets\DLC\Expansion2\UI\InGame\Popups\DeclareWarPopup.lua'
   B='-- LEK_EXT_SPACE_AUTOPILOT_CITYCAPTURE_V07_BEGIN';E='-- LEK_EXT_SPACE_AUTOPILOT_CITYCAPTURE_V07_END'
   Require=@('LEKSpaceCityCapture','BUTTONPOPUP_CITY_CAPTURED','TaskTypes.TASK_CREATE_PUPPET','TaskTypes.TASK_RAZE','activePlayer:GetUnhappinessForecast(nil,newCity)','activePlayer:GetExcessHappiness()','forecastExcessHappiness<-5 and newCity:GetPopulation()<=2 and activePlayer:CanRaze(newCity)','LEKSpaceOriginalCityCaptureInput','LuaEvents.LEKSpaceAutomateTick.Add','pcall(LEKSpaceCityCapture)')
   Forbid=@('TASK_ANNEX_PUPPET','SendLiberateMinor','BUTTONPOPUP_DECLAREWARMOVE','BUTTONPOPUP_DECLAREWARRANGESTRIKE','endlocal','endfunction')
  },
  @{
   P=Join-LEKPath $civ 'Assets\DLC\Expansion2\UI\InGame\Popups\ChooseIdeologyPopup.lua'
   B='-- LEK_EXT_SPACE_AUTOPILOT_IDEOLOGY_V08_BEGIN';E='-- LEK_EXT_SPACE_AUTOPILOT_IDEOLOGY_V08_END'
   Require=@('LEKSpaceChooseIdeology','POLICY_BRANCH_AUTOCRACY','POLICY_BRANCH_FREEDOM','POLICY_BRANCH_ORDER','SelectIdeologyChoice(best.ID)','LEKSpaceOriginalIdeologyInput','LuaEvents.LEKSpaceAutomateTick.Add','pcall(LEKSpaceChooseIdeology)')
   Forbid=@('endlocal','endfunction')
  }
 )
 foreach($c in $checks){
  $t=[IO.File]::ReadAllText($c.P)
  if(([regex]::Matches($t,[regex]::Escape($c.B))).Count -ne 1 -or ([regex]::Matches($t,[regex]::Escape($c.E))).Count -ne 1){ throw "Marker count failed: $($c.P)" }
  if($t.IndexOf($c.B) -gt $t.IndexOf('ContextPtr:SetInputHandler( InputHandler );')){ throw 'Wrapper appears after handler registration.' }
  $block=Get-LEKMarkedBlockText $t $c.B $c.E
  if(!$block){ throw "Could not extract marked block: $($c.P)" }
  foreach($x in $c.Require){ if(!$block.Contains($x)){ throw "Missing token in marked block: $x ($($c.P))" } }
  foreach($x in $c.Forbid){ if($block.Contains($x)){ throw "Forbidden token present in marked block: $x ($($c.P))" } }
 }
 foreach($appendCheck in @(
  @{P=Join-LEKPath $civ 'Assets\DLC\Expansion2\UI\InGame\Popups\ChooseFaithGreatPerson.lua';B='-- LEK_EXT_SPACE_AUTOPILOT_FAITHGP_V07_BEGIN';E='-- LEK_EXT_SPACE_AUTOPILOT_FAITHGP_V07_END';Require=@('LEKSpaceChooseFaithGreatPerson','SPECIALUNIT_PEOPLE','CommitItems[LEKSpaceClassType]','LEKSpaceFaithGPInputHandler','ContextPtr:SetInputHandler(LEKSpaceFaithGPInputHandler)','LuaEvents.LEKSpaceAutomateTick.Add','pcall(LEKSpaceChooseFaithGreatPerson)')},
  @{P=Join-LEKPath $civ 'Assets\DLC\Expansion2\UI\InGame\Popups\ChooseMayaBonus.lua';B='-- LEK_EXT_SPACE_AUTOPILOT_MAYA_V07_BEGIN';E='-- LEK_EXT_SPACE_AUTOPILOT_MAYA_V07_END';Require=@('LEKSpaceChooseMayaBonus','SPECIALUNIT_PEOPLE','CommitItems[LEKSpaceClassType]','LEKSpaceMayaInputHandler','ContextPtr:SetInputHandler(LEKSpaceMayaInputHandler)','LuaEvents.LEKSpaceAutomateTick.Add','pcall(LEKSpaceChooseMayaBonus)')}
 )){
  $t=[IO.File]::ReadAllText($appendCheck.P)
  if(([regex]::Matches($t,[regex]::Escape($appendCheck.B))).Count -ne 1 -or ([regex]::Matches($t,[regex]::Escape($appendCheck.E))).Count -ne 1){ throw "Marker count failed: $($appendCheck.P)" }
  $block=Get-LEKMarkedBlockText $t $appendCheck.B $appendCheck.E
  if(!$block){ throw "Could not extract marked block: $($appendCheck.P)" }
  foreach($x in $appendCheck.Require){ if(!$block.Contains($x)){ throw "Missing token in marked block: $x ($($appendCheck.P))" } }
  if($block.Contains('endlocal') -or $block.Contains('endfunction')){ throw "Forbidden token present in marked block: ($($appendCheck.P))" }
 }
 Write-Host 'SPACE AUTOPILOT POLICY/CONGRESS v0.8 VERIFIED.' -ForegroundColor Green
} catch {Write-Host ('ERROR: '+$_.Exception.Message) -ForegroundColor Red; exit 1}
