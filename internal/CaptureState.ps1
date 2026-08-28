param([string]$CivPath='')
$ErrorActionPreference='Stop'
$Root=Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'LekTools.ps1')

function Copy-Safe([string]$Source,[string]$Dest){
    if(Test-LEKPath $Source){
        try { Copy-Item -LiteralPath $Source -Destination $Dest -Force } catch {}
    }
}

function Add-FileSummary([System.Collections.ArrayList]$Lines,[string]$Label,[string]$Path){
    [void]$Lines.Add(('FILE: '+$Label))
    [void]$Lines.Add(('PATH: '+$Path))
    [void]$Lines.Add(('SHA256: '+(Get-LEKSha256 $Path)))
    if(Test-LEKPath $Path){
        try {
            $txt=[IO.File]::ReadAllText($Path)
            $matches=@([regex]::Matches($txt,'(?m)^.*(?:LEK_MP_FAIR_AI_TRADES|LEK_EXT_FAIR_TRADES|GTAS_MP_|LEK_MP_REROLL|ULTRAFAST|HOST_INSTANT).*?$'))
            if($matches.Count -eq 0){ [void]$Lines.Add('MARKERS: none matched') }
            else {
                [void]$Lines.Add('MARKERS:')
                foreach($m in $matches){ [void]$Lines.Add(('  '+$m.Value.Trim())) }
            }
        } catch { [void]$Lines.Add(('READ ERROR: '+$_.Exception.Message)) }
    }
    [void]$Lines.Add('')
}

