# Simple Auth Solution (No Cookies Needed)

## The Problem

You're absolutely right - the cookies are stored for `localhost:5000` (backend), but Elm on `localhost:1234` (frontend) cannot access them. **Elm's Http module doesn't support sending cookies with cross-origin requests** (`withCredentials: true` is not available in Elm).

## The Solution

**Keep authentication in Elm's memory** - no cookies, no localStorage needed (for now):

1. User logs in
2. Backend returns success with user data
3. Elm stores user in Shared.Model
4. As long as the tab is open, user stays logged in
5. On page refresh, they'll need to login again (acceptable for MVP)

## Alternative Solutions (For Later)

### Full Persistence (Requires Ports)
- Use Elm ports to store token in localStorage
- Restore on page load
- More complex but better UX

### Same-Origin Deployment  
- Serve Elm app from the same server as API
- Backend serves static files on port 5000
- Cookies work automatically
- Best for production

## Current Implementation

For now, the login will work but won't persist across page refreshes. This is fine for testing and can be improved later with ports.


