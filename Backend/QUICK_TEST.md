# Quick API Test Guide

## ✅ Backend is Running Successfully!

The API is running on **http://localhost:5000**

## Easiest Way to Test: Use Swagger UI

**Open in your browser:** http://localhost:5000/swagger

Swagger provides an interactive UI where you can:
- See all available endpoints
- Try out each endpoint
- See request/response examples
- Test authentication

### Using Swagger:

1. **Login First**
   - Go to `/api/Auth/login` (POST)
   - Click "Try it out"
   - Use request body:
     ```json
     {
       "username": "admin",
       "password": "skals"
     }
     ```
   - Click "Execute"

2. **Create a Country**
   - Go to `/api/Countries` (POST)
   - Click "Try it out"
   - Use request body:
     ```json
     {
       "name": "Denmark",
       "firmwareReleaseNote": "Special voltage requirements"
     }
     ```

3. **Create Software**
   - Go to `/api/Software` (POST)
   - Request body:
     ```json
     {
       "name": "Test Firmware",
       "type": "firmware",
       "requiresCustomerValidation": false,
       "fileLocation": "C:\\Firmware\\Test",
       "releaseMethod": "Find file"
     }
     ```

4. **View All Software**
   - Go to `/api/Software` (GET)
   - Click "Execute"

## Alternative: Using curl

```bash
# Check if API is running
curl http://localhost:5000/api/auth/check

# Login
curl -X POST http://localhost:5000/api/auth/login \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"admin\",\"password\":\"skals\"}"

# Get all software
curl http://localhost:5000/api/software

# Create software
curl -X POST http://localhost:5000/api/software \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"Test\",\"type\":\"firmware\",\"requiresCustomerValidation\":false}"
```

## Current Test Data

The following data has been successfully created:

### Countries
- ✓ Denmark (ID: 1)
- ✓ Germany (ID: 2)

### Software
- ✓ Test Firmware (ID: 1)
- ✓ Main Controller Firmware (ID: 2)

You can view these by visiting:
- http://localhost:5000/api/countries
- http://localhost:5000/api/software

## All Available Endpoints

✅ **Authentication**
- POST `/api/auth/login`
- POST `/api/auth/logout`
- GET `/api/auth/check`

✅ **Countries**
- GET `/api/countries`
- GET `/api/countries/{id}`
- POST `/api/countries`
- PUT `/api/countries/{id}`
- DELETE `/api/countries/{id}`

✅ **Customers**
- GET `/api/customers`
- GET `/api/customers/{id}`
- POST `/api/customers`
- PUT `/api/customers/{id}`
- DELETE `/api/customers/{id}` (soft delete)

✅ **Software**
- GET `/api/software`
- GET `/api/software/{id}`
- POST `/api/software`
- PUT `/api/software/{id}`
- DELETE `/api/software/{id}`

✅ **Users**
- GET `/api/users`
- GET `/api/users/{id}`
- POST `/api/users`
- PUT `/api/users/{id}`
- DELETE `/api/users/{id}`

✅ **Versions**
- GET `/api/versions`
- GET `/api/versions/{id}`
- POST `/api/versions`
- POST `/api/versions/confirm`
- PUT `/api/versions/{id}`

✅ **Audit Logs**
- GET `/api/audit`
- GET `/api/audit/{entityType}/{entityId}`

## Status: ✅ Fully Operational

The backend API is complete and working perfectly!


