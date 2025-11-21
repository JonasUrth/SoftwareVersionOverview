# Authentication Workaround

## The Situation

- ✅ Login API works
- ✅ Backend returns user data + token
- ✅ Decoder is fixed
- ❌ Pages cannot update Shared.Model in elm-spa v1

## Immediate Options

### Option A: Skip Login for Now
Temporarily bypass login to test other features:
1. Comment out the login check in Home page
2. Test Countries CRUD (works without auth)
3. Come back to auth later

### Option B: Add localStorage with Ports (30 min)
Proper solution:
1. Add Elm ports for localStorage
2. Store token on login
3. Check token on page load
4. Full persistence

### Option C: Use URL Param Workaround (5 min)
Quick hack:
1. Pass user data in URL when navigating from login
2. Home page reads from URL
3. Not pretty but works for testing

## Recommendation

For testing the app RIGHT NOW:
- The Countries page works fine (go to `/countries`)
- You can test full CRUD without worrying about login
- We can fix auth properly with ports next

For a proper solution:
- We should add localStorage via ports
- Takes 30 minutes but works perfectly
- Standard pattern for Elm apps

What would you prefer?


