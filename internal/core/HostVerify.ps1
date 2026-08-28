param([string]$CivPath="")
$ErrorActionPreference="Stop"

$candidates=@(
    $CivPath,
    "${env:ProgramFiles(x86)}\Steam\steamapps\common\Sid Meier's Civilization V",
    "$env:ProgramFiles\Steam\steamapps\common\Sid Meier's Civilization V",
    "C:\SteamLibrary\steamapps\common\Sid Meier's Civilization V",
    "D:\SteamLibrary\steamapps\common\Sid Meier's Civilization V",
    "E:\SteamLibrary\steamapps\common\Sid Meier's Civilization V"
) | Where-Object {$_}

$civ=$null

foreach($c in $candidates){
    $p=Join-Path $c "Assets\UI\FrontEnd\Multiplayer\StagingRoom.lua"

    if(Test-Path $p){
        $civ=$c
        break
    }
}

if(!$civ){
    throw "Civ V not found."
}

$target=Join-Path $civ "Assets\UI\FrontEnd\Multiplayer\StagingRoom.lua"
$txt=[IO.File]::ReadAllText($target)

Write-Host ""
Write-Host "HOST INSTANT START v0.1 VERIFY" -ForegroundColor Cyan
Write-Host ""

$checks=@(
    "LEK_HOST_INSTANT_START_V01_BEGIN",
    "LEK_InstantStart_Launch",
    "START GAME NOW",
    "Matchmaking.LaunchMultiplayerGame"
)

$good=$true

foreach($needle in $checks){
    if($txt.Contains($needle)){
        Write-Host "PASS  $needle" -ForegroundColor Green
    }
    else {
        Write-Host "FAIL  $needle" -ForegroundColor Red
        $good=$false
    }
}

if($txt.Contains("LEK_REROLL_V021_STAGING_BEGIN")){
    Write-Host "PASS  Reroll/Rehost v0.21 still present" -ForegroundColor Green
}

Write-Host ""

if($good){
    Write-Host "HOST INSTANT START IS INSTALLED." -ForegroundColor Green
}
else {
    Write-Host "INSTALL INCOMPLETE." -ForegroundColor Red
}
