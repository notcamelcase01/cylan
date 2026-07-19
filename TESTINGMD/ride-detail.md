[← Back to TESTING.md](../TESTING.md)

# Ride detail

- [ ] Open a ride → map and stats (distance, ascent, descent, max grade) render.
- [ ] Tap a point on the elevation/gradient chart → the matching point highlights on the map.
- [ ] Switch the chart between **Elevation** and **Gradient** → chart updates.
- [ ] Drag the **Smoothing** slider (50–500 m) → the profile re-smooths; the value label updates; a brief spinner shows while it applies.
- [ ] On a wide screen (tablet / landscape / unfolded foldable) → the map and stats lay out side-by-side.

### Likes
- [ ] Open a ride you haven't liked → the heart is outlined and shows the current count.
- [ ] Tap the heart → it fills immediately (optimistic) and the count goes up by one.
- [ ] Tap it again → it un-fills and the count drops back.
- [ ] Leave the ride and reopen it → the like state you left it in is still correct (reflects `is_liked` from the server, not just this session).
- [ ] Open the same ride from the **Liked Rides** tab (see [rides.md](rides.md#liked-rides)) → the like state matches what you set on the detail screen.
- [ ] With no connection, tap the heart → it reverts to its previous state rather than getting stuck filled/unfilled incorrectly.

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
