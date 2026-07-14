# Testing

Testing for Cylan is **manual**. Work through the checklist below before a
release, or after touching a feature's area. Each item is a step to perform and
the result to confirm.

Use the shared test account for anything that hits the backend
(`cyclingngin.duckdns.org`). It has enough rides/data to exercise every screen.

> There is also a small automated scaffold — see [Automated (optional)](#automated-optional)
> at the bottom — but it is not the primary way this app is tested.

---

## Auth

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

### Profile
- [ ] Open Profile (person icon, top-right of My Rides) → your username shows.
- [ ] Set a name and email, tap **Save changes** → a "Profile saved" confirmation appears; reopen Profile to confirm it persisted.
- [ ] Enter an invalid email → validation blocks the save.
- [ ] Tap **Log out** → you return to the landing screen; reopening the app does not auto-login.

---

## Rides

### List
- [ ] My Rides shows your rides with name, distance, format, and date.
- [ ] Pull down to refresh → the list reloads.
- [ ] Scroll to the bottom of a long list → more rides load (infinite scroll).
- [ ] Change the sort (sort icon → newest / name / distance) → the list reorders correctly.
- [ ] Swipe a ride left → confirm the delete dialog → ride is removed.
- [ ] Ride card menu → **Rename** → new name is saved and shown.

### Upload — **manual only** (native file picker)
- [ ] Tap **Add ride** → **Upload a file** → pick a valid **GPX** → ride imports and appears in the list.
- [ ] Repeat with a **FIT** file.
- [ ] Repeat with a **KML** file.
- [ ] Pick a malformed / unsupported file → a sensible error is shown, no crash.

### Strava import — **manual only** (browser OAuth)
- [ ] **Add ride** → **Import from Strava** → complete the Strava connect flow in the browser → you return to the app.
- [ ] Imported Strava routes appear in the rides list.
- [ ] Cancel/deny the Strava auth → app handles it gracefully (no hang, clear state).

---

## Ride detail

- [ ] Open a ride → map and stats (distance, ascent, descent, max grade) render.
- [ ] Tap a point on the elevation/gradient chart → the matching point highlights on the map.
- [ ] Switch the chart between **Elevation** and **Gradient** → chart updates.
- [ ] Drag the **Smoothing** slider (50–500 m) → the profile re-smooths; the value label updates; a brief spinner shows while it applies.
- [ ] On a wide screen (tablet / landscape / unfolded foldable) → the map and stats lay out side-by-side.

### Share image — **manual only** (native share sheet)
- [ ] Tap the share icon → the share sheet opens with a generated snapshot.
- [ ] The snapshot looks correct: map, stats, current chart, and "Cylan" branding.
- [ ] Verify on **both** iOS and Android if possible.

---

## Weather

- [ ] From a ride, tap **Weather** → the forecast screen opens.
- [ ] Pick a **Start** and **Finish** date/time → tap **Get forecast** → a list of per-point forecasts loads (temp, feels-like, wind, precipitation).
- [ ] Once loaded, the route map shows temperature/wind bubbles.
- [ ] Tap the **reset/refresh** icon → the forecast clears back to the empty state.
- [ ] Go back to the ride, then reopen Weather → the previously fetched forecast is still there (session cache).
- [ ] Set the finish before the start → the app auto-corrects / handles it sensibly.

---

## Live tracking — **manual only** (GPS + permissions)

Needs real movement, or a mocked GPS feed, to exercise fully.

- [ ] Open a ride → tap **Live** → the location permission prompt appears the first time.
- [ ] **Deny** permission → the "location off" screen with **Location settings / App settings / Try again** shows.
- [ ] **Grant** permission → your position marker appears on the route.
- [ ] While moving above walking pace → the marker shows a heading arrow; while stopped → it falls back to a plain dot.
- [ ] The "distance traveled / total" readout updates as you move.
- [ ] Move more than ~60 m off the planned route → the off-route warning appears.

---

## Offline rides — **manual only** (needs no connection)

- [ ] On a ride, tap the **download / save-offline** icon → read the limitations dialog → **Save** → a determinate progress spinner runs, then the icon becomes a filled pin.
- [ ] Open **Offline rides** (icon on My Rides app bar) → the saved ride is listed with its saved date and weather snapshot.
- [ ] Turn the device fully offline (airplane mode) → open the offline ride → the route line, saved weather, and stats load with no connection.
- [ ] Start **Live** tracking on the offline ride → GPS tracking still works (route line only, no street basemap).
- [ ] Confirm offline limitations hold: no street map background, weather is frozen from save time, smoothing is fixed.
- [ ] Remove the offline copy (pin icon → **Remove**, or swipe in the offline list) → it disappears from Offline rides; the online ride is unaffected.
- [ ] Save a ride offline, then **delete the online ride** (from My Rides) while its offline copy still exists → reconnect and open the offline copy → the green **"Internet available — switch to the live view"** banner appears (connectivity detected) → tap it → since the online ride no longer exists, this should show a "ride not found" state, not crash or hang.

---

## Cross-cutting

### Theme
- [ ] Cycle the theme toggle (My Rides app bar): **Light → Dark → System** → the whole app restyles.
- [ ] Restart the app → the chosen theme persists.
- [ ] Spot-check every screen in both light and dark → no unreadable text, clipped labels, or broken contrast.

### Network / error handling
- [ ] With a poor / dropped connection, the rides list, ride detail, and weather fetch show retry/error states rather than hanging or crashing.
- [ ] Recover the connection → retry works.

### Layout
- [ ] Check on a small phone and a large tablet → no overflow or clipped content on any screen.

---

## Automated (optional)

### Widget smoke test — `test/widget_test.dart`
Boots the app headless and checks it reaches the auth gate. Fast, no network/device.

```
flutter test
```

### Integration scaffold — `integration_test/app_test.dart`
An end-to-end script driving this flow against the live API with a test account:

**logout → login → open a ride → weather → smoothing → offline map (save, open, exit)**

It's kept as a starting point, not the primary test path — manual testing
above is. Verified passing on a physical device; running on macOS desktop is
flakier (see below). Credentials come from a gitignored `test_config.json`
(shape in `test_config.example.json`) via `--dart-define-from-file`:

```
flutter test integration_test/app_test.dart \
  --dart-define-from-file=test_config.json -d <device-id>
```

Known rough edges on **macOS desktop only** (not seen on a real device): the
app window needs real focus to receive taps (run from a normal Terminal, not
a headless shell), and the default scroll-drag point can land on the route
map and pan it instead of scrolling the list. A wirelessly-tethered iOS
device needs `--publish-port`.
