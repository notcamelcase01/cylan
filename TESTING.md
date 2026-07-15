# Testing

Cylan is tested at three levels. They cover different things and none replaces
another:

| Level | What it is | Command | Needs |
|---|---|---|---|
| **[Manual](#manual-checklist)** | The checklist below — the primary path. Anything involving a real map, GPS, file picker, share sheet, or your eyes on a colour. | — | A device + the test account |
| **[Automated](#automated-tests)** | Unit tests over the API layer and the providers. Covers request races and error handling that **can't** be staged by hand. | `flutter test` | Nothing — ~4s, headless |
| **[Integration](#integration-tests)** | One end-to-end script driving the real app against the live API. | `flutter test integration_test/app_test.dart …` | A device + the test account |

**Before a release:** run `flutter test` (cheap, catches regressions in logic),
then work the manual checklist for whatever you touched. The integration script
is a bonus — it's a starting point, not a gate.

Use the shared test account for anything that hits the backend
(`cyclingngin.duckdns.org`). It has enough rides/data to exercise every screen.

---

# Manual checklist

Work through this before a release, or after touching a feature's area. Each
item is a step to perform and the result to confirm.

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

#### Upload progress
Best seen with a large file (multi-MB FIT) on a throttled connection — a small
file on wifi finishes too fast to watch.

- [ ] While uploading → the **Add ride** button reads "Uploading NN%" and its ring **fills** as it goes, rather than spinning blankly.
- [ ] The percentage climbs to 100% and then the upload completes → the button returns to **Add ride** with the ring gone. It must not sit frozen at 100%.
- [ ] Upload fails midway (kill the connection) → the error snackbar shows and the button returns to **Add ride**, not stuck mid-progress.

### Strava import — **manual only** (browser OAuth)
- [ ] **Add ride** → **Import from Strava** → complete the Strava connect flow in the browser → you return to the app.
- [ ] Imported Strava routes appear in the rides list.
- [ ] Cancel/deny the Strava auth → app handles it gracefully (no hang, clear state).

---

## Audax events

Public brevet calendar (`GET /audax-events/`, no auth needed server-side) —
reached via the ⋮ overflow menu on **My Rides**.

- [ ] Open **Audax events** (⋮ menu on My Rides → **Audax events**) → the current month's events load by default.
- [ ] Tap `<` / `>` next to the month label → the previous/next month's events load.
- [ ] Tap the month/year label → a picker dialog opens → pick a different month and year → **Go** → that month's events load.
- [ ] Pick a month with more than 10 events → scroll to the bottom → the next page loads (infinite scroll); pagination is fixed at 10/page server-side.
- [ ] Pull down to refresh → the current month reloads.
- [ ] Pick a month with no events → "No audax events for `<Month Year>`" empty state shows (no crash).
- [ ] With no connection → an error state with **Retry** shows instead of hanging; reconnect and tap **Retry** → the list loads.
- [ ] Filter icon → toggle **Upcoming only** → events earlier in the month than today disappear; the filter icon fills in to show a filter is active.
- [ ] Filter icon → enter a **City** or **State** → the list narrows to matches; category chips (fetched from `GET /audax-events/filters/`, not hardcoded) → tap one → the list narrows to that distance/category only.

#### City / State suggestions
- [ ] Tap the empty **City** field → the full city list drops down; tap a suggestion → it fills the field → **Apply** → the list narrows to that city. Same for **State**.
- [ ] Type a partial name (e.g. `mum`) → suggestions narrow to matches (`Mumbai`, `Navi Mumbai`), case-insensitively.
- [ ] Type a name that **isn't** in the list (e.g. `Zzz`) → no suggestions appear but the text is still accepted → **Apply** → an empty-state ("No audax events…") shows rather than the input being blocked or reverted.
- [ ] Type a real city in a **different case** (e.g. `MUMBAI`, `mumbai`) → still returns results (server matches case-insensitively).
- [ ] Suggestions come from the same once-per-session filter fetch as the category chips — open the sheet a second time → the lists appear with no reload.
- [ ] With the filter list unavailable (kill the connection before it ever loads) → City/State show as **plain text fields with no dropdown arrow**, and typing + Apply still filters normally.
- [ ] Scroll a long suggestion list (cities) → it scrolls within its own overlay, capped in height, and doesn't push the sheet around.
- [ ] Open the sheet with the keyboard up → the suggestion overlay sits against its field and isn't hidden behind the keyboard.
- [ ] **Clear all** in the filter sheet → all filters reset and the unfiltered current month reloads.
- [ ] Changing the month or any filter always resets to page 1 — confirm there's no stale/duplicated data when switching between a filtered and unfiltered view.
- [ ] Find an event with a missing field (e.g. no club, no start point, no fee, no registration date) → it shows a placeholder ("TBA" / "Unnamed club"), not a blank or hidden row.

### Category badge
> Needs the API change exposing `category` on each event to be **deployed** —
> before that, every badge reads "TBA" in the neutral colour (the field simply
> isn't in the payload yet).

- [ ] Each event card shows a colour-coded category badge (e.g. `200 km`, `Fleche`) next to the club name; the card's tint, border, and date colour match that badge.
- [ ] Different categories are visibly different colours; two events of the same category look identical.
- [ ] The badge sits on the club-name row — confirm cards are **no taller** than before the badge existed.
- [ ] An event whose category is missing shows a `TBA` badge in the neutral brown, not a blank space or a crash.
- [ ] Category chips in the filter sheet use the same colours and labels as the card badges.
- [ ] Check the whole list in **both light and dark themes** → badge text stays readable against its pill on every colour, and the card tint never washes out the body text.
- [ ] Non-numeric categories (`Fleche`) show without a `km` suffix; numeric ones (`200`) show as `200 km`.
- [ ] Tap an event card → its Audax India event page opens in the browser.
- [ ] If an event has a route map link, tap the map icon on its card → opens the route map (e.g. RideWithGPS) in the browser.
- [ ] An event with a contact number shows it as plain text on the card (not a tappable link).
- [ ] Confirm this doesn't disturb anything else on **My Rides** — upload, Strava import, sort, offline rides, profile, and theme toggle all still work as before.

### Registration badge
Sits next to the category badge on each card. Colour is a second signal only —
the word carries the meaning, so it must read correctly in greyscale too.

- [ ] An event whose registration close date is still ahead → green **Open**.
- [ ] An event whose close date has passed → red **Closed**, and the row below it reads "Registration **closed** `<date>`" (past tense), not "closes".
- [ ] An event with no close date published → grey **TBA**.
- [ ] An event whose **ride date** has already passed → red **Closed**, even if its close date is in the future or missing. A finished brevet must never show green.
- [ ] An event closing **today** still reads **Open** (you can enter until the day is out).
- [ ] Check the list in **both light and dark themes** → the badge text stays readable against its pill.
- [ ] Cards are **no taller** than before the badge existed — it shares the club-name row.

### Month stepper
- [ ] Tap `>` five times quickly → the month label moves **immediately** with every tap (it must never lag behind your finger), but only the month you land on loads — one spinner, not five.
- [ ] Step back to a month already viewed this session → it appears instantly, no spinner, no re-fetch.
- [ ] Step to a new month and wait → it loads normally (a single tap must not feel delayed).

### Session caching
- [ ] Open a month, leave the screen (back to My Rides), reopen **Audax events** → the same month appears instantly with no loading spinner (served from the session cache, not re-fetched).
- [ ] Apply a filter combo, navigate away and back → that exact filter combo also loads instantly the second time; changing even one field (e.g. just the category) still triggers a real fetch, since it's a different cache key.
- [ ] Open the filter sheet a second time in the same session → the category chips appear immediately (no reload spinner) — the filter list itself is fetched once per session.
- [ ] Force-quit and reopen the app → the previous session's cache is gone; the first Audax events open fetches fresh from the network again.
- [ ] Pull-to-refresh on an already-cached month with no connection → a "Refresh failed: …" snackbar appears and the previously-loaded events stay on screen (not replaced with an error page).
- [ ] Turn off the connection before the filter sheet has ever loaded categories → the sheet shows "Couldn't load categories" with an inline **Retry**, while City/State/Upcoming-only remain usable.

---

## Ride detail

- [ ] Open a ride → map and stats (distance, ascent, descent, max grade) render.
- [ ] Tap a point on the elevation/gradient chart → the matching point highlights on the map.
- [ ] Switch the chart between **Elevation** and **Gradient** → chart updates.
- [ ] Drag the **Smoothing** slider (50–500 m) → the profile re-smooths; the value label updates; a brief spinner shows while it applies.
- [ ] On a wide screen (tablet / landscape / unfolded foldable) → the map and stats lay out side-by-side.

### Notable sections
- [ ] Open a ride with climbs/descents → a **Notable sections** list shows at the bottom, each row with an icon, label, distance range, and average gradient.
- [ ] Open a ride with no notable sections → the list is simply absent (no empty heading, no crash).
- [ ] Tap a section → a detail screen opens: the map is zoomed to just that section, with start/end flags and the weather bubbles that fall on it.
- [ ] The section detail shows its stats (length, elevation change, avg/max grade; sharp-turn count for technical descents) and an elevation/gradient chart of just that section.
- [ ] Tap a point on the section's chart → it highlights on the section map (same chart↔map linkage as the full ride).
- [ ] Open a section that has rain in its forecast **and** is a descent → a caution callout appears ("Rain on a descent — surfaces may be slick…").
- [ ] Go back → you return to the ride detail with the sections list intact.

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
- [ ] Go back to the ride, then reopen Weather → the previously fetched forecast is still there (cache).
- [ ] Set the finish before the start → the app auto-corrects / handles it sensibly.
- [ ] Once fetched, an **"Updated `<date, time>`"** line shows under the Get forecast button.

### Forecast persistence (survives app restart)
> Online forecasts are cached to disk. This is separate from **Offline rides**,
> which freeze their own weather on purpose — that behaviour is unchanged.

- [ ] Fetch a forecast for a window **in the future** → force-quit the app → reopen → the ride's weather icon/temp is still on the **My Rides** list (it no longer vanishes), and reopening Weather still shows the forecast with its original "Updated …" time.
- [ ] Fetch a forecast whose window has **already passed** (e.g. finish an hour ago) → force-quit → reopen → that ride's badge is **gone** and Weather is back to its empty state. Expired forecasts are dropped rather than shown as if current.
- [ ] Fetch for ride A, force-quit, reopen, fetch for ride B → both A and B keep their badges; they don't overwrite each other.
- [ ] Tap **reset** on a ride's forecast → force-quit → reopen → it stays cleared (the on-disk copy was deleted too, not just the in-memory one).
- [ ] Refetch a forecast for a ride that already had one → the "Updated" time advances and the new forecast survives a restart (the old file is replaced, not duplicated).
- [ ] Fetch a forecast for a ride, then **delete that ride** (swipe on My Rides) → force-quit → reopen → no orphaned forecast remains; re-uploading the same route starts with no weather.
- [ ] Delete a ride that has **both** an online forecast and an offline copy → the online forecast is dropped, but the offline copy keeps its own frozen weather and still opens from **Offline rides**.
- [ ] With no connection at launch → cached forecasts still appear from disk (no network needed to show them).
- [ ] Save a ride **offline**, then reset its online forecast → the offline copy's frozen weather is **unaffected** (the two caches are independent).

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
- [ ] Open **Offline rides** (⋮ menu on My Rides → **Offline rides**) → the saved ride is listed with its saved date and weather snapshot.
- [ ] Turn the device fully offline (airplane mode) → open the offline ride → the route line, saved weather, and stats load with no connection.
- [ ] While offline, the **Notable sections** list is present (if the ride had any) → tap a section → its detail opens with the section map (route line only, no street basemap) and the frozen weather on it — same UI as online.
- [ ] Start **Live** tracking on the offline ride → GPS tracking still works (route line only, no street basemap).
- [ ] Confirm offline limitations hold: no street map background, weather is frozen from save time, smoothing is fixed.
- [ ] Remove the offline copy (pin icon → **Remove**, or swipe in the offline list) → it disappears from Offline rides; the online ride is unaffected.
- [ ] Save a ride offline, then **delete the online ride** (from My Rides) while its offline copy still exists → reconnect and open the offline copy → the green **"Internet available — switch to the live view"** banner appears (connectivity detected) → tap it → since the online ride no longer exists, this should show a "ride not found" state, not crash or hang.

---

## Cross-cutting

### My Rides app bar
- [ ] The bar shows only the **title, Sort (⇅), and ⋮** — nothing else competes with "My Rides", and the title isn't squeezed on a small phone.
- [ ] ⋮ opens a labelled menu: **Audax events**, **Offline rides**, divider, **Theme: …**, **Profile** — each navigates/acts correctly and the menu closes after.
- [ ] Sort still works directly from its own icon (not buried in ⋮).
- [ ] With the rides list failed/offline, the **View offline rides** button in the error state still reaches offline rides without going through ⋮.

### Theme
- [ ] Cycle the theme (⋮ menu on My Rides → **Theme: …**): **Light → Dark → System** → the whole app restyles. The menu closes on each tap, so reopen it to cycle again; the item's label and icon reflect the current mode.
- [ ] Restart the app → the chosen theme persists.
- [ ] Spot-check every screen in both light and dark → no unreadable text, clipped labels, or broken contrast.

### Network / error handling
- [ ] With a poor / dropped connection, the rides list, ride detail, and weather fetch show retry/error states rather than hanging or crashing.
- [ ] Recover the connection → retry works.

### Layout
- [ ] Check on a small phone and a large tablet → no overflow or clipped content on any screen.

---

---

# Automated tests

Unit tests over the API layer and the providers. They exist for the things the
manual checklist genuinely **can't** reach: two overlapping network requests
resolving in the wrong order, and the exact JSON shapes the server returns on
failure. You can't hand-time a pull-to-refresh against an in-flight page load;
these do it deterministically, every run, in milliseconds.

### Running them

Everything here runs headless from the project root — no device, no network,
no test account. The whole suite takes about four seconds.

Run **all** of them:

```
flutter test
```

Run **one file**:

```
flutter test test/core/api/api_client_test.dart
```

Run **one test** by name (a substring of its description is enough):

```
flutter test --plain-name "a 401 detail body carries its status code through"
```

### Reading the output

`flutter test` prints one line that keeps overwriting itself, ending in
something like:

```
00:04 +17: All tests passed!
```

The `+17` is the number of **individual tests** that passed — not files, not
features. So `flutter test` reporting `+17` and
`flutter test test/core/api/api_client_test.dart` reporting `+10` aren't in
conflict: the second is just the 10 tests that live in that one file. Today
the 17 break down as **10 + 4 + 2 + 1** across the four files below.

A failure looks like `+15 -1:` (fifteen passed, one failed), prints the
expected vs. actual value, and exits non-zero — so CI catches it too. Add
`-r expanded` to list every test name as it runs instead of a single updating
line.

### `test/core/api/api_client_test.dart` — 10 tests

The Dio layer in `lib/core/api/api_client.dart`. Swaps Dio's transport for an
in-memory fake, so the **real** auth interceptor, timeouts, and status handling
all still run — only the network is faked.

- The auth interceptor attaches the stored token to private endpoints, and
  deliberately **doesn't** to `/audax-events/` or login. (DRF authenticates
  before checking permissions, so a stale token would turn the public calendar
  into a 401.)
- Error mapping: a `{"detail": …}` body keeps its status code (so a 401 is
  recognisable as one); field errors are collected; a dead connection produces
  a `null` status code, which is how callers tell "never reached the server"
  from "the server said no".
- URL building: relative paths join `baseUrl` correctly, query params survive,
  and absolute pagination URLs are used as-is.

### `test/features/rides/rides_provider_test.dart` — 4 tests

Request races on the rides list. These stage two overlapping requests and
settle them **in the wrong order on purpose** — the thing you can't do by hand.
Covers: a page-2 load landing after a pull-to-refresh must be discarded rather
than spliced onto the fresh list; two overlapping refreshes settle on the newer
answer; a superseded load doesn't clear the newer one's spinner or surface a
phantom error.

### `test/features/rides/offline_rides_provider_test.dart` — 2 tests

The same idea for the offline store: a disk read that started **before** a save
must not land afterwards and erase it (that bug flipped a just-saved ride's
"Saved ✓" back to unsaved), and an invalidated refresh must still release its
spinner.

### `test/widget_test.dart` — 1 test

Boots the app headless and checks it reaches the auth gate. A smoke test — it
catches "the app doesn't start at all", nothing finer.

---

# Integration tests

### `integration_test/app_test.dart`

Unlike the automated tests above, this drives the **real app against the live
API**, so it needs a device and the test account.

An end-to-end script driving this flow against the live API with a test account:

**logout → login → open a ride → weather → notable section (open, exit) → smoothing → offline map (save, open, exit)**

The notable-section and smoothing/offline steps are guarded — they run only if
the test ride actually has sections / a GPS track, so the script still passes on
a ride without them.

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
