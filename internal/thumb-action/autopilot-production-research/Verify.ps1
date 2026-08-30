param([string]$CivPath='')
$ErrorActionPreference='Stop';$I=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent;. (Join-Path $I 'LekTools.ps1')
function W($s,[ConsoleColor]$c=[ConsoleColor]::Gray){Write-Host $s -ForegroundColor $c}
try{$c=Find-LEKCivV $CivPath;if(!$c){throw 'Civilization V install folder not found.'}
$a=[IO.File]::ReadAllText((Join-LEKPath $c 'Assets\DLC\UI_bc1\CityView\CityView.lua'));$b=[IO.File]::ReadAllText((Join-LEKPath $c 'Assets\DLC\UI_bc1\TechTree\TechTree.lua'))
$q=[ordered]@{
'singular production bridge'=([regex]::Matches($a,'LEK_EXT_SPACE_AUTOPILOT_PR_V01_BEGIN').Count-eq 1 -and [regex]::Matches($a,'LEK_EXT_SPACE_AUTOPILOT_PR_V01_KEY_BEGIN').Count-eq 1)
'singular research bridge'=([regex]::Matches($b,'LEK_EXT_SPACE_AUTOPILOT_PR_V01_BEGIN').Count-eq 1 -and [regex]::Matches($b,'LEK_EXT_SPACE_AUTOPILOT_PR_V01_KEY_BEGIN').Count-eq 1)
'all production families legal'=($a.Contains('city.CanConstruct')-and$a.Contains('LEKSpaceCanTrainUnit')-and$a.Contains('city.CanCreate')-and$a.Contains('city.CanMaintain'))
'work boats excluded when no sea resource is reachable'=($a.Contains('DefaultUnitAI=="UNITAI_WORKER_SEA"')-and$a.Contains('LEKSpaceHasSeaWorkTarget')-and$a.Contains('city:CanTrain(id)'))
'production and research consume Automate modal ticks'=($a.Contains('LuaEvents.LEKSpaceAutomateTick.Add')-and$a.Contains('LuaEvents.LEKSpaceAutomateModalHandled(1.7)')-and$a.Contains('pcall(LEKSpaceChooseProduction)')-and$b.Contains('LuaEvents.LEKSpaceAutomateTick.Add')-and$b.Contains('LuaEvents.LEKSpaceAutomateModalHandled(1.7)')-and$b.Contains('pcall(LEKSpaceChooseNormalResearch)'))
'Automate listeners only act while their own screen is visible'=($a.Contains('if not ContextPtr:IsHidden() then')-and$b.Contains('if not ContextPtr:IsHidden() then'))
'production advisor and commit'=($a.Contains('Game.SetAdvisorRecommenderCity(city)')-and$a.Contains('Game.CityPushOrder(city,best.order,best.id,false,false,true)'))
'research excludes steal-tech, covers ordinary and free-tech grants'=($b.Contains('g_stealingTechTargetPlayer')-and!$b.Contains('g_activePlayer:GetNumFreeTechs()>0'))
'research legality advisor commit'=($b.Contains('g_activePlayer:CanResearch(tech.ID)')-and$b.Contains('Game.IsTechRecommended')-and$b.Contains('Network_SendResearch(best.id,g_activePlayer:GetNumFreeTechs(),-1,false)')-and$b.Contains('CloseTechTree(); return true'))
'flavor deterministic ties'=($a.Contains('GameInfo.Leader_Flavors')-and$b.Contains('GameInfo.Leader_Flavors')-and$a.Contains('a.id<b.id')-and$b.Contains('a.id<b.id'))
'KeyDown modal no held state'=($a.Contains('wParam == Keys.VK_SPACE and LEKSpaceChooseProduction()')-and$b.Contains('wParam == Keys.VK_SPACE and LEKSpaceChooseNormalResearch()')-and!$a.Contains('AutopilotHeld')-and!$b.Contains('AutopilotHeld'))
'no concatenation ran two statements together'=(!$a.Contains('endlocal')-and!$b.Contains('endlocal')-and!$a.Contains('endfunction')-and!$b.Contains('endfunction'))}
$ok=$true;foreach($x in $q.GetEnumerator()){if($x.Value){W ('PASS  '+$x.Key) Green}else{W ('FAIL  '+$x.Key) Red;$ok=$false}};if(!$ok){exit 1};W 'SPACE AUTOPILOT PRODUCTION/RESEARCH v0.1 VERIFIED.' Green}catch{W ('ERROR: '+$_.Exception.Message) Red;exit 1}
