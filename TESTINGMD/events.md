[← Back to TESTING.md](../TESTING.md)

# Events

App-native events (distinct from the read-only Audax calendar), reached
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

#### Route copy ("Add route to my rides")
Copying the route is voluntary — subscribing alone copies nothing.

- [ ] Subscribe to a **published event that has a route attached** (one you don't already own) → an **Add route to my rides** button appears under the route card → tap it → the confirmation names the ride with a **View** action that opens it, and the ride now appears on the **Rides** tab under your account (openable, renameable like any other).
- [ ] Tap **Add route to my rides** again → no duplicate is created (server is idempotent — the same copy comes back).
- [ ] As the event's **creator** (you already own the route) → no copy button shows.
- [ ] Leave the event → the copy you already made stays in your rides.

### Comments (public events only)
- [ ] Open a **public** event → a **Comments** section closes out the detail screen; a **private** event has no such section.
- [ ] No comments yet → "No comments yet." shows, not a blank area.
- [ ] Type a comment and send → it appears at the end of the thread immediately, the field clears, and the count in the section title goes up.
- [ ] Post from a second account (not subscribed to the event) → it works — commenting doesn't require subscribing — and both comments show oldest first, each with username and time.
- [ ] Your own comments carry a delete icon; other people's don't → delete one → confirmation dialog → it disappears and the count drops.
- [ ] An event with more than a page of comments → **Show more comments** loads the next page without duplicating any row.
- [ ] Post, then tap **Show more comments** → your fresh comment isn't duplicated when the page containing it loads.
- [ ] With no connection → the section shows an error with **Try again** instead of spinning forever, and the rest of the event detail still renders.
- [ ] Send with only whitespace → nothing is posted.

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
