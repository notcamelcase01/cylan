[← Back to TESTING.md](../TESTING.md)

# Rides

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
