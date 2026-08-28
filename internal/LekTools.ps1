# LEK Stable Development Tools v1.1
# Shared Windows PowerShell 5.1-safe helpers for all future extension installers.
Set-StrictMode -Version 2.0

function Test-LEKPath([string]$Path,[switch]$Container){
    if([string]::IsNullOrWhiteSpace($Path)){ return $false }
    try {
        if($Container){ return Test-Path -LiteralPath $Path -PathType Container -ErrorAction SilentlyContinue }
        return Test-Path -LiteralPath $Path -ErrorAction SilentlyContinue
    } catch { return $false }
}

function Join-LEKPath([string]$Base,[string]$Child){
    if([string]::IsNullOrWhiteSpace($Base)){ return $null }
    try { return [IO.Path]::Combine($Base,$Child) } catch { return $null }
}

function Test-LEKCivRoot([string]$Path){
    if([string]::IsNullOrWhiteSpace($Path)){ return $false }
    return (Test-LEKPath (Join-LEKPath $Path 'Assets\UI\FrontEnd\Multiplayer\StagingRoom.lua'))
}

function Get-LEKSteamRoots {
    # Use the same Windows PowerShell 5.1-safe string-list pattern as the
    # already-proven LEK Core v1.3 verifier.  Mutate the list object in the
    # nested helper instead of assigning to a script-scope variable.
    $roots = New-Object System.Collections.Generic.List[string]
    function AddRoot([string]$p){
        if([string]::IsNullOrWhiteSpace($p)){ return }
        $p=$p.Trim('"')
        if((Test-LEKPath $p -Container) -and (-not $roots.Contains($p))){
            [void]$roots.Add($p)
        }
    }
    foreach($rp in @('HKCU:\Software\Valve\Steam','HKLM:\SOFTWARE\WOW6432Node\Valve\Steam','HKLM:\SOFTWARE\Valve\Steam')){
        try {
            $v=Get-ItemProperty -Path $rp -ErrorAction Stop
            foreach($n in @('SteamPath','InstallPath')){ if($v.$n){ AddRoot ([string]$v.$n) } }
        } catch {}
    }
    if(${env:ProgramFiles(x86)}){ AddRoot "${env:ProgramFiles(x86)}\Steam" }
    if($env:ProgramFiles){ AddRoot "$env:ProgramFiles\Steam" }
    try {
        foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){
            if($d.Root){ AddRoot (Join-LEKPath $d.Root 'Steam'); AddRoot (Join-LEKPath $d.Root 'SteamLibrary') }
        }
    } catch {}
    return @($roots)
}

function Get-LEKSteamLibraries([string]$SteamRoot){
    $libs=@()
    if(Test-LEKPath $SteamRoot -Container){ $libs += $SteamRoot }
    $vdf=Join-LEKPath $SteamRoot 'steamapps\libraryfolders.vdf'
    if(Test-LEKPath $vdf){
        try {
            $raw=[IO.File]::ReadAllText($vdf)
            foreach($m in @([regex]::Matches($raw,'"path"\s+"([^"]+)"'))){
                $lib=$m.Groups[1].Value -replace '\\\\','\'
                if((Test-LEKPath $lib -Container) -and ($libs -notcontains $lib)){ $libs += $lib }
            }
            foreach($m in @([regex]::Matches($raw,'(?m)^\s*"\d+"\s+"([A-Za-z]:\\[^"]+)"'))){
                $lib=$m.Groups[1].Value -replace '\\\\','\'
                if((Test-LEKPath $lib -Container) -and ($libs -notcontains $lib)){ $libs += $lib }
            }
        } catch {}
    }
    return @($libs)
}

function Find-LEKCivV([string]$Requested=''){
    if($Requested){
        $Requested=$Requested.Trim('"')
        if(Test-LEKCivRoot $Requested){ return $Requested }
    }
    foreach($steam in @(Get-LEKSteamRoots)){
        foreach($lib in @(Get-LEKSteamLibraries $steam)){
            $candidate=Join-LEKPath $lib 'steamapps\common\Sid Meier''s Civilization V'
            if(Test-LEKCivRoot $candidate){ return $candidate }
        }
    }
    return $null
}

function Get-LEKLeaderRoot([string]$Civ){
    $exact=Join-LEKPath $Civ 'Assets\DLC\UI_bc1\LeaderHead\LeaderHeadRoot.lua'
    if(Test-LEKPath $exact){ return $exact }
    $base=Join-LEKPath $Civ 'Assets\DLC\UI_bc1'
    if(!(Test-LEKPath $base -Container)){ return $null }
    try {
        $f=Get-ChildItem -LiteralPath $base -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ieq 'LeaderHeadRoot.lua' } |
            Select-Object -First 1
        if($f){ return $f.FullName }
    } catch {}
    return $null
}

function Write-LEKUtf8NoBom([string]$Path,[string]$Text){
    [IO.File]::WriteAllText($Path,$Text,(New-Object Text.UTF8Encoding($false)))
}

function Get-LEKSha256([string]$Path){
    if(!(Test-LEKPath $Path)){ return 'MISSING' }
    try { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() } catch { return 'HASH_ERROR' }
}

function Test-LEKContains([string]$Path,[string]$Needle){
    if(!(Test-LEKPath $Path)){ return $false }
    try { return [IO.File]::ReadAllText($Path).Contains($Needle) } catch { return $false }
}

function Remove-LEKMarkedBlock([string]$Text,[string]$Begin,[string]$End){
    $pattern='(?ms)\r?\n?'+[regex]::Escape($Begin)+'.*?'+[regex]::Escape($End)+'\r?\n?'
    return [regex]::Replace($Text,$pattern,"`r`n")
}

function Set-LEKMarkedBlock([string]$Path,[string]$Begin,[string]$End,[string]$Body){
    $text=[IO.File]::ReadAllText($Path)
    $text=Remove-LEKMarkedBlock $text $Begin $End
    $block="`r`n$Begin`r`n$Body`r`n$End`r`n"
    Write-LEKUtf8NoBom $Path ($text.TrimEnd()+$block)
}

function Backup-LEKFileOnce([string]$Path,[string]$BackupRoot,[string]$Key){
    if(!(Test-LEKPath $Path)){ throw "Cannot back up missing file: $Path" }
    New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null
    $safe=($Key -replace '[^A-Za-z0-9_.-]','_')
    $dest=Join-Path $BackupRoot ($safe+'.base')
    if(!(Test-LEKPath $dest)){ Copy-Item -LiteralPath $Path -Destination $dest -Force }
    return $dest
}

function Test-LEKCivRunning {
    try {
        $p=@(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like 'CivilizationV*' -or $_.ProcessName -like 'Civ5*' })
        return ($p.Count -gt 0)
    } catch { return $false }
}
