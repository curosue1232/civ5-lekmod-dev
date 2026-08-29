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
    if(Test-Path $c){
        $civ=$c
        break
    }
}
if(!$civ){ throw "Civ V not found." }

$suffix=".lek_ultrafast_mp_startup_v03_backup"

$targets=@(
    (Join-Path $civ "Assets\UI\FrontEnd\FrontEnd.lua"),
    (Join-Path $civ "Assets\UI\FrontEnd\MainMenu.lua"),
    (Join-Path $civ "Assets\UI\FrontEnd\Multiplayer\MultiplayerSelect.lua"),
    (Join-Path $civ "Assets\UI\FrontEnd\Multiplayer\Lobby.lua")
)

foreach($target in $targets){
    $backup="$target$suffix"

    if(Test-Path $backup){
        Copy-Item $backup $target -Force
        Remove-Item $backup -Force
        Write-Host "RESTORED  $target" -ForegroundColor Green
    }
}

$userSettings=Join-Path ([Environment]::GetFolderPath("MyDocuments")) "My Games\Sid Meier's Civilization 5\UserSettings.ini"
$userBackup="$userSettings$suffix"

if(Test-Path $userBackup){
    Copy-Item $userBackup $userSettings -Force
    Remove-Item $userBackup -Force
    Write-Host "RESTORED  UserSettings.ini" -ForegroundColor Green
}

# Restore only media disabled specifically by v0.3.
$disabledSuffix=".lek_ultrafast_mp_startup_v03_disabled"

foreach($dir in @(
    $civ,
    (Join-Path $civ "Assets\DLC\Expansion"),
    (Join-Path $civ "Assets\DLC\Expansion2")
)){
    if(!(Test-Path $dir)){ continue }

    $files=Get-ChildItem $dir -File -ErrorAction SilentlyContinue |
        Where-Object {$_.Name -like "*$disabledSuffix"}

    foreach($f in $files){
        $original=$f.FullName.Substring(0,$f.FullName.Length-$disabledSuffix.Length)

        if(!(Test-Path $original)){
            Move-Item $f.FullName $original -Force
            Write-Host "RESTORED  $original" -ForegroundColor Green
        }
    }
}

Write-Host ""
Write-Host "Ultra-Fast MP Startup v0.3 removed." -ForegroundColor Green
Write-Host "Any files previously disabled by v0.2 are left in their v0.2 state." -ForegroundColor Yellow
