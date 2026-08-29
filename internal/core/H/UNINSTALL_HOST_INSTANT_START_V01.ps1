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
$backup="$target.lek_host_instant_start_v01_backup"

if(!(Test-Path $backup)){
    throw "Instant Start backup not found. Nothing restored."
}

Copy-Item $backup $target -Force
Remove-Item $backup -Force

Write-Host ""
Write-Host "Host Instant Start v0.1 removed." -ForegroundColor Green
Write-Host "The exact StagingRoom.lua from before its installation was restored." -ForegroundColor Green
