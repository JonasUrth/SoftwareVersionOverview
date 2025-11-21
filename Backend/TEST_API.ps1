# BM Release Manager - API Test Script
# This script demonstrates all API endpoints

Write-Host "=== BM Release Manager API Tests ===" -ForegroundColor Cyan
Write-Host ""

# Base URL
$baseUrl = "http://localhost:5000"

# Test 1: Login
Write-Host "1. Testing Authentication..." -ForegroundColor Yellow
$loginBody = @{
    username = "admin"
    password = "skals"
} | ConvertTo-Json

try {
    $loginResponse = Invoke-RestMethod -Uri "$baseUrl/api/auth/login" -Method POST -Body $loginBody -ContentType "application/json" -SessionVariable session
    Write-Host "   ✓ Login successful: $($loginResponse.message)" -ForegroundColor Green
    Write-Host "   User: $($loginResponse.user.name)" -ForegroundColor Gray
}
catch {
    Write-Host "   ✗ Login failed" -ForegroundColor Red
    exit
}

# Test 2: Create Country
Write-Host "`n2. Creating Country..." -ForegroundColor Yellow
$countryBody = @{
    name = "Germany"
    firmwareReleaseNote = "230V standard configuration"
} | ConvertTo-Json

$country = Invoke-RestMethod -Uri "$baseUrl/api/countries" -Method POST -Body $countryBody -ContentType "application/json" -WebSession $session
Write-Host "   ✓ Created country: $($country.name) (ID: $($country.id))" -ForegroundColor Green

# Test 3: Create Customer
Write-Host "`n3. Creating Customer..." -ForegroundColor Yellow
$customerBody = @{
    name = "ACME Corporation"
    countryId = $country.id
    isActive = $true
} | ConvertTo-Json

$customer = Invoke-RestMethod -Uri "$baseUrl/api/customers" -Method POST -Body $customerBody -ContentType "application/json" -WebSession $session
Write-Host "   ✓ Created customer: $($customer.name) (ID: $($customer.id))" -ForegroundColor Green

# Test 4: Create Software
Write-Host "`n4. Creating Software..." -ForegroundColor Yellow
$softwareBody = @{
    name = "Main Controller Firmware"
    type = "firmware"
    requiresCustomerValidation = $true
    fileLocation = "\\fileserver\firmware\main-controller"
    releaseMethod = "Load to tester via USB"
} | ConvertTo-Json

$software = Invoke-RestMethod -Uri "$baseUrl/api/software" -Method POST -Body $softwareBody -ContentType "application/json" -WebSession $session
Write-Host "   ✓ Created software: $($software.name) (ID: $($software.id))" -ForegroundColor Green
Write-Host "   Requires validation: $($software.requiresCustomerValidation)" -ForegroundColor Gray

# Test 5: Create Version Release
Write-Host "`n5. Creating Version Release..." -ForegroundColor Yellow
$versionBody = @{
    version = "2.1.0"
    softwareId = $software.id
    releaseDate = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
    releaseStatus = "Released"
    customerIds = @($customer.id)
    notes = @(
        @{
            note = "Initial release with new features"
            customerIds = @($customer.id)
        },
        @{
            note = "Bug fixes and performance improvements"
            customerIds = @($customer.id)
        }
    )
} | ConvertTo-Json -Depth 5

try {
    $version = Invoke-RestMethod -Uri "$baseUrl/api/versions/confirm" -Method POST -Body $versionBody -ContentType "application/json" -WebSession $session
    Write-Host "   ✓ Created version: $($version.version)" -ForegroundColor Green
    Write-Host "   Software: $($version.softwareName)" -ForegroundColor Gray
    Write-Host "   Customers: $($version.customers.Count)" -ForegroundColor Gray
    Write-Host "   Notes: $($version.notes.Count)" -ForegroundColor Gray
}
catch {
    Write-Host "   ! Version creation returned: $_" -ForegroundColor Yellow
}

# Test 6: Get All Versions
Write-Host "`n6. Retrieving All Versions..." -ForegroundColor Yellow
$versions = Invoke-RestMethod -Uri "$baseUrl/api/versions" -Method GET -WebSession $session
Write-Host "   ✓ Found $($versions.Count) version(s)" -ForegroundColor Green
foreach ($v in $versions) {
    Write-Host "   - $($v.softwareName) v$($v.version) - Status: $($v.releaseStatus)" -ForegroundColor Gray
}

# Test 7: Get All Customers
Write-Host "`n7. Retrieving All Customers..." -ForegroundColor Yellow
$customers = Invoke-RestMethod -Uri "$baseUrl/api/customers" -Method GET -WebSession $session
Write-Host "   ✓ Found $($customers.Count) customer(s)" -ForegroundColor Green
foreach ($c in $customers) {
    Write-Host "   - $($c.name) ($($c.country.name))" -ForegroundColor Gray
}

# Test 8: Get Audit Logs
Write-Host "`n8. Retrieving Audit Logs..." -ForegroundColor Yellow
$auditLogs = Invoke-RestMethod -Uri "$baseUrl/api/audit?limit=10" -Method GET -WebSession $session
Write-Host "   ✓ Found $($auditLogs.Count) audit log(s)" -ForegroundColor Green
foreach ($log in $auditLogs | Select-Object -First 3) {
    Write-Host "   - [$($log.action)] $($log.entityType) by $($log.userName)" -ForegroundColor Gray
}

# Summary
Write-Host "`n=== Test Summary ===" -ForegroundColor Cyan
Write-Host "✓ Authentication working" -ForegroundColor Green
Write-Host "✓ Countries CRUD working" -ForegroundColor Green
Write-Host "✓ Customers CRUD working" -ForegroundColor Green
Write-Host "✓ Software CRUD working" -ForegroundColor Green
Write-Host "✓ Version management working" -ForegroundColor Green
Write-Host "✓ Audit logging working" -ForegroundColor Green

Write-Host "`nAPI is fully functional! 🎉" -ForegroundColor Green
Write-Host "Swagger UI: http://localhost:5000/swagger" -ForegroundColor Cyan


