param([string]$CivPath='')
$ErrorActionPreference='Stop';$I=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent;. (Join-Path $I 'LekTools.ps1')
try{if(Test-LEKCivRunning){throw 'Civilization V appears to be running. Close it before uninstalling.'};$c=Find-LEKCivV $CivPath;if(!$c){throw 'Civilization V install folder not found.'}
foreach($r in @('Assets\DLC\UI_bc1\CityView\CityView.lua','Assets\DLC\UI_bc1\TechTree\TechTree.lua')){$p=Join-LEKPath $c $r;if(Test-LEKPath $p){$t=[IO.File]::ReadAllText($p);$t=Remove-LEKMarkedBlock $t '-- LEK_EXT_SPACE_AUTOPILOT_PR_V01_BEGIN' '-- LEK_EXT_SPACE_AUTOPILOT_PR_V01_END';$t=Remove-LEKMarkedBlock $t '-- LEK_EXT_SPACE_AUTOPILOT_PR_V01_KEY_BEGIN' '-- LEK_EXT_SPACE_AUTOPILOT_PR_V01_KEY_END';Write-LEKUtf8NoBom $p $t}}
Write-Host 'SPACE AUTOPILOT PRODUCTION/RESEARCH REMOVED.' -ForegroundColor Green}catch{Write-Host ('ERROR: '+$_.Exception.Message) -ForegroundColor Red;exit 1}
