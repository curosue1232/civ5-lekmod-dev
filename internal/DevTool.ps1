param(
    [string]$Action='',
    [string]$CivPath=''
)

$ErrorActionPreference='Stop'
$Root=Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'LekTools.ps1')

function W([string]$s,[ConsoleColor]$c=[ConsoleColor]::Gray){ Write-Host $s -ForegroundColor $c }
function Wait-Key { Write-Host ''; Write-Host 'Press any key to return to the menu . . .' -ForegroundColor DarkGray; [void][Console]::ReadKey($true) }

$LocalDir=Join-Path $Root 'local'
$PathFile=Join-Path $LocalDir 'civ_path.txt'
New-Item -ItemType Directory -Force -Path $LocalDir | Out-Null

function Save-CivPath([string]$Path){
    if(!(Test-LEKCivRoot $Path)){ throw 'That folder is not a Civilization V install folder.' }
    [IO.File]::WriteAllText($PathFile,$Path,(New-Object Text.UTF8Encoding($false)))
}

function Get-SavedCivPath {
    if(Test-Path -LiteralPath $PathFile -PathType Leaf){
        try {
            $p=[IO.File]::ReadAllText($PathFile).Trim()
            if(Test-LEKCivRoot $p){ return $p }
        } catch {}
    }
    return $null
}

function Resolve-Civ([switch]$AllowPrompt){
    if($CivPath){
        $p=Find-LEKCivV $CivPath
        if($p){ Save-CivPath $p; return $p }
    }
    $saved=Get-SavedCivPath
    if($saved){ return $saved }
    $auto=Find-LEKCivV ''
    if($auto){ Save-CivPath $auto; return $auto }
    if($AllowPrompt){
        $manual=Read-Host 'Paste your Civilization V install folder'
        if($manual){
            $p=Find-LEKCivV $manual.Trim('"')
            if($p){ Save-CivPath $p; return $p }
        }
    }
    return $null
}

function Run-Script([string]$Rel,[string[]]$Extra=@()){
    $civ=Resolve-Civ -AllowPrompt
    if(!$civ){ throw 'Civilization V was not found. Use option 1 to set the path.' }
    $script=Join-Path $Root $Rel
    if(!(Test-Path -LiteralPath $script -PathType Leaf)){ throw ('Missing workspace script: '+$Rel) }
    $psArgs=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$script,'-CivPath',$civ) + $Extra
    & powershell.exe @psArgs
    return [int]$LASTEXITCODE
}

function Set-PathInteractive {
    $current=Get-SavedCivPath
    if($current){ W ('Current saved path: '+$current) Green }
    $auto=Find-LEKCivV ''
    if($auto){
        W ('Detected: '+$auto) Cyan
        $answer=Read-Host 'Save this path? [Y/n]'
        if([string]::IsNullOrWhiteSpace($answer) -or $answer -match '^[Yy]'){
            Save-CivPath $auto
            W 'Saved.' Green
            return
        }
    }
    $manual=Read-Host 'Paste Civilization V install folder'
    if(!$manual){ return }
    $p=Find-LEKCivV $manual.Trim('"')
    if(!$p){ throw 'That folder did not validate as Civilization V.' }
    Save-CivPath $p
    W ('Saved: '+$p) Green
}

function Sync-Git {
    $git=Get-Command git.exe -ErrorAction SilentlyContinue
    if(!$git){
        W 'Git for Windows is not installed or is not in PATH.' Yellow
        W 'You can still use this workspace normally. GitHub setup instructions are in README.md.' Gray
        return 2
    }
    if(!(Test-Path -LiteralPath (Join-Path $Root '.git') -PathType Container)){
        W 'This folder is not a Git clone yet.' Yellow
        W 'Run GITHUB_SETUP.bat once, or clone the repository after it is created.' Gray
        return 2
    }
    Push-Location $Root
    try {
        & git.exe status --short 2>&1 | ForEach-Object { Write-Host ([string]$_) }
        $ec=[int]$LASTEXITCODE
        if($ec -ne 0){ return $ec }
        & git.exe pull --ff-only 2>&1 | ForEach-Object { Write-Host ([string]$_) }
        return [int]$LASTEXITCODE
    } finally { Pop-Location }
}

