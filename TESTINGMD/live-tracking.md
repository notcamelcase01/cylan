[← Back to TESTING.md](../TESTING.md)

# Live tracking — **manual only** (GPS + permissions)

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
