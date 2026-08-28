param([string]$CivPath="")
$ErrorActionPreference = "Stop"

function Find-CivV {
    param([string]$Requested)

    $candidates = @(
        $Requested,
        "${env:ProgramFiles(x86)}\Steam\steamapps\common\Sid Meier's Civilization V",
        "$env:ProgramFiles\Steam\steamapps\common\Sid Meier's Civilization V",
        "C:\SteamLibrary\steamapps\common\Sid Meier's Civilization V",
        "D:\SteamLibrary\steamapps\common\Sid Meier's Civilization V",
        "E:\SteamLibrary\steamapps\common\Sid Meier's Civilization V"
    )

    foreach($c in ($candidates | Where-Object {$_} | Select-Object -Unique)){
        if(Test-Path (Join-Path $c "Assets\UI\FrontEnd\Multiplayer\StagingRoom.lua")){
            return $c
        }
    }

    return $null
}

$civ = Find-CivV $CivPath

if(!$civ){
    throw "Civilization V not found."
}

$good = $true
$found = 0

$paths = @(
    (Join-Path $civ "Assets\UI\InGame\InGame.lua"),
    (Join-Path $civ "Assets\DLC\Expansion\UI\InGame\InGame.lua"),
    (Join-Path $civ "Assets\DLC\Expansion2\UI\InGame\InGame.lua"),
    (Join-Path $civ "Assets\DLC\LEKMOD_V30.7\UI\InGame.lua")
)

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " RAS MP BRIDGE v0.8.8 VERIFY" -ForegroundColor Cyan
Write-Host " RESTART SETTINGS REPLAY" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

foreach($p in $paths){
    if(Test-Path $p){
        $t = [IO.File]::ReadAllText($p)

        if(
            $t.Contains(
                "GTAS_MP_V0872_INGAME_HEARTBEAT"
            )
        ){
            $found++

            if(
                $t.Contains(
                    "GTAS_MP_BRIDGE_V088_REROLL_RUNTIME_REPLAY_BEGIN"
                )
            ){
                Write-Host "PASS  v0.8.8 replay handler: $p" -ForegroundColor Green
            }
            else {
                Write-Host "FAIL  v0.8.8 replay handler missing: $p" -ForegroundColor Red
                $good = $false
            }

            if(
                $t.Contains(
                    'GTAS_MP_SetBridgeValue('
                ) -and
                $t.Contains(
                    '"SkipRuntimeRASOnce",'
                ) -and
                $t.Contains(
                    'GTAS_MP_ApplyAdvancedSetup();'
                )
            ){
                Write-Host "PASS  safe runtime RAS replay call" -ForegroundColor Green
            }
            else {
                Write-Host "FAIL  runtime replay call incomplete" -ForegroundColor Red
                $good = $false
            }

            if(
                $t.Contains(
                    "RUNTIME_RAS_REPLAY_OK"
                )
            ){
                Write-Host "PASS  replay success heartbeat" -ForegroundColor Green
            }
            else {
                Write-Host "FAIL  replay heartbeat missing" -ForegroundColor Red
                $good = $false
            }
        }
    }
}

if($found -lt 1){
    Write-Host "FAIL  no v0.8.7.2 InGame safe-load hook found" -ForegroundColor Red
    $good = $false
}

Write-Host ""

if($good){
    Write-Host "RAS MP BRIDGE v0.8.8 VERIFIED." -ForegroundColor Green
}
else {
    Write-Host "VERIFY FOUND A PROBLEM." -ForegroundColor Red
}
