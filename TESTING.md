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

### Make ride public / Public Rides tab
Curated-suggestion opt-in (`POST`/`DELETE /rides/{id}/suggest/`) — surfaces the
ride to nearby event creators once staff approve it.

- [ ] Ride card menu → **Make ride public** → a dialog shows the disclaimer ("suggested to nearby riders creating events… reviewed before going live") and an optional description field.
- [ ] Submit with no description → still succeeds; submit with one → it's saved (visible in Django admin as the ride's `description`).
- [ ] After submitting → a **Pending review** chip appears on the card in **My Rides**, and **Make ride public** no longer appears in that card's menu.
- [ ] Switch to the **Public** tab → the ride appears there with the same **Pending review** chip, without needing to pull-to-refresh.
- [ ] On the Public tab, tap a ride's ⋮ → **Remove from public suggestions** → confirmation dialog → confirm → the ride disappears from this list.
- [ ] Switch back to **My Rides** → that ride's chip is gone and **Make ride public** is available again on its menu, with no manual refresh needed.
- [ ] Approve a ride as a curated suggestion in Django admin (`public_suggestion_status → COMPLETED`) → reopen the Public tab (pull-to-refresh) → the chip reads **Public** instead of **Pending review**.
- [ ] Remove a **Public** (approved) ride from suggestions → it disappears from the Public tab, and its `visibility` reverts to Private unless it's also attached to a public event (spot-check via the ride's own detail screen / admin).
- [ ] Public tab, empty state (no rides opted in) → "No public suggestions yet" prompt shows, pointing back to the Rides tab's ⋮ menu.
- [ ] Public tab supports pull-to-refresh and infinite scroll like My Rides.

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

### Google Maps import — **manual only** (live routing + elevation lookup)
Server-side this is `POST /rides/google-maps/`, **India only**, and fully
synchronous (up to 90s) — no browser step, unlike Strava.

