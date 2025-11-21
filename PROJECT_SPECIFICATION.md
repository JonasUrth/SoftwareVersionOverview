# BM Release Manager - Project Specification

## Project Overview

A web application for managing software releases across multiple customers and countries. The system tracks version history, release notes, and customer-specific information for various software types (firmware, Windows applications, etc.).

**Deployment**: Self-hosted Windows Service on local company server (custom port, e.g., 5000)  
**Network**: Company network only (no external access)  
**Authentication**: Simple username/password (admin role only)  
**Note**: Can easily pivot to IIS deployment later if needed

---

## Technology Stack

### Frontend
- **Framework**: Elm-spa
- **Language**: Elm
- **Build Tool**: elm-spa CLI

### Backend
- **Language**: C#
- **Framework**: ASP.NET Core Web API
- **ORM**: Entity Framework Core

### Database
- **System**: PostgreSQL
- **Server**: Local company server (existing)

### Deployment
- **Method**: Self-hosted Windows Service
- **Environment**: Local company Windows server (coexisting with existing IIS)
- **Port**: Custom port (e.g., 5000, 8080) - configurable
- **Hosting Model**: Kestrel web server running as Windows Service
- **Future Migration**: Can easily pivot to IIS in-process hosting if needed

---

## Database Schema

### 1. CUSTOMERS Table
| Field | Type | Constraints | Default | Notes |
|-------|------|-------------|---------|-------|
| Id | int/guid | PK, Auto | - | Primary key |
| Name | string | NOT NULL | - | Customer name |
| IsActive | boolean | NOT NULL | true | To preserve history |
| CountryId | int/guid | FK | - | References COUNTRY |

### 2. COUNTRY Table
| Field | Type | Constraints | Default | Notes |
|-------|------|-------------|---------|-------|
| Id | int/guid | PK, Auto | - | Primary key |
| Name | string | NOT NULL | - | Country name |
| FirmwareReleaseNote | text | - | - | Note to production about configuration needed before sending hardware to this country |

### 3. USERS Table
| Field | Type | Constraints | Default | Notes |
|-------|------|-------------|---------|-------|
| Id | int/guid | PK, Auto | - | Primary key |
| Name | string | NOT NULL, UNIQUE | - | Username |
| Password | string | NOT NULL | - | Plain text password (local network only) |

### 4. SOFTWARE Table
| Field | Type | Constraints | Default | Notes |
|-------|------|-------------|---------|-------|
| Id | int/guid | PK, Auto | - | Primary key |
| Name | string | NOT NULL | - | Software name |
| Type | string | NOT NULL | - | e.g., "firmware", "windows", etc. |
| RequiresCustomerValidation | boolean | NOT NULL | false | Stricter release requirements |
| FileLocation | string | - | - | Path to files (no upload/download) |
| ReleaseMethod | string | - | - | e.g., "find file", "create cd", etc. |

### 5. VERSION_HISTORY Table
| Field | Type | Constraints | Default | Notes |
|-------|------|-------------|---------|-------|
| Id | int/guid | PK, Auto | - | Primary key |
| Version | string | NOT NULL | - | Version string |
| SoftwareId | int/guid | FK, NOT NULL | - | References SOFTWARE |
| ReleaseDate | datetime | NOT NULL | - | When released |
| ReleasedById | int/guid | FK, NOT NULL | - | References USERS |
| ReleaseStatus | enum/string | NOT NULL | - | 'PreRelease', 'Released', 'ProductionReady' |
| **UNIQUE CONSTRAINT** | - | (Version, SoftwareId) | - | **Cannot have duplicate version for same software** |

### 6. HISTORY_NOTES Table
| Field | Type | Constraints | Default | Notes |
|-------|------|-------------|---------|-------|
| Id | int/guid | PK, Auto | - | Primary key |
| Note | text | NOT NULL | - | Text content (may contain bullet points) |
| VersionHistoryId | int/guid | FK, NOT NULL | - | References VERSION_HISTORY |

### 7. VERSION_HISTORY_CUSTOMERS Table (Junction)
| Field | Type | Constraints | Default | Notes |
|-------|------|-------------|---------|-------|
| Id | int/guid | PK, Auto | - | Primary key |
| VersionHistoryId | int/guid | FK, NOT NULL | - | References VERSION_HISTORY |
| CustomerId | int/guid | FK, NOT NULL | - | References CUSTOMERS |
| **UNIQUE CONSTRAINT** | - | (VersionHistoryId, CustomerId) | - | No duplicate customers per version |

