$ErrorActionPreference="Stop"

$db=Join-Path ([Environment]::GetFolderPath("MyDocuments")) "My Games\Sid Meier's Civilization 5\ModUserData\LEK_MP_REROLL_REHOST-21.db"

Write-Host ""
Write-Host "v0.21 USER-DATA FILE" -ForegroundColor Cyan
Write-Host $db
Write-Host ""

if(Test-Path $db){
    $size=(Get-Item $db).Length
    Write-Host "EXISTS - size $size bytes" -ForegroundColor Green
    Write-Host ""
    Write-Host "If auto-join fails, upload THIS DB from the affected CLIENT PC." -ForegroundColor Cyan
}
else {
    Write-Host "NOT CREATED YET." -ForegroundColor Yellow
}
