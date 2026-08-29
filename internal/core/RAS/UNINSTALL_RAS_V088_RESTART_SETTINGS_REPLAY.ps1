param([string]$CivPath="")
$ErrorActionPreference = "Stop"

$Suffix =
    ".lek_ras_v088_replay_backup"

$candidates = @(
    $CivPath,
    "${env:ProgramFiles(x86)}\Steam\steamapps\common\Sid Meier's Civilization V",
    "$env:ProgramFiles\Steam\steamapps\common\Sid Meier's Civilization V",
    "C:\SteamLibrary\steamapps\common\Sid Meier's Civilization V",
    "D:\SteamLibrary\steamapps\common\Sid Meier's Civilization V",
    "E:\SteamLibrary\steamapps\common\Sid Meier's Civilization V"
) |
    Where-Object {$_}

$civ = $null

foreach($c in $candidates){
    if(Test-Path $c){
        $civ = $c
        break
    }
}

if(!$civ){
    throw "Civ V not found."
}

Get-ChildItem $civ -Recurse -File -Filter "*$Suffix" -ErrorAction SilentlyContinue |
    ForEach-Object {
        $target =
            $_.FullName.Substring(
                0,
                $_.FullName.Length -
                $Suffix.Length
            )

        Copy-Item $_.FullName $target -Force
        Remove-Item $_.FullName -Force

        Write-Host "RESTORED  $target" -ForegroundColor Green
    }

Write-Host ""
Write-Host "RAS v0.8.8 Restart Settings Replay removed." -ForegroundColor Green