try {
    $civ=Find-LEKCivV $CivPath
    if(!$civ){ $m=Read-Host 'Paste Civilization V install folder'; if($m){$civ=Find-LEKCivV $m} }
    if(!$civ){ throw 'Civilization V was not found.' }

    $stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
    $work=Join-Path $env:TEMP ('LEK_DEV_STATE_'+$stamp)
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $work 'RAS') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $work 'FT') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $work 'LOGS') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $work 'DB') | Out-Null

    $lekUI=Join-LEKPath $civ 'Assets\DLC\LEKMOD_V30.7\UI'
    $inGame=Join-LEKPath $lekUI 'InGame.lua'
    $leader=Get-LEKLeaderRoot $civ
    $multi=Join-LEKPath $civ 'Assets\UI\FrontEnd\Multiplayer'
    $mpSetup=Join-LEKPath $multi 'GameSetup\MPGameSetupScreen.lua'
    $euiLoad=Join-LEKPath $civ 'Assets\DLC\UI_bc1\GameSetup\LoadScreen.lua'
    $staging=Join-LEKPath $multi 'StagingRoom.lua'
    $gtasStart=Join-LEKPath $multi 'GTAS_StartGame.lua'
    $gtasInitMap=Join-LEKPath $multi 'GTAS_InitMap.lua'
    $gtasPlaceWonders=Join-LEKPath $multi 'GTAS_PlaceWonders.lua'

    $lines=New-Object System.Collections.ArrayList
    [void]$lines.Add('LEK DEVELOPMENT STATE SNAPSHOT')
    [void]$lines.Add(('Created: '+(Get-Date).ToString('s')))
    [void]$lines.Add(('CivPath: '+$civ))
    [void]$lines.Add('Workspace: frozen Core v1.3 + isolated development extensions')
    [void]$lines.Add('')

    Add-FileSummary $lines 'Lekmod InGame.lua' $inGame
    Add-FileSummary $lines 'EUI LeaderHeadRoot.lua' $leader
    Add-FileSummary $lines 'MPGameSetupScreen.lua' $mpSetup
    Add-FileSummary $lines 'EUI LoadScreen.lua' $euiLoad
    Add-FileSummary $lines 'StagingRoom.lua' $staging
    Add-FileSummary $lines 'GTAS_StartGame.lua' $gtasStart
    Add-FileSummary $lines 'GTAS_InitMap.lua' $gtasInitMap
    Add-FileSummary $lines 'GTAS_PlaceWonders.lua' $gtasPlaceWonders

    [IO.File]::WriteAllLines((Join-Path $work 'SUMMARY.txt'),[string[]]$lines,(New-Object Text.UTF8Encoding($false)))

    Copy-Safe $inGame (Join-Path $work 'InGame.lua')
    Copy-Safe $leader (Join-Path $work 'LeaderHeadRoot.lua')
    Copy-Safe $mpSetup (Join-Path $work 'RAS\MPGameSetupScreen.lua')
    Copy-Safe $euiLoad (Join-Path $work 'RAS\LoadScreen.lua')
    Copy-Safe $staging (Join-Path $work 'RAS\StagingRoom.lua')
    Copy-Safe $gtasStart (Join-Path $work 'RAS\GTAS_StartGame.lua')
    Copy-Safe $gtasInitMap (Join-Path $work 'RAS\GTAS_InitMap.lua')
    Copy-Safe $gtasPlaceWonders (Join-Path $work 'RAS\GTAS_PlaceWonders.lua')

    if(Test-LEKPath $lekUI -Container){
        foreach($f in @(Get-ChildItem -LiteralPath $lekUI -File -ErrorAction SilentlyContinue)){
            if($f.Name -match '^LEK(?:MP)?FairTrades.*\.(lua|xml)$'){
                Copy-Safe $f.FullName (Join-Path $work ('FT\'+$f.Name))
            }
        }
    }

    # Bridge support files copied to FrontEnd\Multiplayer by the RAS MP bridge.
    foreach($n in @('GTAS_MP_Bridge.lua','GTAS_MP_DB_Bootstrap.lua','GTAS_Constants.lua','GTAS_Utilities.lua')){
        Copy-Safe (Join-LEKPath $multi $n) (Join-Path $work ('RAS\'+$n))
    }

    $igCandidates=@(
        (Join-LEKPath $civ 'Assets\UI\InGame\InGame.lua'),
        (Join-LEKPath $civ 'Assets\DLC\Expansion\UI\InGame\InGame.lua'),
        (Join-LEKPath $civ 'Assets\DLC\Expansion2\UI\InGame\InGame.lua'),
        (Join-LEKPath $civ 'Assets\DLC\LEKMOD_V30.7\UI\InGame.lua')
    )
    $igIndex=0
    foreach($p in $igCandidates){
        if(Test-LEKPath $p){
            $igIndex++
            Copy-Safe $p (Join-Path $work ('RAS\InGame_'+$igIndex+'.lua'))
        }
    }

    $userRoots=@(
        (Join-LEKPath $env:USERPROFILE 'Documents\My Games\Sid Meier''s Civilization 5'),
        (Join-LEKPath $env:USERPROFILE 'OneDrive\Documents\My Games\Sid Meier''s Civilization 5')
    )
    foreach($ur in $userRoots){
        $mu=Join-LEKPath $ur 'ModUserData'
        if(Test-LEKPath $mu -Container){
            foreach($db in @(Get-ChildItem -LiteralPath $mu -File -ErrorAction SilentlyContinue)){
                if($db.Name -match '^(LEK_FAIR_TRADES|GTAS|LEK_MP_REROLL_REHOST).*\.db$'){
                    Copy-Safe $db.FullName (Join-Path $work ('DB\'+$db.Name))
                }
            }
            break
        }
    }

    $logRoots=@(
        (Join-LEKPath $env:USERPROFILE 'Documents\My Games\Sid Meier''s Civilization 5\Logs'),
        (Join-LEKPath $env:USERPROFILE 'OneDrive\Documents\My Games\Sid Meier''s Civilization 5\Logs')
    )
    foreach($lr in $logRoots){
        if(Test-LEKPath $lr -Container){
            foreach($name in @('Lua.log','Database.log','xml.log','net_message_debug.log')){
                $p=Join-LEKPath $lr $name
                if(Test-LEKPath $p){
                    try { Get-Content -LiteralPath $p -Tail 8000 | Set-Content -LiteralPath (Join-Path $work ('LOGS\'+$name)) -Encoding UTF8 } catch {}
                }
            }
            break
        }
    }

    foreach($src in @('internal\fair\UI\LEKFairTrades.lua','internal\fair\UI\LEKFairTrades.xml','PROJECT_STATE.md')){
        $p=Join-Path $Root $src
        if(Test-LEKPath $p){ Copy-Safe $p (Join-Path $work ('SOURCE_'+([IO.Path]::GetFileName($p)))) }
    }

    $zip=Join-Path $Root ('LEK_DEV_STATE_'+$stamp+'.zip')
    if(Test-Path $zip){ Remove-Item $zip -Force }
    Compress-Archive -Path (Join-Path $work '*') -DestinationPath $zip -CompressionLevel Optimal
    Remove-Item -LiteralPath $work -Recurse -Force

    Write-Host ''
    Write-Host 'ONE development snapshot created:' -ForegroundColor Green
    Write-Host $zip -ForegroundColor Green
    Write-Host 'Upload only that ZIP for normal debugging. It includes Fair Trades + RAS/reroll/wonder context.' -ForegroundColor Cyan
    exit 0
} catch {
    Write-Host ('STATE CAPTURE ERROR: '+$_.Exception.Message) -ForegroundColor Red
    if($_.InvocationInfo -and $_.InvocationInfo.PositionMessage){ Write-Host $_.InvocationInfo.PositionMessage -ForegroundColor DarkGray }
    if($_.ScriptStackTrace){ Write-Host ('STACK: '+$_.ScriptStackTrace) -ForegroundColor DarkGray }
    exit 1
}
