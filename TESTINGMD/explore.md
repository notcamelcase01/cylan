[← Back to TESTING.md](../TESTING.md)

# Explore

The 4th bottom-nav tab (explore icon) — staff-approved curated rides,
browsable as a flat list or searched near a place you pick on a map. Every
ride here is `PUBLIC` by construction, so liking works exactly as it does
from the ride's own detail screen. No automated coverage yet.

### Browse (default)
- [ ] Open the **Explore** tab → approved rides load, newest first, each showing name, distance, like count, and (if staff wrote one) a description snippet.
- [ ] Scroll a long list → more load (infinite scroll).
- [ ] Pull down to refresh → the list reloads.
- [ ] With nothing approved yet → an empty state shows, not a blank screen.
- [ ] With no connection → an error state with **Retry** shows, not a crash.
- [ ] Switch to another tab and back → the list refreshes (a newly-approved ride shows up without needing an app restart — same fix as the Liked tab).
- [ ] Tap a ride → opens **read-only** (no smoothing control — these usually aren't yours to adjust).
- [ ] Tap the heart on a ride's detail screen → likes/unlikes it exactly like any other ride.

### Pick a place
- [ ] Tap the map icon in the app bar → a full-screen map opens with an instruction banner ("Tap anywhere to drop a pin").
- [ ] Tap anywhere on the map → a pin drops at that point and the coordinates show in the banner; **Use this place** becomes enabled.
- [ ] Tap **Use this place** → back on Explore, the browse list is replaced by a "Near `lat, lng`" banner and results within 25 km of that point (with terrain label and elevation remarks where available).
- [ ] No approved rides within 25 km of the picked point → a clear "No approved rides within 25 km." message, not a blank list.
- [ ] Tap **Clear** on the banner → back to the normal browse list.
- [ ] Back out of the map picker without tapping **Use this place** → Explore is unchanged (still whatever it was showing before).
- [ ] Pick a place, then quickly pick a different one before the first search finishes → only the second place's results ever show (no flicker back to the first, no duplicate/mixed results).
- [ ] With no connection, pick a place → an error state with **Retry** shows under the banner (the banner itself stays, so **Clear** is still reachable).
- [ ] Switch to another tab and back while in "near a place" mode → still showing that place's results, not reset to browse (unlike the browse-mode auto-refresh above).
- [ ] Tap a result → opens **read-only**, same as the browse list.
