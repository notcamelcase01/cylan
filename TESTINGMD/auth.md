[← Back to TESTING.md](../TESTING.md)

# Auth

### Signup
- [ ] From the landing screen, tap **Get started** → enter a new username + password → account is created and you land on **My Rides**.
- [ ] Try signing up with an already-taken username → a clear error is shown, you stay on the signup screen.
- [ ] Submit with an empty username or password → inline validation blocks it.

### Login
- [ ] From the landing screen, tap **I already have an account** → enter valid credentials → you land on **My Rides**.
- [ ] Enter a wrong password → an error message appears, you stay on the login screen.
- [ ] Toggle the password visibility (eye icon) → password text shows/hides.
- [ ] Submit with empty fields → inline validation blocks it.

### Auto-login / session
- [ ] Log in, fully close the app, reopen it → you go straight to **My Rides** without logging in again.
- [ ] While logged in, put the device in airplane mode and reopen → you stay logged in (not kicked to landing).

The rule is: a stored token is dropped **only** when the server actually
rejects it (401/403). Any other failure — offline, timeout, a 5xx — means we
couldn't check, so the rider stays logged in. Both halves need testing, since
they pull in opposite directions.

- [ ] Log in, then invalidate the token server-side (delete it in the Django admin, or plant a junk token) → reopen the app → you land on the **landing screen**, logged out cleanly.
  > This only started working once `ApiException.statusCode` was populated for
  > `{"detail": …}` bodies. Before that a rejected token was kept, and the app
  > sat on a **My Rides** where every request failed.
- [ ] Repeat the airplane-mode check above → still logged in. A connectivity failure must never log you out, or a rider offline mid-brevet gets locked out of their own saved routes.

### Profile
- [ ] Open Profile (⋮ overflow menu, top-right of My Rides → **Profile**) → your username shows.
- [ ] Set a name and email, tap **Save changes** → a "Profile saved" confirmation appears; reopen Profile to confirm it persisted.
- [ ] Enter an invalid email → validation blocks the save.
- [ ] Tap **Log out** → you return to the landing screen; reopening the app does not auto-login.
