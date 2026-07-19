[← Back to TESTING.md](../TESTING.md)

# Rides

### List
- [ ] My Rides shows your rides with name, distance, format, and date.
- [ ] Pull down to refresh → the list reloads.
- [ ] Scroll to the bottom of a long list → more rides load (infinite scroll).
- [ ] Change the sort (sort icon → newest / name / distance) → the list reorders correctly.
- [ ] Swipe a **private** ride left → confirm the delete dialog → ride is removed.
- [ ] Swipe a **public** ride left (attached to a public event) → an explanatory dialog blocks it ("Can't delete a public ride…"), no confirm/delete dialog appears, and the card stays in the list.
- [ ] Force the rare race (make the ride public from another device/session right after this one loaded the list, then swipe) → the server's `400` still comes back; the card snaps back into place and a snackbar shows "Only private rides can be deleted." — it must not vanish silently.
- [ ] After any failed delete → the ride's cached weather forecast is untouched (only a *confirmed* delete clears it).
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

### Liked Rides
The 3rd bottom-nav tab (heart icon) — rides you've liked, whether or not you
own them. No automated coverage yet.

- [ ] Like a ride you own, and a ride you don't (e.g. from an event's route) → both appear on the **Liked** tab.
- [ ] Unlike one from its own detail screen → it drops off the **Liked** tab (pull to refresh if it doesn't reload on its own — the tab doesn't auto-refresh on switch, same as **Rides**).
- [ ] With nothing liked yet → an empty state shows ("No liked rides yet"), not a blank screen.
- [ ] Scroll a long liked-rides list → more load (infinite scroll), same as **My Rides**.
- [ ] Pull down to refresh → the list reloads.
- [ ] Tap a liked ride you **don't** own (e.g. someone else's public route) → it opens **read-only** (no smoothing control — it would 404 for a ride that isn't yours).
- [ ] Tap a liked ride you **do** own → it still opens read-only from this tab (by design — go to **My Rides** to adjust smoothing on your own rides).
- [ ] With no connection → an error state with **Try again** shows, not a crash.