### 8. HISTORY_NOTE_CUSTOMERS Table (Junction)
| Field | Type | Constraints | Default | Notes |
|-------|------|-------------|---------|-------|
| Id | int/guid | PK, Auto | - | Primary key |
| HistoryNoteId | int/guid | FK, NOT NULL | - | References HISTORY_NOTES |
| CustomerId | int/guid | FK, NOT NULL | - | References CUSTOMERS |
| **UNIQUE CONSTRAINT** | - | (HistoryNoteId, CustomerId) | - | No duplicate customers per note |

### 9. AUDIT_LOG Table
| Field | Type | Constraints | Default | Notes |
|-------|------|-------------|---------|-------|
| Id | int/guid | PK, Auto | - | Primary key |
| Timestamp | datetime | NOT NULL | NOW() | When change occurred |
| UserId | int/guid | FK | - | References USERS (who made change) |
| EntityType | string | NOT NULL | - | e.g., "VERSION_HISTORY", "CUSTOMERS" |
| EntityId | string | NOT NULL | - | ID of affected record |
| Action | string | NOT NULL | - | e.g., "CREATE", "UPDATE", "DELETE" |
| Changes | json/text | - | - | What changed (old vs new values) |

---

## Relationships Summary

```
COUNTRY (1) ←→ (many) CUSTOMERS
USERS (1) ←→ (many) VERSION_HISTORY (as ReleasedBy)
SOFTWARE (1) ←→ (many) VERSION_HISTORY
VERSION_HISTORY (1) ←→ (many) HISTORY_NOTES
VERSION_HISTORY (many) ←→ (many) CUSTOMERS (via VERSION_HISTORY_CUSTOMERS)
HISTORY_NOTES (many) ←→ (many) CUSTOMERS (via HISTORY_NOTE_CUSTOMERS)
```

---

## Core Workflows

### 1. Create New Version Release

**Steps**:
1. User selects software by name
2. User enters version number
3. System checks if version + software combination already exists
   - If exists: Show error "This version already exists for this software. Please edit the existing release."
4. If SOFTWARE.RequiresCustomerValidation = true:
   - Show warning listing customers that require validation
   - Display: "Customer 'X' and 'Y' require customer version validation. Are you sure you want to release to these customers?"
   - User must confirm to proceed
5. User selects customers (individual or bulk select via country)
6. User adds notes and assigns each note to one or more of the selected customers
7. System creates:
   - New VERSION_HISTORY record
   - New HISTORY_NOTES records
   - Links in VERSION_HISTORY_CUSTOMERS table
   - Links in HISTORY_NOTE_CUSTOMERS table
   - AUDIT_LOG entry for creation

### 2. Edit Existing Version Release

**Steps**:
1. User selects existing version from VERSION_HISTORY
2. User can:
   - Add/remove customers
   - Add/remove/edit notes
   - Change note-to-customer assignments
   - Update release status
3. System updates:
   - VERSION_HISTORY_CUSTOMERS records (add/delete as needed)
   - HISTORY_NOTE_CUSTOMERS records (add/delete as needed)
   - Creates AUDIT_LOG entry with changes

**Constraint**: Cannot change version number or software (those define uniqueness)

### 3. Bulk Customer Selection via Country

**Steps**:
1. When selecting customers for a release, user can click on a country name
2. System auto-selects all CUSTOMERS where CountryId = selected country AND IsActive = true
3. User can then deselect individual customers if needed

### 4. View Release History

**Features**:
- Filter by: software, customer, date range, status (frontend filtering)
- Display version, release date, status, released by, customers, notes
- Click to view full details including audit trail

---

## Functional Requirements

### Authentication & Authorization
- Simple login form (username/password)
- Admin role only (full CRUD access)
- Future: Public views without login (read-only)
- Session management in backend

### Validation Rules
1. Version + Software combination must be unique
2. Cannot create version without at least one customer
3. Cannot create version without at least one note
4. Each note must be assigned to at least one customer (from the selected customers for that version)
5. Warn when releasing to customers requiring validation

### Data Integrity
- Soft delete via IsActive flag for CUSTOMERS (preserve history)
- Audit trail for VERSION_HISTORY changes
- Foreign key constraints enforced at database level

### UI Considerations
- Easy bulk selection of customers by country
- Clear warning dialogs for validation-required customers
- Ability to see full audit trail when viewing/editing releases
- Display country's firmware release note when viewing customers from that country

---

## Implementation Notes

### Backend (C# + ASP.NET Core + EF Core)
1. Create PostgreSQL database with above schema
2. Use Entity Framework Core with:
   - DbContext with all entities
   - Data annotations for constraints
   - Unique index on (Version, SoftwareId) in VERSION_HISTORY
