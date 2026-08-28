$ErrorActionPreference='Stop'
$Root=Split-Path -Parent $PSScriptRoot
$DefaultRepo='https://github.com/curosue1232/civ5-lekmod-dev.git'
$DefaultRepoPage='https://github.com/curosue1232/civ5-lekmod-dev'

function W([string]$s,[ConsoleColor]$c=[ConsoleColor]::Gray){ Write-Host $s -ForegroundColor $c }

try {
    W '============================================================' Cyan
    W ' LEK DEVELOPMENT WORKSPACE - GITHUB CONNECTOR v1.2.1' Cyan
    W '============================================================' Cyan
    W ''
    W 'This script never uploads your Civ V install, local path, backups, logs, or diagnostic ZIPs.' Green
    W 'Only files in this development workspace that are not ignored by .gitignore are committed.' Green
    W ''

    $git=Get-Command git.exe -ErrorAction SilentlyContinue
    if(!$git){
        W 'Git for Windows was not found.' Yellow
        W 'Install Git for Windows, then rerun this script.' White
        Start-Process 'https://git-scm.com/download/win'
        exit 2
    }

    $repo=Read-Host ('Existing repository URL ['+$DefaultRepo+']')
    if([string]::IsNullOrWhiteSpace($repo)){ $repo=$DefaultRepo }
    $repo=$repo.Trim()
    if($repo -notmatch '^https://github\.com/[^/]+/[^/]+(?:\.git)?$'){
        throw 'Expected a GitHub HTTPS repository URL such as https://github.com/user/repo.git'
    }
    if($repo -notmatch '\.git$'){ $repo += '.git' }

    Push-Location $Root
    try {
        if(!(Test-Path -LiteralPath (Join-Path $Root '.git') -PathType Container)){
            W 'Initializing local Git repository...' Cyan
            & git.exe init
            if($LASTEXITCODE -ne 0){ throw 'git init failed.' }
            & git.exe branch -M main
            if($LASTEXITCODE -ne 0){ throw 'Could not create/rename the main branch.' }
        }

        # Keep identity local to this workspace; do not alter the user's global Git settings.
        $name=(& git.exe config --local user.name 2>$null)
        if([string]::IsNullOrWhiteSpace(($name | Out-String))){
            & git.exe config --local user.name 'curosue1232'
            if($LASTEXITCODE -ne 0){ throw 'Could not configure the local Git author name.' }
        }
        $email=(& git.exe config --local user.email 2>$null)
        if([string]::IsNullOrWhiteSpace(($email | Out-String))){
            & git.exe config --local user.email '22933531+curosue1232@users.noreply.github.com'
            if($LASTEXITCODE -ne 0){ throw 'Could not configure the local Git author email.' }
        }

        # Do not probe a missing remote with `git remote get-url origin`.
        # Git writes "No such remote" to stderr, which Windows PowerShell 5.1 can
        # promote to a terminating NativeCommandError under ErrorActionPreference=Stop.
        $remoteNames=@(& git.exe remote)
        if($LASTEXITCODE -ne 0){ throw 'Could not list Git remotes.' }
        $hasOrigin=($remoteNames -contains 'origin')

        if($hasOrigin){
            $existingOrigin=(& git.exe remote get-url origin)
            if($LASTEXITCODE -ne 0){ throw 'Could not read the existing origin URL.' }
            $existingOrigin=(($existingOrigin | Out-String).Trim())
            if($existingOrigin -ne $repo){
                W ('Updating origin from '+$existingOrigin+' to '+$repo) Yellow
                & git.exe remote set-url origin $repo
                if($LASTEXITCODE -ne 0){ throw 'git remote set-url failed.' }
            }
        } else {
            W 'No origin remote exists yet; adding it now...' Cyan
            & git.exe remote add origin $repo
            if($LASTEXITCODE -ne 0){ throw 'git remote add origin failed.' }
        }

        W ('Origin: '+$repo) Green
        W ''
        W 'Checking the GitHub repository...' Cyan
        & git.exe ls-remote origin 1>$null 2>$null
        if($LASTEXITCODE -ne 0){
            W 'Git could not authenticate to the repository yet.' Yellow
            W 'A browser sign-in may be required by Git Credential Manager.' White
            W ('Repository page: '+$DefaultRepoPage) DarkGray
            Start-Process $DefaultRepoPage
            throw 'Could not access origin. Sign in to GitHub when prompted, then rerun this script.'
        }

        # The intended first-run repository is empty. If it is no longer empty, protect both histories.
        $remoteMain=(& git.exe ls-remote --heads origin main 2>$null)
        if($LASTEXITCODE -ne 0){ throw 'Could not inspect origin/main.' }
        if($remoteMain){
            W 'origin/main already exists.' Yellow
            & git.exe show-ref --verify --quiet refs/heads/main
            $hasLocalMain=($LASTEXITCODE -eq 0)
            if(!$hasLocalMain){
                W 'This local workspace has no commit yet; cloning the existing repository is safer than creating unrelated history.' Yellow
                throw 'Remote main is not empty. Use a fresh clone of the repository, or ask ChatGPT for the reconnect package.'
            }
        }

        & git.exe add --all
        if($LASTEXITCODE -ne 0){ throw 'git add failed.' }

        # `show-ref --quiet` returns 1 for an empty repository without emitting the
        # fatal stderr text that `rev-parse --verify HEAD` emits on first setup.
        & git.exe show-ref --verify --quiet refs/heads/main
        $hasHead=($LASTEXITCODE -eq 0)

        & git.exe diff --cached --quiet
        $hasStaged=($LASTEXITCODE -ne 0)
        if(!$hasHead -or $hasStaged){
            W 'Creating workspace commit...' Cyan
            & git.exe commit -m 'Establish LEK development workspace'
            if($LASTEXITCODE -ne 0){ throw 'git commit failed.' }
        } else {
            W 'No new workspace files need committing.' Green
        }

        W 'Pushing workspace to GitHub...' Cyan
        & git.exe push -u origin main
        if($LASTEXITCODE -ne 0){
            W ''
            W 'The repository exists, but Git could not complete the push.' Yellow
            W 'If a GitHub sign-in window appeared, finish signing in and rerun this script.' White
            throw 'git push failed.'
        }
    } finally { Pop-Location }

    W ''
    W 'GITHUB WORKSPACE READY.' Green
    W 'Repository: curosue1232/civ5-lekmod-dev' Cyan
    W 'ChatGPT can now read and update the repository directly.' Green
    W 'Future local updates: LEK_DEV_TOOL.bat -> option 8 (Sync workspace from GitHub).' Cyan
    exit 0
} catch {
    W ''
    W ('GITHUB SETUP ERROR: '+$_.Exception.Message) Red
    if($_.InvocationInfo -and $_.InvocationInfo.PositionMessage){ W $_.InvocationInfo.PositionMessage DarkGray }
    if($_.ScriptStackTrace){ W ('STACK: '+$_.ScriptStackTrace) DarkGray }
    exit 1
}
