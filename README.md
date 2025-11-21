# BM Release Manager

A web application for managing software releases across multiple customers and countries.

## 🎉 Status: Backend Complete & Running!

The ASP.NET Core Web API backend is **fully implemented and operational** on port 5000.

## Quick Start

### Backend is Already Running
```
API: http://localhost:5000
Swagger UI: http://localhost:5000/swagger
```

### Test the API
Open **http://localhost:5000/swagger** in your browser for interactive API documentation.

Or test with curl:
```bash
curl http://localhost:5000/api/software
curl http://localhost:5000/api/countries
```

### Login Credentials
- **Username:** `admin`
- **Password:** `skals`

## Project Structure

```
Backend/                    # ✅ Complete ASP.NET Core API
├── Controllers/            # 7 API controllers
├── Models/                 # 9 entity models
├── DTOs/                   # Request/response objects
├── Data/                   # DbContext + Migrations
├── README.md              # Detailed API documentation
├── QUICK_TEST.md          # Quick testing guide
└── TEST_API.ps1           # PowerShell test script

Database: BMReleaseManager  # ✅ PostgreSQL (localhost:5432)

Frontend/                   # 🔨 To be built with elm-spa
                           # (You mentioned you'll set this up)

Documentation/
├── QUICK_START.md         # Quick reference
├── IMPLEMENTATION_STATUS.md  # Complete feature list
└── PROJECT_SPECIFICATION.md  # Original requirements
```

## Features Implemented

### ✅ Database (PostgreSQL)
- All 9 tables with relationships
- Unique constraints enforced
- Foreign keys configured
- Initial admin user seeded

### ✅ API Endpoints
- **Authentication** - Session-based login/logout
- **Countries** - Full CRUD with firmware notes
- **Customers** - Full CRUD with soft delete
- **Software** - Full CRUD with validation flags
- **Users** - Full CRUD (password protected)
- **Versions** - Complex creation with validation:
  - Version+Software uniqueness check
  - Customer requirement validation
  - Note requirement validation
  - Note-customer assignment validation
  - RequiresCustomerValidation warnings
- **Audit Logs** - Complete audit trail

### ✅ Business Logic
- All validation rules from specification
- Soft delete for customers (preserves history)
- Audit logging for version changes
- Session management (8-hour timeout)
- CORS configured for elm-spa

### ✅ Deployment Ready
- Windows Service support configured
- Can run on port 5000 (customizable)
- Ready for company network deployment

## Next Steps

### 1. Test the Backend
Visit **http://localhost:5000/swagger** to test all endpoints interactively.

### 2. Build the Frontend (When Ready)
```bash
elm-spa new frontend
cd frontend
elm-spa server
```

The backend CORS is already configured for:
- `http://localhost:8000` (elm-spa default)
- `http://localhost:1234` (alternative port)

### 3. Deploy as Windows Service
```powershell
cd Backend
dotnet publish -c Release -o ./publish
sc create BMReleaseManager binPath="C:\Services\BMReleaseManager\BMReleaseManager.exe"
sc start BMReleaseManager
```

## Documentation

- **[Backend/README.md](Backend/README.md)** - Complete API documentation
- **[Backend/QUICK_TEST.md](Backend/QUICK_TEST.md)** - Quick testing guide
- **[QUICK_START.md](QUICK_START.md)** - Quick reference
- **[IMPLEMENTATION_STATUS.md](IMPLEMENTATION_STATUS.md)** - Detailed feature list
- **[PROJECT_SPECIFICATION.md](PROJECT_SPECIFICATION.md)** - Original requirements

## Technology Stack

- **Backend:** ASP.NET Core 9.0 Web API
- **Database:** PostgreSQL
- **ORM:** Entity Framework Core
- **API Docs:** Swagger/OpenAPI
- **Deployment:** Windows Service (Kestrel)
- **Frontend:** Elm-spa (to be built)

## Database Connection

```
Host: localhost
Port: 5432
Database: BMReleaseManager
Username: postgres
Password: access
```

## API Examples

### Create a Country
```bash
curl -X POST http://localhost:5000/api/countries \
  -H "Content-Type: application/json" \
  -d '{"name":"Denmark","firmwareReleaseNote":"Special config"}'
```

### Get All Software
```bash
curl http://localhost:5000/api/software
```

### Login
```bash
curl -X POST http://localhost:5000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"skals"}'
```

## Support

All backend code is complete and documented. For questions:
1. Check Swagger UI at http://localhost:5000/swagger
2. Read [Backend/README.md](Backend/README.md)
3. View [IMPLEMENTATION_STATUS.md](IMPLEMENTATION_STATUS.md)

---

**Backend Status:** ✅ Complete and Running
**Frontend Status:** 🔨 Ready to be built (you'll set up elm-spa when needed)
**Database Status:** ✅ Created and Migrated
**Deployment:** ✅ Ready for Windows Service