3. Create API endpoints:
   - `/api/auth/login` - POST (username/password)
   - `/api/software` - GET (list all software)
   - `/api/customers` - GET (list all active customers)
   - `/api/countries` - GET (list all countries)
   - `/api/versions` - GET, POST, PUT (CRUD for VERSION_HISTORY)
   - `/api/versions/{id}/details` - GET (full details including notes, customers, audit)
   - `/api/audit/{entityType}/{entityId}` - GET (audit trail)
4. Implement audit logging interceptor/middleware
5. Simple session-based authentication
6. **Windows Service Setup**:
   - Add `builder.Services.AddWindowsService();` in Program.cs
   - Configure Kestrel to listen on custom port (e.g., 5000)
   - Enable CORS for frontend (if serving Elm from different port/location)
   - Configure to run as Windows Service on server startup
   - Publish as self-contained or framework-dependent deployment

### Frontend (Elm + elm-spa)
1. Setup elm-spa project structure
2. Pages:
   - `/` - Home/Dashboard
   - `/login` - Login page
   - `/versions` - List all versions (with filters)
   - `/versions/new` - Create new version
   - `/versions/:id` - View/edit version details
   - `/software` - Manage software
   - `/customers` - Manage customers
   - `/countries` - Manage countries
   - `/users` - Manage users
3. Shared state for:
   - Current user session
   - Reference data (software list, customer list, country list)
4. HTTP requests to backend API
5. Form validation matching backend rules

### File Path Storage
- SOFTWARE.FileLocation stores string path only
- No file upload/download through web app
- Path used later by external Windows application for:
  - Copying install files
  - Loading firmware to testers

---

## Future Enhancements (Out of Initial Scope)
- Public read-only views without authentication
- Email notifications on new releases
- PDF export of release notes
- More granular user roles
- Advanced reporting/analytics

---

## Development Order Suggestion

1. **Database Setup**: Create PostgreSQL schema with all tables and relationships
2. **Backend Foundation**: Setup ASP.NET Core project with EF Core and basic CRUD
3. **Authentication**: Implement simple login/session management
4. **Core API**: Build VERSION_HISTORY endpoints with all validation rules
5. **Audit System**: Implement audit logging for VERSION_HISTORY changes
6. **Frontend Setup**: Initialize elm-spa project with routing
7. **Login Flow**: Build Elm login page and session management
8. **Version Management**: Build create/edit version pages with customer/note selection
9. **List Views**: Build filterable lists for versions, software, customers
10. **Testing**: Test all workflows end-to-end
11. **Deployment**: Package as Windows Service and deploy to company server on custom port

---

## Deployment Instructions

### Windows Service Deployment

1. **Publish the Application**:
   ```bash
   dotnet publish -c Release -o ./publish
   ```

2. **Copy Files to Server**:
   - Transfer published files to server directory (e.g., `C:\Services\BMReleaseManager`)

3. **Install as Windows Service**:
   ```bash
   sc create BMReleaseManager binPath="C:\Services\BMReleaseManager\BMReleaseManager.exe"
   sc config BMReleaseManager start=auto
   sc start BMReleaseManager
   ```

4. **Configure Firewall**:
   - Open Windows Firewall port for the configured port (e.g., 5000)
   - Or use PowerShell:
     ```powershell
     New-NetFirewallRule -DisplayName "BM Release Manager" -Direction Inbound -LocalPort 5000 -Protocol TCP -Action Allow
     ```

5. **Access the Application**:
   - Navigate to `http://servername:5000` from any computer on the network

### Configuration Notes

- **appsettings.json**: Configure database connection string and port
- **CORS**: Ensure frontend origin is allowed if serving from different location
- **Service Account**: Run service as appropriate Windows account with PostgreSQL access

### To Update the Service

1. Stop service: `sc stop BMReleaseManager`
2. Replace files in service directory
3. Start service: `sc start BMReleaseManager`

### Migration to IIS (If Needed Later)

1. Remove `builder.Services.AddWindowsService();` from Program.cs
2. Publish application
3. Create IIS Application Pool
4. Create IIS Website/Application pointing to published files
5. Install ASP.NET Core Hosting Bundle if not already installed

---

## Questions to Verify Before Starting

- [ ] Confirm database name and connection details for PostgreSQL server
- [ ] Confirm port number for Windows Service (e.g., 5000, 8080)
- [ ] Confirm Windows server deployment path for service files
- [ ] Verify port is available and not blocked by firewall
- [ ] Create initial admin user in USERS table? (username/password)
- [ ] Any specific UI framework preferences for styling? (CSS framework)
- [ ] Version number format validation? (e.g., semantic versioning: 1.2.3)
- [ ] Should deleted customers (IsActive=false) still show in historical releases?
- [ ] Where will Elm frontend files be hosted? (Same service, or separate?)


