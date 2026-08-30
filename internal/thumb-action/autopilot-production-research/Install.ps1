param([string]$CivPath='')
$ErrorActionPreference='Stop'
$InternalRoot=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $InternalRoot 'LekTools.ps1')
function W([string]$s,[ConsoleColor]$c=[ConsoleColor]::Gray){Write-Host $s -ForegroundColor $c}
$B='-- LEK_EXT_SPACE_AUTOPILOT_PR_V01_BEGIN';$E='-- LEK_EXT_SPACE_AUTOPILOT_PR_V01_END'
$KB='-- LEK_EXT_SPACE_AUTOPILOT_PR_V01_KEY_BEGIN';$KE='-- LEK_EXT_SPACE_AUTOPILOT_PR_V01_KEY_END'
function Add-Bridge($Path,$Anchor,$KeyAnchor,$Body,$KeyBody){
 $t=[IO.File]::ReadAllText($Path);$t=Remove-LEKMarkedBlock $t $B $E;$t=Remove-LEKMarkedBlock $t $KB $KE
 if(!$t.Contains($Anchor)-or!$t.Contains($KeyAnchor)){throw "Expected EUI anchor missing: $Path"}
 $t=$t.Replace($Anchor,"$B`r`n$Body`r`n$E`r`n`r`n$Anchor")
 $t=$t.Replace($KeyAnchor,"$KeyAnchor`r`n`t`t$KB`r`n$KeyBody`r`n`t`t$KE")
 Write-LEKUtf8NoBom $Path $t
}
$common=@'
local LEKAutopilotDB=nil
pcall(function() LEKAutopilotDB=Modding.OpenUserData("LEK_SPACE_AUTOPILOT",1) end)
local function LEKAutopilotLog(k,v) if LEKAutopilotDB then pcall(function() LEKAutopilotDB.SetValue(k,v) end) end end
local function LEKSpaceLeaderFlavors()
 local r,p={},Players[Game.GetActivePlayer()]
 local leader=p and GameInfo.Leaders[p:GetLeaderType()]
 if leader and GameInfo.Leader_Flavors then
  for x in GameInfo.Leader_Flavors{LeaderType=leader.Type} do r[x.FlavorType]=tonumber(x.Flavor) or 0 end
 end
 return r
end
local function LEKSpaceFlavorScore(tableName,column,itemType,flavors)
 local source=GameInfo[tableName];if not source or not itemType then return 0 end
 local filter={};filter[column]=itemType;local score=0
 for x in source(filter) do score=score+(flavors[x.FlavorType] or 0)*(tonumber(x.Flavor) or 0) end
 return score
end
local function LEKSpaceBetter(a,b)
 return not b or a.rec>b.rec or (a.rec==b.rec and a.score>b.score) or (a.rec==b.rec and a.score==b.score and a.id<b.id)
