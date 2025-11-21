# Fix: Login Session Not Persisting

## The Problem

The backend successfully creates a session, but the Elm frontend doesn't receive the cookie because of CORS restrictions when going from `localhost:1234` (frontend) → `localhost:5000` (backend).

## The Solution

I've updated both backend and frontend to properly handle cross-origin cookies.

### Changes Made

✅ **Backend** (`Backend/Program.cs`)
- Added `SameSite = SameSiteMode.None` to session cookie
- Added `SecurePolicy = CookieSecurePolicy.None` for localhost testing

✅ **Frontend** (`frontend/src/Api/Auth.elm`)
- Changed from `Http.post`/`Http.get` to `Http.request` (needed for credentials)

## Steps to Apply the Fix

### 1. Stop the Backend
Press `Ctrl+C` in the terminal running the backend

### 2. Restart the Backend
```powershell
cd Backend
dotnet run
```

### 3. Rebuild the Frontend
```powershell
cd frontend
elm-spa build
```

The elm-spa server should auto-reload, but if not:
```powershell
# Stop with Ctrl+C, then restart
elm-spa server
```

### 4. Test Again
1. Open http://localhost:1234
2. Click "Login"
3. Enter:
   - Username: `admin`
   - Password: `skals`
4. **Should now redirect to dashboard and stay logged in!**

## Why This Happened

When a browser makes a request from one origin (localhost:1234) to another (localhost:5000), cookies are NOT sent by default for security. This is called "cross-origin requests" or CORS.

To send cookies cross-origin, we need:
1. **Backend**: Set cookie `SameSite=None` 
2. **Backend**: CORS must include `.AllowCredentials()` ✅ (we already had this)
3. **Frontend**: HTTP requests must include credentials (not supported by simple Http.post)

## For Production

When deploying on the same domain (e.g., `company.com:5000`), you would:
- Remove `SameSite = SameSiteMode.None`
- Change to `SecurePolicy = CookieSecurePolicy.Always`
- Use HTTPS

But for localhost development, the current settings work fine.

## Verification

After restarting the backend, you should see in your browser DevTools:
1. Network tab → `/api/auth/login` request
2. Response Headers should include: `Set-Cookie: .BMReleaseManager.Session=...`
3. Subsequent requests should include: `Cookie: .BMReleaseManager.Session=...`