function Show-Header {
    Clear-Host
    W '============================================================' Cyan
    W ' LEKMOD 30.7 DEVELOPMENT TOOL v1.3' Cyan
    W ' Frozen Core v1.3 + Isolated Development Extensions' Cyan
    W '============================================================' Cyan
    $p=Get-SavedCivPath
    if($p){ W ('Civ V: '+$p) Green } else { W 'Civ V: not saved yet' Yellow }
    W ''
}

function Invoke-Action([string]$A){
    switch($A.ToLowerInvariant()){
        'path'      { Set-PathInteractive; return 0 }
        'baseline'  { return (Run-Script 'internal\BaselineCheck.ps1') }
        'core'      { return (Run-Script 'internal\CoreVerify.ps1' @('-RASMode','Auto')) }
        'fair-install' { return (Run-Script 'internal\fair\Install.ps1') }
        'fair-verify'  { return (Run-Script 'internal\fair\Verify.ps1') }
        'fair-remove'  { return (Run-Script 'internal\fair\Uninstall.ps1') }
        'capture'   { return (Run-Script 'internal\CaptureState.ps1') }
        'sync'      { return (Sync-Git) }
        'wonder-install' { return (Run-Script 'internal\ras-wonder\Install.ps1') }
        'wonder-verify'  { return (Run-Script 'internal\ras-wonder\Verify.ps1') }
        'wonder-remove'  { return (Run-Script 'internal\ras-wonder\Uninstall.ps1') }
        default     { throw ('Unknown action: '+$A) }
    }
}

try {
    if($Action){ exit (Invoke-Action $Action) }
    while($true){
        Show-Header
        W ' 1   Set / save Civilization V path' White
        W ' 2   Baseline check (core + clean extension state)' White
        W ' 3   Verify frozen Core v1.3' White
        W ' 4   Install / update Fair Trades' White
        W ' 5   Verify Fair Trades' White
        W ' 6   Uninstall Fair Trades only' White
        W ' 7   Capture ONE full diagnostic ZIP' White
        W ' 8   Sync workspace from GitHub (git pull)' White
        W ' 9   Install / update RAS wonder graphics hotfix' White
        W ' 10  Verify RAS wonder graphics hotfix' White
        W ' 11  Uninstall RAS wonder graphics hotfix' White
        W ' G   One-time GitHub repository setup' White
        W ' Q   Quit' White
        W ''
        $choice=(Read-Host 'Choose').Trim()
        if($choice -match '^[Qq]$'){ break }
        try {
            $ec=0
            switch($choice.ToUpperInvariant()){
                '1' { $ec=Invoke-Action 'path' }
                '2' { $ec=Invoke-Action 'baseline' }
                '3' { $ec=Invoke-Action 'core' }
                '4' { $ec=Invoke-Action 'fair-install' }
                '5' { $ec=Invoke-Action 'fair-verify' }
                '6' { $ec=Invoke-Action 'fair-remove' }
                '7' { $ec=Invoke-Action 'capture' }
                '8' { $ec=Invoke-Action 'sync' }
                '9' { $ec=Invoke-Action 'wonder-install' }
                '10' { $ec=Invoke-Action 'wonder-verify' }
                '11' { $ec=Invoke-Action 'wonder-remove' }
                'G' {
                    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'internal\GitHubSetup.ps1')
                    $ec=[int]$LASTEXITCODE
                }
                default { W 'Unknown choice.' Yellow; $ec=2 }
            }
            if($ec -eq 0){ W 'Completed successfully.' Green }
            else { W ('Command finished with exit code '+$ec+'.') Yellow }
        } catch {
            W ('ERROR: '+$_.Exception.Message) Red
            if($_.InvocationInfo -and $_.InvocationInfo.PositionMessage){ W $_.InvocationInfo.PositionMessage DarkGray }
            if($_.ScriptStackTrace){ W ('STACK: '+$_.ScriptStackTrace) DarkGray }
        }
        Wait-Key
    }
    exit 0
} catch {
    W ('DEV TOOL ERROR: '+$_.Exception.Message) Red
    if($_.InvocationInfo -and $_.InvocationInfo.PositionMessage){ W $_.InvocationInfo.PositionMessage DarkGray }
    if($_.ScriptStackTrace){ W ('STACK: '+$_.ScriptStackTrace) DarkGray }
    exit 1
}
