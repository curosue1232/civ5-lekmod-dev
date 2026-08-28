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
    if(Test-Path (Join-Path $c "Assets\UI\FrontEnd\MainMenu.lua")){
        $civ=$c
        break
    }
}
if(!$civ){ throw "Civ V not found." }

$main=Join-Path $civ "Assets\UI\FrontEnd\MainMenu.lua"
$select=Join-Path $civ "Assets\UI\FrontEnd\Multiplayer\MultiplayerSelect.lua"
$lobby=Join-Path $civ "Assets\UI\FrontEnd\Multiplayer\Lobby.lua"
$reroll=Join-Path $civ "Assets\UI\InGame\Menus\GameMenu.lua"

$good=$true

Write-Host ""
Write-Host "ULTRA-FAST MP STARTUP v0.3.1 REROLL-SAFE VERIFY" -ForegroundColor Cyan
Write-Host ""

foreach($c in @(
    @($main,"LEK_ULTRAFAST_MP_STARTUP_V03_MAIN_BEGIN","MainMenu v0.3"),
    @($select,"LEK_ULTRAFAST_MP_STARTUP_V03_SELECT_BEGIN","MultiplayerSelect v0.3"),
    @($lobby,"LEK_ULTRAFAST_MP_STARTUP_V03_LOBBY_BEGIN","Lobby v0.3"),
    @($reroll,"LEK_REROLL_V021_GAME_BEGIN","Reroll/Rehost v0.21")
)){
    if((Test-Path $c[0]) -and ([IO.File]::ReadAllText($c[0]).Contains($c[1]))){
        Write-Host "PASS  $($c[2])" -ForegroundColor Green
    }
    else {
        Write-Host "FAIL  $($c[2])" -ForegroundColor Red
        $good=$false
    }
}

foreach($c in @(
    @($main,"LEK_ULTRAFAST_MP_STARTUP_V02_MAIN_BEGIN","old UltraFast MainMenu v0.2"),
    @($select,"LEK_ULTRAFAST_MP_STARTUP_V02_SELECT_BEGIN","old UltraFast Select v0.2"),
    @($lobby,"LEK_ULTRAFAST_MP_STARTUP_V02_LOBBY_BEGIN","old UltraFast Lobby v0.2")
)){
    if(!(Test-Path $c[0]) -or !([IO.File]::ReadAllText($c[0]).Contains($c[1]))){
        Write-Host "PASS  removed $($c[2])" -ForegroundColor Green
    }
    else {
        Write-Host "FAIL  still contains $($c[2])" -ForegroundColor Red
        $good=$false
    }
}

foreach($pair in @(
    @($main,"LEK_ULTRAFAST_MP_STARTUP_V03_MAIN_BEGIN","LEK_ULTRAFAST_MP_STARTUP_V03_MAIN_END","MainMenu"),
    @($select,"LEK_ULTRAFAST_MP_STARTUP_V03_SELECT_BEGIN","LEK_ULTRAFAST_MP_STARTUP_V03_SELECT_END","Select"),
    @($lobby,"LEK_ULTRAFAST_MP_STARTUP_V03_LOBBY_BEGIN","LEK_ULTRAFAST_MP_STARTUP_V03_LOBBY_END","Lobby")
)){
    $txt=[IO.File]::ReadAllText($pair[0])
    $a=$txt.IndexOf($pair[1])
    $b=$txt.IndexOf($pair[2],$a)

    if($a -ge 0 -and $b -gt $a){
        $block=$txt.Substring($a,$b-$a)

        # Only executable calls count. Ignore comments containing the text.
        if(!([regex]::IsMatch($block,'(?m)^[ \t]*ContextPtr:SetUpdate[ \t]*\('))){
            Write-Host "PASS  $($pair[3]) v0.3 has no executable SetUpdate call" -ForegroundColor Green
        }
        else {
            Write-Host "FAIL  $($pair[3]) v0.3 contains an executable SetUpdate call" -ForegroundColor Red
            $good=$false
        }
    }
}

Write-Host ""

if($good){
    Write-Host "ULTRA-FAST v0.3.1 IS REROLL-SAFE." -ForegroundColor Green
}
else {
    Write-Host "VERIFY FAILED - DO NOT TEST YET." -ForegroundColor Red
}
