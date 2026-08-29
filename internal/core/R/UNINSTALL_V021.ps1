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
if(!$civ){throw "Civ V not found."}

$backs=Get-ChildItem $civ -Filter "*.lek_reroll_v021_backup" -Recurse -File -ErrorAction SilentlyContinue
$count=0

foreach($b in $backs){
    $suffix=".lek_reroll_v021_backup"
    $target=$b.FullName.Substring(0,$b.FullName.Length-$suffix.Length)

    Copy-Item $b.FullName $target -Force
    Remove-Item $b.FullName -Force

    Write-Host "Restored $target" -ForegroundColor Green
    $count++
}

Write-Host ""
Write-Host "v0.21 removed. Restored $count file(s)." -ForegroundColor Green
