# PowerShell script to use the Node version specified in .nvmrc
$nvmrcPath = Join-Path $PSScriptRoot ".nvmrc"
if (Test-Path $nvmrcPath) {
    $nodeVersion = (Get-Content $nvmrcPath).Trim()
    Write-Host "Switching to Node.js version from .nvmrc: $nodeVersion" -ForegroundColor Green
    nvm use $nodeVersion
} else {
    Write-Host ".nvmrc file not found!" -ForegroundColor Red
    exit 1
}

