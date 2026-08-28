param(
    [string]$CivPath="",
    [ValidateSet("Auto","Required","Skip")]
    [string]$RASMode="Auto"
)
$ErrorActionPreference="Stop"
$Root=Split-Path -Parent $MyInvocation.MyCommand.Path
$C=Join-Path $Root "core"

function Test-SafePath([string]$Path,[bool]$Container=$false){
    if([string]::IsNullOrWhiteSpace($Path)){ return $false }
    try {
        if($Container){ return Test-Path -LiteralPath $Path -PathType Container -ErrorAction SilentlyContinue }
        return Test-Path -LiteralPath $Path -ErrorAction SilentlyContinue
    } catch { return $false }
}
function Join-Native([string]$Base,[string]$Child){
    if([string]::IsNullOrWhiteSpace($Base)){ return $null }
    try { return [IO.Path]::Combine($Base,$Child) } catch { return $null }
}
function Test-CivRoot([string]$Path){
    if([string]::IsNullOrWhiteSpace($Path)){ return $false }
    Test-SafePath (Join-Native $Path "Assets\UI\FrontEnd\Multiplayer\StagingRoom.lua")
}
function Get-SteamRoots {
    $roots=New-Object System.Collections.Generic.List[string]
    function Add-Root([string]$p){
        if(!$p){return}; $p=$p.Trim('"')
        if((Test-SafePath $p $true) -and (-not $roots.Contains($p))){$roots.Add($p)}
    }
    foreach($rp in @("HKCU:\Software\Valve\Steam","HKLM:\SOFTWARE\WOW6432Node\Valve\Steam","HKLM:\SOFTWARE\Valve\Steam")){
        try{$v=Get-ItemProperty -Path $rp -ErrorAction Stop; foreach($n in @("SteamPath","InstallPath")){if($v.$n){Add-Root ([string]$v.$n)}}}catch{}
    }
    if(${env:ProgramFiles(x86)}){Add-Root "${env:ProgramFiles(x86)}\Steam"}
    if($env:ProgramFiles){Add-Root "$env:ProgramFiles\Steam"}
    try{foreach($d in (Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){if($d.Root){Add-Root (Join-Native $d.Root "Steam"); Add-Root (Join-Native $d.Root "SteamLibrary")}}}catch{}
    @($roots)
}
function Get-SteamLibraries([string]$SteamRoot){
    $libs=New-Object System.Collections.Generic.List[string]
    if(Test-SafePath $SteamRoot $true){$libs.Add($SteamRoot)}
    $vdf=Join-Native $SteamRoot "steamapps\libraryfolders.vdf"
    if(Test-SafePath $vdf){
        try{
            $raw=[IO.File]::ReadAllText($vdf)
            foreach($m in [regex]::Matches($raw,'"path"\s+"([^"]+)"')){$lib=$m.Groups[1].Value -replace '\\\\','\'; if((Test-SafePath $lib $true)-and(-not $libs.Contains($lib))){$libs.Add($lib)}}
            foreach($m in [regex]::Matches($raw,'(?m)^\s*"\d+"\s+"([A-Za-z]:\\[^"]+)"')){$lib=$m.Groups[1].Value -replace '\\\\','\'; if((Test-SafePath $lib $true)-and(-not $libs.Contains($lib))){$libs.Add($lib)}}
        }catch{}
    }
    @($libs)
}
function Find-CivV([string]$Requested){
    if($Requested){$Requested=$Requested.Trim('"'); if(Test-CivRoot $Requested){return $Requested}}
    foreach($steam in Get-SteamRoots){foreach($lib in Get-SteamLibraries $steam){$candidate=Join-Native $lib "steamapps\common\Sid Meier's Civilization V"; if(Test-CivRoot $candidate){return $candidate}}}
    return $null
}


function Test-RASV088Installed([string]$Civ){
    $candidates = @(
        (Join-Native $Civ "Assets\UI\InGame\InGame.lua"),
        (Join-Native $Civ "Assets\DLC\Expansion\UI\InGame\InGame.lua"),
        (Join-Native $Civ "Assets\DLC\Expansion2\UI\InGame\InGame.lua"),
        (Join-Native $Civ "Assets\DLC\LEKMOD_V30.7\UI\InGame.lua")
    )
    foreach($p in $candidates){
        if((Test-SafePath $p) -and ([IO.File]::ReadAllText($p).Contains("GTAS_MP_BRIDGE_V088_REROLL_RUNTIME_REPLAY_BEGIN"))){
            return $true
        }
    }
    return $false
}

function Invoke-Verify([string]$Label,[string]$Script,[string]$Civ){
    Write-Host ""; Write-Host ("==== VERIFY " + $Label + " ====") -ForegroundColor Cyan
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Script -CivPath $Civ
    if($LASTEXITCODE -ne 0){ throw "$Label verification failed." }
}

try {
    $civ=Find-CivV $CivPath
    if(!$civ){ throw "Civilization V not found. Pass -CivPath if it is in a nonstandard Steam library." }
    Invoke-Verify "MP Reroll / Rehost v0.21" (Join-Path $C "RerollVerify.ps1") $civ
    Invoke-Verify "Host Instant Start v0.1" (Join-Path $C "HostVerify.ps1") $civ
    Invoke-Verify "UltraFast MP Startup v0.3.1" (Join-Path $C "UltraFastVerify.ps1") $civ
    $verifyRAS = $false
    switch($RASMode){
        "Required" { $verifyRAS = $true }
        "Skip"     { $verifyRAS = $false }
        "Auto"     { $verifyRAS = Test-RASV088Installed $civ }
    }

    if($verifyRAS){
        Invoke-Verify "RAS MP Bridge v0.8.8" (Join-Path $C "RASVerify.ps1") $civ
    } else {
        Write-Host ""
        if($RASMode -eq "Auto"){
            Write-Host "RAS v0.8.8 marker not detected; RAS verification skipped automatically." -ForegroundColor Yellow
        } else {
            Write-Host "RAS v0.8.8 verification skipped by installer state." -ForegroundColor Yellow
        }
    }
    Write-Host ""; Write-Host "ALL EXPECTED CORE PATCHES VERIFIED." -ForegroundColor Green
    exit 0
} catch {
    Write-Host ""; Write-Host ("VERIFY ERROR: " + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
