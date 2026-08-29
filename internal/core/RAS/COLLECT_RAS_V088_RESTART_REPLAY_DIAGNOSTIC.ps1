$ErrorActionPreference = "Continue"

$user =
    Join-Path ([Environment]::GetFolderPath("MyDocuments")) "My Games\Sid Meier's Civilization 5"

$out =
    Join-Path $PSScriptRoot "RAS_V088_RESTART_REPLAY_DIAGNOSTIC"

New-Item -ItemType Directory -Path $out -Force |
    Out-Null

foreach($name in @(
    "Lua.log",
    "Database.log",
    "xml.log",
    "Modding.log",
    "net_message_debug.log"
)){
    $p =
        Join-Path $user ("Logs\" + $name)

    if(Test-Path $p){
        Copy-Item $p (Join-Path $out $name) -Force
    }
}

foreach($name in @(
    "LEK_MP_REROLL_REHOST-21.db",
    "GTAS_MP_BRIDGE-8.db",
    "GTAS_AdvancedSetupMod-15.db"
)){
    $p =
        Join-Path $user ("ModUserData\" + $name)

    if(Test-Path $p){
        Copy-Item $p (Join-Path $out $name) -Force
    }
}

Write-Host ""
Write-Host "Collected v0.8.8 restart replay diagnostic to:" -ForegroundColor Cyan
Write-Host "  $out"
