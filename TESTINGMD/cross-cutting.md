[← Back to TESTING.md](../TESTING.md)

# Cross-cutting

### Bottom navigation
- [ ] The signed-in app opens on the **Rides** tab; a bottom bar shows **Rides**, **Events**, **Liked**, and **Explore**.
- [ ] Switch between tabs and back → each is exactly as it was (scroll position, sort, any in-flight upload, a picked place on Explore) — the tabs don't reset each other, except **Liked** and Explore's **browse** list, which deliberately refresh every time you switch onto them (see [rides.md](rides.md#liked-rides) / [explore.md](explore.md)).
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