end
'@
try{
 if(Test-LEKCivRunning){throw 'Civilization V appears to be running. Close it before installing.'}
 $civ=Find-LEKCivV $CivPath;if(!$civ){throw 'Civilization V install folder not found.'}
 $city=Join-LEKPath $civ 'Assets\DLC\UI_bc1\CityView\CityView.lua';$tech=Join-LEKPath $civ 'Assets\DLC\UI_bc1\TechTree\TechTree.lua'
 if(!(Test-LEKPath $city)-or !(Test-LEKPath $tech)){throw 'Installed EUI production/research owners were not found.'}
 $backup=Join-Path (Split-Path $InternalRoot -Parent) 'local\backups\thumb-action'
 Backup-LEKFileOnce $city $backup 'EUI-CityView.lua'|Out-Null;Backup-LEKFileOnce $tech $backup 'EUI-TechTree.lua'|Out-Null
 $cityBody=$common+"`r`n"+@'
local function LEKSpaceHasSeaWorkTarget(city)
 local cx,cy=city:GetX(),city:GetY()
 for dx=-8,8 do for dy=-8,8 do
  local p=Map.GetPlot(cx+dx,cy+dy)
  if p and p:IsWater() and p:GetResourceType()~=-1 and p:GetImprovementType()==-1 and Map.PlotDistance(cx,cy,p:GetX(),p:GetY())<=8 then return true end
 end end
 return false
end
local function LEKSpaceCanTrainUnit(city,id)
 if not city:CanTrain(id) then return false end
 -- A Work Boat with no sea resource anywhere nearby to improve is wasted
 -- production -- the unit itself deletes itself once stranded, so better to
 -- never build it in the first place.
 local info=GameInfo.Units[id]
 if info and info.DefaultUnitAI=="UNITAI_WORKER_SEA" and not LEKSpaceHasSeaWorkTarget(city) then return false end
 return true
end
local function LEKSpaceChooseProduction()
 LEKAutopilotLog("PR_LastPressTurn",Game.GetGameTurn())
 local city=GetSelectedModifiableCity()
 LEKAutopilotLog("PR_HasSelectedCity",city and 1 or 0)
 if not city or city:GetOwner()~=g_activePlayerID or city:IsPuppet() then LEKAutopilotLog("PR_LastResult","NO_MODIFIABLE_CITY");return false end
 -- Don't rely on g_isButtonPopupChooseProduction: EUI also opens this screen
 -- directly from a NotificationAdded handler when a city is founded this
 -- turn, and that path never sets the flag. Checking the order queue
 -- directly covers both native paths and never touches a city that already
 -- has something queued.
 if city:GetOrderQueueLength()>0 then
  -- A production notification can reopen CityView after our order has
  -- already committed.  There is no remaining choice to make, so return to
  -- the map instead of reporting failure and leaving Automate trapped here.
  LEKAutopilotLog("PR_LastResult","ALREADY_HAS_ORDER_CLOSING")
  LuaEvents.LEKSpaceAutomateModalHandled(1.7)
  ExitCityScreen(); return true
 end
 Game.SetAdvisorRecommenderCity(city);local flavors,best=LEKSpaceLeaderFlavors()
 local function scan(rows,order,canDo,flavorTable,column,recommender)
  for item in rows() do if canDo(city,item.ID) then
   local rec=0;if recommender then for a=0,AdvisorTypes.NUM_ADVISOR_TYPES-1 do if recommender(item.ID,a) then rec=rec+1 end end end
   local c={id=item.ID,order=order,rec=rec,score=LEKSpaceFlavorScore(flavorTable,column,item.Type,flavors)}
   if LEKSpaceBetter(c,best) then best=c end
  end end
 end
 scan(GameInfo.Buildings,OrderTypes.ORDER_CONSTRUCT,city.CanConstruct,'Building_Flavors','BuildingType',Game.IsBuildingRecommended)
 scan(GameInfo.Units,OrderTypes.ORDER_TRAIN,LEKSpaceCanTrainUnit,'Unit_Flavors','UnitType',Game.IsUnitRecommended)
 scan(GameInfo.Projects,OrderTypes.ORDER_CREATE,city.CanCreate,'Project_Flavors','ProjectType',Game.IsProjectRecommended)
 if not best then scan(GameInfo.Processes,OrderTypes.ORDER_MAINTAIN,city.CanMaintain,'Process_Flavors','ProcessType',nil) end
 if not best then LEKAutopilotLog("PR_LastResult","NO_LEGAL_ITEM");return false end
 LEKAutopilotLog("PR_LastResult","PUSHED_ORDER");LEKAutopilotLog("PR_LastOrder",best.order);LEKAutopilotLog("PR_LastItemID",best.id)
 Game.CityPushOrder(city,best.order,best.id,false,false,true)
 Events.SpecificCityInfoDirty(city:GetOwner(),city:GetID(),CityUpdateTypes.CITY_UPDATE_TYPE_BANNER)
 Events.SpecificCityInfoDirty(city:GetOwner(),city:GetID(),CityUpdateTypes.CITY_UPDATE_TYPE_PRODUCTION)
 for c in g_activePlayer:Cities() do if c~=city and not c:IsPuppet() and c:GetOrderQueueLength()<1 then UI.SelectCity(c);UI.LookAtSelectionPlot();return true end end
 LuaEvents.LEKSpaceAutomateModalHandled(1.7)
 ExitCityScreen();return true
end
-- Automate (the Escape-menu button) never presses a real key, so this screen
-- would otherwise sit open forever once a newly founded city opens it. Only
-- act while this screen is actually the one showing.
LuaEvents.LEKSpaceAutomateTick.Add(function()
 if not ContextPtr:IsHidden() then
  LuaEvents.LEKSpaceAutomateModalHandled(1.7)
  local ok,err=pcall(LEKSpaceChooseProduction)
 end
end)
'@
 $cityKey="`t`tif wParam == Keys.VK_SPACE and LEKSpaceChooseProduction() then`r`n`t`t`treturn true`r`n`t`tend"
 Add-Bridge $city 'ContextPtr:SetInputHandler(' "`tif uiMsg == KeyEvents.KeyDown then" $cityBody.Trim() $cityKey
 $techBody=$common+"`r`n"+@'
local function LEKSpaceChooseNormalResearch()
 LEKAutopilotLog("R_LastPressTurn",Game.GetGameTurn())
 LEKAutopilotLog("R_PopupInfoType",tostring(g_popupInfoType))
 LEKAutopilotLog("R_Stealing",g_stealingTechTargetPlayer and 1 or 0)
 -- TechSelected() already passes g_activePlayer:GetNumFreeTechs() through to
 -- Network.SendResearch regardless of why the tree opened, so the same pick
 -- logic correctly covers both ordinary research and a free-tech grant.
 if g_popupInfoType~=ButtonPopupTypes.BUTTONPOPUP_CHOOSETECH or g_stealingTechTargetPlayer or not g_activePlayer then LEKAutopilotLog("R_LastResult","NOT_APPLICABLE");return false end
 local currentResearch=g_activePlayer:GetCurrentResearch()
 LEKAutopilotLog("R_CurrentResearch",currentResearch)
 LEKAutopilotLog("R_NumFreeTechs",g_activePlayer:GetNumFreeTechs())
 -- Network research assignment is asynchronous, while CanResearch remains
 -- true for the currently assigned technology.  Without this guard each
 -- Automate tick resends the same choice and queues another choose-tech
 -- popup, producing an endless flashing tree even though research is set.
 if currentResearch and currentResearch>=0 and g_activePlayer:GetNumFreeTechs()<=0 then
  LEKAutopilotLog("R_LastResult","ALREADY_RESEARCHING_CLOSING")
  LuaEvents.LEKSpaceAutomateModalHandled(1.7)
  CloseTechTree(); return true
 end
 Game.SetAdvisorRecommenderTech(g_activePlayerID);local flavors,best=LEKSpaceLeaderFlavors()
 for tech in GameInfo.Technologies() do if g_activePlayer:CanResearch(tech.ID) then
  local rec=0;for a=0,AdvisorTypes.NUM_ADVISOR_TYPES-1 do if Game.IsTechRecommended(tech.ID,a) then rec=rec+1 end end
  local c={id=tech.ID,rec=rec,score=LEKSpaceFlavorScore('Technology_Flavors','TechType',tech.Type,flavors)}
  if LEKSpaceBetter(c,best) then best=c end
 end end
 if not best then LEKAutopilotLog("R_LastResult","NO_LEGAL_TECH");return false end
 LEKAutopilotLog("R_LastResult","SELECTED_TECH");LEKAutopilotLog("R_LastTechID",best.id)
 -- TechSelected silently ignores clicks while EUI's g_RefreshRequested flag
 -- is set.  Automate ticks can arrive during that refresh, causing a close /
 -- immediate reopen loop with no research ever assigned.  Use the exact
 -- cached native call made by TechSelected's ordinary-research branch, then
 -- finish the required-choice modal explicitly.
 Network_SendResearch(best.id,g_activePlayer:GetNumFreeTechs(),-1,false)
 LuaEvents.LEKSpaceAutomateModalHandled(1.7)
 CloseTechTree(); return true
end
-- Automate (the Escape-menu button) never presses a real key, so this screen
-- would otherwise sit open forever once opened by a free tech or normal
-- research completion. Only act while this screen is actually the one
-- showing.
LuaEvents.LEKSpaceAutomateTick.Add(function()
 if not ContextPtr:IsHidden() then
  LuaEvents.LEKSpaceAutomateModalHandled(1.7)
  local ok,result=pcall(LEKSpaceChooseNormalResearch)
 end
end)
'@
 $techKeyAnchor="`tif uiMsg == KeyEvents_KeyDown`r`n`t`tand (wParam == Keys.VK_ESCAPE or wParam == Keys.VK_RETURN)`r`n`tthen`r`n`t`tCloseTechTree()`r`n`t`treturn true`r`n`tend"
 $techKey="`tif wParam == Keys.VK_SPACE and LEKSpaceChooseNormalResearch() then`r`n`t`treturn true`r`n`tend"
 Add-Bridge $tech 'ContextPtr:SetInputHandler(' $techKeyAnchor $techBody.Trim() $techKey
 & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Verify.ps1') -CivPath $civ
 if($LASTEXITCODE-ne 0){throw 'Bridge verification failed.'};W 'SPACE AUTOPILOT PRODUCTION/RESEARCH v0.1 INSTALLED.' Green
}catch{W ('ERROR: '+$_.Exception.Message) Red;exit 1}
