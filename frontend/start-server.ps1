# PowerShell script to start elm-spa server from the frontend directory
# This ensures we're in the right directory and avoids path issues

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptPath

Write-Host "Starting elm-spa server from: $scriptPath" -ForegroundColor Green
Write-Host "Make sure you're using Node 22.20.0 (run 'npm run use-node' if needed)" -ForegroundColor Yellow
Write-Host ""

elm-spa server