- [ ] **Add ride** → **Import from Google Maps** → the beta warning ("route can be slightly inaccurate") is visible before you can import.
- [ ] Paste a valid Maps directions link (a route within India, with checkpoints) + a name → **Import** → the button reads "Importing…" with an indeterminate spinner (no percentage, unlike file upload) → the ride appears in the list with the name you gave it.
- [ ] Repeat with no name entered → the ride imports using the server's default name.
- [ ] Tap **Import** with an empty link field → inline validation blocks it, no request is sent.
- [ ] Paste a link for a route **outside India** → a clear, displayable error is shown (not a raw exception), the FAB returns to **Add ride**, and no phantom ride appears in the list.
- [ ] Paste a link with no stops/checkpoints, or a non-Maps URL → a clear error is shown, no crash.
- [ ] Start an import, then kill the connection before it resolves → after the timeout, an error is shown and the FAB returns to **Add ride** — it must not spin indefinitely.
- [ ] While importing, the FAB is disabled (can't start a second import or upload concurrently).

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

## Events

App-native events (distinct from the read-only Audax calendar above), reached
via the **Events** tab in the bottom navigation. No automated coverage yet —
everything below is manual-only for now.

### List / browse
- [ ] Open the **Events** tab → events visible to you load (your own of any status, plus everyone's public + published ones).
- [ ] Type in the search box → the list narrows after a short pause (debounced), not on every keystroke.
- [ ] Toggle the **Mine** chip → only your own events show; toggle it off → the full visible list returns.
- [ ] Toggle the **Upcoming** chip → events whose start date has passed drop out.
- [ ] Tap a status chip (**Draft** / **Published** / **Cancelled** / **Completed**) → the list narrows to that status; tap it again → the filter clears.
- [ ] Pull down to refresh → the list reloads.
- [ ] Scroll a long list → more events load (infinite scroll).
- [ ] No events match the current filters → an empty state shows, not a blank screen.
- [ ] With no connection → an error state with **Try again** shows.
- [ ] Switch to the **Rides** tab and back → the Events list is still there instantly, no reload (session cache, same idea as Audax's).
- [ ] Open an event, go back → the list reflects any change you just made (subscribe, edit, delete) without a manual refresh.

### Create
- [ ] Tap **New event**, leave the name blank, fill in a start date, save → the event is created as **"MyEvent"**.
- [ ] Try to save with no start date → inline error blocks it.
- [ ] Set visibility to **Public** and try to save with no contact number → a clear error blocks it; fill in a number → it saves.
- [ ] Set visibility to **Private** → contact number is optional.
- [ ] Leave status at **Draft** → a note explains subscriptions open only once published.
- [ ] Set an entry fee and currency → the event detail shows the fee formatted with that currency; leave the fee blank/0 → it shows **Free**.
- [ ] Set a subscriber cap → the detail shows "`n` / cap subscribed"; leave it blank → shows unlimited.
- [ ] Under **More**, tap **Add an external link** → a link row appears; add a second with **Add another link**; fill both → both show on the detail screen and each opens in the browser when tapped. Tap a row's **×** → that link is removed. Add remarks → they show on the detail too.
- [ ] Type your own assembly point → it's saved and shown; leave it blank with a ride attached → the ride's start is shown instead (server-resolved).

### Attach a route — **manual only** (native file picker / OAuth / GPS)
- [ ] On the create/edit screen, tap **Attach a ride** → a sheet offers **Choose from my rides**, **Upload a file**, **Import from Strava**, **Import from Google Maps**.
- [ ] **Choose from my rides** → a paginated picker of your existing rides opens → pick one → it's attached and shown on the form.
- [ ] **Upload a file** → pick a GPX/FIT/KML → a progress dialog shows → the new ride is attached automatically once it finishes.
- [ ] **Import from Strava** → completes the existing Strava connect/import flow unchanged → afterwards you land on the "choose from my rides" picker (since Strava can import more than one) → pick the one you want attached.
- [ ] **Import from Google Maps** → same beta warning and link/name fields as the Rides tab's importer → imports and attaches in one step.
- [ ] With a ride attached, tap **Change** → the sheet reopens; tap the **×** → the ride is detached and the "Attach a ride" button reappears.

### Route suggestions — **manual only** (GPS permission)
- [ ] On the create screen, tap **Find routes near me** → grant location permission → nearby curated routes load, each showing distance from you.
- [ ] Deny/skip location permission → the panel automatically offers **Pick a city instead**; pick one → routes for that city load (no distance-from-you figure, since that's radius-only).
- [ ] On a device/simulator with **no GPS fix** (permission granted but no location set) → the panel must **not** spin forever: after ~12s it times out and falls back to the city picker with a "Couldn't get your location" note.
- [ ] No curated routes near you / in that city → a clear "no routes" message shows, not a blank panel or crash.
- [ ] Tap **Use this route** on a suggestion → it's copied into your own rides (**fork**) and attached to the event in one step; a confirmation snackbar names the ride.
- [ ] The forked ride now also appears on the **Rides** tab as an ordinary ride of yours.
- [ ] Tap **Use this route** on a suggestion you've already forked before → the server's "You already own this ride." error shows, not a crash.

### Detail view
- [ ] Open any event → status and visibility chips, date, assembly point, creator, fee, and subscriber count all render; missing optional sections (no description, no links, no ride) simply don't appear rather than showing blanks.
- [ ] Open an event **with a route attached** → the route card shows a chevron; tap it → the ride's detail screen opens (map, profile, stats), and Back returns to the event.
- [ ] Assembly point that's bare ride-derived coordinates → a **Map** link appears and opens Google Maps; a user-typed assembly point shows as plain text with no Map link.
- [ ] Public event → the **Contact** and **Waiver document** sections appear; a private event shows neither.

### Weather prompt (on date pick)
Weather is forecast *along the route*, and only ~8 days out, so the prompt is gated.
- [ ] On create/edit, attach a route, then pick a **start date within ~a week** → a **"Check the weather?"** dialog appears → **See weather** opens the forecast screen with the dates pre-filled to the event day; tap **Get forecast** → the route's forecast for that day loads.
- [ ] Pick the date **first**, then attach a route → the same prompt appears after attaching (either order works).
- [ ] Pick a date with **no route attached** → no prompt (nothing to forecast).
- [ ] Pick a date **far in the future** (e.g. 3 weeks out) with a route attached → no prompt (outside the forecast window).
- [ ] Tap **Not now** → no navigation, you stay on the form with the date set.

### Creator's own checklist
A creator can join their own event to keep a personal checklist (it counts toward the cap and shows in their own roster — expected).
- [ ] Open a **published** event you created → below **View subscribers** there's an **Add a checklist for yourself** button → tap it → the checklist picker opens (new / reuse / none) → pick one → confirmation "Checklist added to your event," and the **Your checklist** section appears with tickable items.
- [ ] The button then becomes **Remove my checklist** → tap it → your checklist detaches and the section disappears.
- [ ] Open a **draft** event you created → instead of the button, a note reads "Publish this event to add your own checklist."
- [ ] After you add your own checklist, open **View subscribers** → you appear in the roster and the count includes you.

### Edit / delete (creator only)
- [ ] Open an event you created → **Edit** and **Delete** icons appear in the app bar; open one you didn't create → neither appears.
- [ ] Edit an event that has a ride attached with no user-set assembly point → the resolved (ride-derived) value is **not** silently promoted to a saved override just from opening and re-saving the form.
- [ ] Edit and change any field → save → the detail screen reflects the change immediately.
- [ ] Delete an event → confirmation dialog → confirm → you're returned to the list and it's gone.

### Subscribe / unsubscribe
- [ ] Open a **Draft**, **Cancelled**, or **Completed** event as a non-creator → a note says subscriptions open once published, no Subscribe button.
- [ ] Open a **Published** event → tap **Subscribe** → a sheet offers **No checklist**, **Create a new one**, or reuse one from your library.
- [ ] Pick **No checklist** → you're subscribed immediately; the event shows you as subscribed and the subscriber count goes up.
- [ ] Pick **Create a new one**, name it, add a couple of items (mark one mandatory) → subscribe → it shows up under **My subscriptions** with 0/N done.
- [ ] Pick an existing checklist from your library → subscribe → the same checklist (same items, same ticked state) is now attached here too.
- [ ] Subscribe to an event that's already at its subscriber cap → the button reads **Event is full** and is disabled.
- [ ] Try subscribing to the same event twice (e.g. from two devices/sessions) → the server's "already subscribed" error surfaces cleanly.
- [ ] Once subscribed, the event detail shows a **Your checklist** section (if you attached one) with tickable items; ticking one persists (reopen to confirm) and, if it's a reused checklist, the same tick shows on **My checklists**.
- [ ] Tap **Leave event** on an event you're subscribed to → you're unsubscribed, the button reverts to **Subscribe**, and the subscriber count drops.

#### Copy-on-subscribe (route copied to your library)
Server-side behaviour on `POST /events/{id}/subscribe/` (returns `copied_ride`).

- [ ] Subscribe to a **published event that has a route attached** (one you don't already own) → the confirmation reads *"Subscribed — "`<name>`" was added to your rides."*, and that ride now appears on the **Rides** tab under your account (openable, renameable like any other).
- [ ] Subscribe to an event with **no** attached ride → plain "Subscribed." with no copy claim.
- [ ] Subscribe to your **own** event (you already own the ride) → plain "Subscribed.", no duplicate ride created.
- [ ] Leave and re-subscribe to the same event → you don't accumulate duplicate copies of the route (server is idempotent); leaving keeps the copy you already have.

### Subscribers roster (creator only)
- [ ] As the creator, tap **View subscribers** → a roster shows the count (and cap, if set) plus each subscriber's username and join date.
- [ ] As a non-creator, confirm there's no way to reach this screen.
- [ ] An event with no subscribers yet → "No one has subscribed yet," not a blank list.

### Checklist library
- [ ] Events tab → ⋮ → **My checklists** → create a new checklist by name.
- [ ] Rename a checklist, delete one (confirmation dialog) → both reflect immediately.
- [ ] Expand a checklist → add an item, tick one off, remove one → all persist (revisit the screen to confirm).
- [ ] Tick an item off here, then open **My subscriptions** or the subscribe sheet where the same checklist appears → it shows ticked there too (same row, reused by reference — not a copy).
- [ ] Delete a checklist that's attached to an existing subscription → the event/subscription screens don't crash; the checklist is simply gone from them.

### Waiver document — **manual only** (native file picker + cloud upload)
- [ ] Open a **public** event you created → a waiver-document section appears; a **private** event shows no such section.
- [ ] Tap upload, pick a PDF → a progress indicator runs → "Document uploaded" confirmation; the event card's document icon now shows on the list too.
- [ ] As any viewer (not just the creator) of a public event with a document → tap **View** → it opens in the browser via a freshly generated link.
- [ ] As the creator, **Replace** it with a different PDF → the old one is superseded.
- [ ] As the creator, **Remove** it → the section reflects "no document" and non-creator viewers no longer see a **View** option.
- [ ] Try uploading a non-PDF file, or one over the size cap → a clear error shows, no crash, no phantom "uploaded" state.

### My subscriptions
- [ ] Events tab → ⋮ → **My subscriptions** → every event you've joined is listed with its date and, if you attached one, the checklist name and done/total progress.
- [ ] Tap one → opens that event's detail screen.
- [ ] No subscriptions yet → an empty state shows.

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
- [ ] While moving above ~1 km/h → the marker shows a heading arrow; below that (including stopped) → it falls back to a plain dot.
- [ ] The distance-from-start readout in the bottom status card updates as you move.
- [ ] Move more than ~60 m off the planned route → a small warning icon appears on the status card (no distance figure shown, just the icon).

### GPS status pill
- [ ] Before the first fix arrives → the pill reads **"Acquiring GPS signal…"** (amber icon) — this must show immediately, not only after a delay, so a device with no GPS coverage at all still shows a cue.
- [ ] Once a fix arrives → the pill switches to **"GPS locked"** (green icon).
- [ ] Lose signal mid-ride (e.g. walk indoors / airplane mode) → the pill turns red with a reconnecting message, then flips back to "GPS locked" once a fix returns.

### Auto-follow / Recenter
- [ ] By default the map follows your position as fixes come in.
- [ ] Pan or pinch the map → auto-follow stops (it no longer snaps back), and a **Recenter** button appears bottom-right.
- [ ] Tap **Recenter** → the camera snaps back to your position, the button disappears, and auto-follow resumes with new fixes.
- [ ] While following, an incoming GPS fix must **not** count as "you panned" — the Recenter button should only appear after an actual touch gesture on the map.

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

### Bottom navigation
- [ ] The signed-in app opens on the **Rides** tab; a bottom bar shows **Rides**, **Events**, and **Public**.
- [ ] Switch between all three tabs and back → each is exactly as it was (scroll position, sort, any in-flight upload, loaded pages) — the tabs don't reset each other.
- [ ] Log out from any tab, log back in → you land on **Rides** again.

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
00:01 +54: All tests passed!
```

The `+54` is the number of **individual tests** that passed — not files, not
features. So `flutter test` reporting `+54` and
`flutter test test/core/api/api_client_test.dart` reporting `+14` aren't in
conflict: the second is just the 14 tests that live in that one file. Today
the 54 break down as **14 + 13 + 4 + 2 + 7 + 7 + 6 + 1** across the eight files
below.

A failure looks like `+15 -1:` (fifteen passed, one failed), prints the
expected vs. actual value, and exits non-zero — so CI catches it too. Add
`-r expanded` to list every test name as it runs instead of a single updating
line.

### `test/core/api/api_client_test.dart` — 14 tests

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
- Google Maps import: the request carries `url` and (when given) `name`, and
  omits `name` entirely rather than sending it blank; a domain error (e.g. a
  route outside India) surfaces its server message rather than throwing a raw
  type; a dropped connection resolves to an `ApiException`, not a hang.

### `test/features/rides/rides_provider_test.dart` — 13 tests

Request races on the rides list. These stage two overlapping requests and
settle them **in the wrong order on purpose** — the thing you can't do by hand.
Covers: a page-2 load landing after a pull-to-refresh must be discarded rather
than spliced onto the fresh list; two overlapping refreshes settle on the newer
answer; a superseded load doesn't clear the newer one's spinner or surface a
phantom error.

Also covers Google Maps import: a successful import prepends the new ride and
clears any prior error; a domain error (`ApiException`, e.g. route outside
India) surfaces its message without adding a phantom ride; and — since not
every failure arrives as an `ApiException` (a 2xx with an unexpected body
shape, say) — an arbitrary unanticipated exception is still caught rather
than crashing the caller or stranding its busy flag.

And "Make ride public" (`suggestPublic`/`patchSuggestionStatus`): a successful
suggest patches the ride's status in place without a refetch; a failed one
(e.g. the server's 409 "already approved") leaves the ride untouched and
surfaces the message; `patchSuggestionStatus` — the local-only sync used when
the Public Rides tab reverts a ride elsewhere — updates a loaded ride and
notifies, and is a no-op (no spurious rebuild) for a ride not currently loaded.

### `test/features/rides/suggested_rides_provider_test.dart` — 4 tests

The Public Rides tab's list. Covers: `loadFirst` asks the API for
`suggested=true`; a successful `unsuggest` removes the ride from the list; a
failed one leaves the list untouched and surfaces the error; and — same
rationale as `RidesProvider.loadFirst` — a 200 with an unexpected body shape
is caught rather than reading as "no public suggestions".

### `test/features/rides/offline_rides_provider_test.dart` — 2 tests

The same request-race idea for the offline store: a disk read that started
**before** a save must not land afterwards and erase it (that bug flipped a
just-saved ride's "Saved ✓" back to unsaved), and an invalidated refresh must
still release its spinner.

### `test/features/rides/offline_ride_store_test.dart` — 7 tests

The on-disk offline store itself (`meta.json` + saved track). Covers: a ride
lists from its metadata alone without needing to open the full GPS track;
`load()` returns the full ride for the offline map; `save()` reports back the
`savedAt` it actually wrote; and rides saved by an older app version (missing
newer metadata fields) are still listed via a fallback, get upgraded in place
the first time they're read so the slow path only runs once, and survive a
save directory that can't be read at all.

### `test/features/audax/audax_events_cache_provider_test.dart` — 7 tests

The same request-race and unexpected-failure coverage as the rides list,
applied to the per-month/filter Audax events cache: a late `fetchMore`
doesn't get appended after a refresh replaces the list, overlapping refreshes
settle on the newer one, a superseded fetch doesn't clobber the current
spinner or surface a stale error, and refreshing one cache key doesn't
invalidate an unrelated key's in-flight `fetchMore`. Plus: a non-`ApiException`
failure (from either `refresh` or `fetchMore`) still surfaces as an error
instead of a stuck spinner, and `fetchMore` failing keeps whatever was already
loaded rather than clearing it.

### `test/features/tracking/live_tracking_provider_test.dart` — 6 tests

The GPS follow-mode provider, without real location hardware. Covers: leaving
the screen while the permission prompt is still open never opens the GPS feed
afterwards; a start failure surfaces an error instead of spinning forever; a
permission refusal explains itself and stops (rather than retrying blindly);
a feed error is shown as a dismissable note rather than replacing the whole
screen; a subsequent good fix clears that note; and a fix that never arrives
says so explicitly instead of leaving the rider staring at a silent screen.

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
