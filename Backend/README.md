# BM Release Manager - Backend API

## Overview
ASP.NET Core Web API for managing software releases across customers and countries.

## Prerequisites
- .NET 9.0 SDK
- PostgreSQL database
- Connection string configured in `appsettings.json`

## Database Setup

### Initial Setup
The database has been created and migrated:
```powershell
# Database: BMReleaseManager
# User: postgres
# Password: access
# Port: 5432
```

### Admin User
- Username: `admin`
- Password: `skals`

## Running the Application

### Development
```powershell
cd Backend
dotnet run
```

The API will be available at: `http://localhost:5000`

### Swagger UI
Access the API documentation at: `http://localhost:5000/swagger`

## API Endpoints

### Authentication
- `POST /api/auth/login` - Login with username/password
- `POST /api/auth/logout` - Logout
- `GET /api/auth/check` - Check current session

### Core Entities
- `GET /api/software` - Get all software
- `POST /api/software` - Create software
- `PUT /api/software/{id}` - Update software
- `DELETE /api/software/{id}` - Delete software

- `GET /api/countries` - Get all countries
- `POST /api/countries` - Create country
- `PUT /api/countries/{id}` - Update country
- `DELETE /api/countries/{id}` - Delete country

- `GET /api/customers` - Get all customers (query: `?activeOnly=true`)
- `POST /api/customers` - Create customer
- `PUT /api/customers/{id}` - Update customer
- `DELETE /api/customers/{id}` - Soft delete customer

- `GET /api/users` - Get all users
- `POST /api/users` - Create user
- `PUT /api/users/{id}` - Update user
- `DELETE /api/users/{id}` - Delete user

### Version Management
- `GET /api/versions` - Get all versions
- `GET /api/versions/{id}` - Get version details with notes and customers
- `POST /api/versions` - Create new version (may return validation warning)
- `POST /api/versions/confirm` - Create version (bypass validation warning)
- `PUT /api/versions/{id}` - Update version

### Audit Logs
- `GET /api/audit` - Get recent audit logs (query: `?limit=100`)
- `GET /api/audit/{entityType}/{entityId}` - Get audit trail for specific entity

## Testing the API

### Test Login
```powershell
$body = @{
    username = "admin"
    password = "skals"
} | ConvertTo-Json

Invoke-RestMethod -Uri "http://localhost:5000/api/auth/login" `
    -Method POST `
    -Body $body `
    -ContentType "application/json" `
    -SessionVariable session
```

### Test Getting Software
```powershell
Invoke-RestMethod -Uri "http://localhost:5000/api/software" -Method GET
```

### Test Creating Software
```powershell
$body = @{
    name = "Test Firmware"
    type = "firmware"
    requiresCustomerValidation = $true
    fileLocation = "C:\Firmware\Test"
    releaseMethod = "Find file"
} | ConvertTo-Json

Invoke-RestMethod -Uri "http://localhost:5000/api/software" `
    -Method POST `
    -Body $body `
    -ContentType "application/json"
```

## Windows Service Deployment

### Build for Production
```powershell
dotnet publish -c Release -o ./publish
```

### Install as Windows Service
```powershell
sc create BMReleaseManager binPath="C:\Services\BMReleaseManager\BMReleaseManager.exe"
sc config BMReleaseManager start=auto
sc start BMReleaseManager
```

### Firewall Configuration
```powershell
New-NetFirewallRule -DisplayName "BM Release Manager" `
    -Direction Inbound `
    -LocalPort 5000 `
    -Protocol TCP `
    -Action Allow
```

## Configuration

### Connection String
Edit `appsettings.json` to configure database connection:
```json
{
  "ConnectionStrings": {
    "DefaultConnection": "Host=localhost;Port=5432;Database=BMReleaseManager;Username=postgres;Password=access"
  }
}
```

### Port Configuration
The server listens on port 5000 by default. This can be changed in `appsettings.json`:
```json
{
  "Kestrel": {
    "Endpoints": {
      "Http": {
        "Url": "http://*:5000"
      }
    }
  }
}
```

### CORS Configuration
The API allows requests from:
- `http://localhost:8000` (elm-spa server default)
- `http://localhost:1234` (alternative dev port)

To add more origins, edit `Program.cs`:
```csharp
policy.WithOrigins("http://localhost:8000", "http://localhost:1234", "http://your-url")
```

## Features Implemented

✅ Entity Framework Core with PostgreSQL
✅ All database entities and relationships
✅ Unique constraints on Version+Software
✅ Session-based authentication
✅ Complete CRUD for all entities
✅ Version management with validation:
  - Check for duplicate version+software
  - Require at least one customer
  - Require at least one note
  - Validate note-customer assignments
  - Warning for RequiresCustomerValidation
✅ Audit logging for VERSION_HISTORY
✅ Soft delete for customers
✅ Windows Service support
✅ CORS configuration for frontend
✅ Swagger/OpenAPI documentation

## Troubleshooting

### Connection Refused
- Ensure PostgreSQL is running
- Check connection string in `appsettings.json`
- Verify firewall allows port 5432

### Port Already in Use
- Change port in `appsettings.json`
- Or stop other application using port 5000

### CORS Errors
- Add your frontend URL to CORS policy in `Program.cs`
- Ensure `AllowCredentials()` is set for session support


