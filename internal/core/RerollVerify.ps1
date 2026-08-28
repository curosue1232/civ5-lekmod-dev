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
    if(Test-Path (Join-Path $c "Assets\UI\InGame\Menus\GameMenu.lua")){
        $civ=$c
        break
    }
}
if(!$civ){throw "Civ V not found."}

$checks=@(
    @((Join-Path $civ "Assets\UI\InGame\Menus\GameMenu.lua"),"LEK_REROLL_V021_GAME_BEGIN"),
    @((Join-Path $civ "Assets\UI\FrontEnd\MainMenu.lua"),"LEK_REROLL_V021_MAIN_BEGIN"),
    @((Join-Path $civ "Assets\UI\FrontEnd\Multiplayer\MultiplayerSelect.lua"),"LEK_REROLL_V021_SELECT_BEGIN"),
    @((Join-Path $civ "Assets\UI\FrontEnd\Multiplayer\Lobby.lua"),"LEK_REROLL_V021_LOBBY_BEGIN"),
    @((Join-Path $civ "Assets\UI\FrontEnd\Multiplayer\GameSetup\MPGameSetupScreen.lua"),"LEK_REROLL_V021_SETUP_BEGIN"),
    @((Join-Path $civ "Assets\UI\FrontEnd\Multiplayer\StagingRoom.lua"),"LEK_REROLL_V021_STAGING_BEGIN")
)

$good=$true
foreach($c in $checks){
    $p=$c[0]; $m=$c[1]

    if((Test-Path $p) -and ([IO.File]::ReadAllText($p).Contains($m))){
        Write-Host "PASS  $m" -ForegroundColor Green
    }
    else {
        Write-Host "FAIL  $m" -ForegroundColor Red
        $good=$false
    }
}

Write-Host ""
if($good){
    Write-Host "ALL v0.21 PATCHES PRESENT." -ForegroundColor Green
}
else {
    Write-Host "v0.21 INSTALL INCOMPLETE." -ForegroundColor Red
}
