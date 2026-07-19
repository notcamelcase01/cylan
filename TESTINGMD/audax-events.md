[← Back to TESTING.md](../TESTING.md)

# Audax events

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
