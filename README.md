# Cylan

A Flutter companion app for [cyclingngin.duckdns.org](https://cyclingngin.duckdns.org) — upload rides, see them mapped with elevation and weather, and follow along live while riding.

<!-- SCREENSHOT: app icon / hero banner -->

## Features

### Auth
- Username + password login and signup
- Auto-login on app restart (session token stored securely on-device)
- Profile screen: set an optional display name/email, log out

<!-- SCREENSHOT: login screen -->
<img width="400" alt="image" src="https://github.com/user-attachments/assets/848c1324-5e86-416b-99ea-7642d7be31e8" />

<!-- SCREENSHOT: profile screen -->
<img width="400" alt="image" src="https://github.com/user-attachments/assets/5942b9dc-99e8-4481-ac98-a2dde51bae88" />


### Rides
- Upload a route from a GPX, FIT, or KML file
- Import routes from Strava
- Import a route from a Google Maps directions link (checkpoints you plotted) — **beta**, India only; the app warns that the generated route can be slightly inaccurate before you import
- Sort rides (newest, name, distance)
- Rename or delete a ride
- Search rides by name
- Pull-to-refresh, infinite scroll

<!-- SCREENSHOT: rides list -->
<img width="400" alt="image" src="https://github.com/user-attachments/assets/022d1daa-d93b-42c5-a727-55118ab3ca8f" />


### Audax events
- Browse the public Audax India brevet calendar, one month at a time (defaults to the current month)
- Step to the previous/next month, or jump straight to one via a month/year picker
- Every event is tagged with its brevet category, colour-coded on a short→long "heat" ramp (teal for a 100, through amber and red, to deep purple for a 1200) so the calendar reads at a glance
- Filter by upcoming-only, city, state, or brevet category — options are fetched live from the server, not hardcoded, so new ones (e.g. `1200`, `Fleche`) show up automatically, falling back to a neutral colour until they're given one
- City and state suggest known values as you type, but stay free-text — you can always type something that isn't on the list
- Pull-to-refresh, infinite scroll
- Tap an event to open its Audax India page, or open the route map straight from the list; organizer contact number is shown on the card
- Fetched months/filters are cached for the rest of the app session — revisiting one is instant and doesn't re-hit the network; the cache is memory-only and clears when the app closes
- No account needed for this data (public endpoint), reached from the ⋮ menu on My Rides

<!-- SCREENSHOT: audax events list -->

### Events
App-native events a rider creates and others subscribe to — distinct from the
read-only Audax calendar above. Reached via its own **Events** tab in the
bottom navigation, alongside **My Rides**.

- Browse events visible to you (your own of any status, plus everyone's public
  + published), with search, and filter chips for **Mine**, **Upcoming**, and
  status
- Create or edit an event: name, date/time, private/public visibility, a
  draft/published/cancelled/completed status, contact info (required once
  public), entry fee + currency, a subscriber cap, external links, remarks
- Attach a route the same three ways rides already come into the app — upload
  a file, import from Strava, import from Google Maps — or pick one you
  already have; nothing event-specific about any of it
- Curated route suggestions while creating an event: a 25 km radius match from
  your location, or a city picker if location isn't available; **"Use this
  route"** copies a suggestion into your own rides and attaches it on the spot
- Subscribe to a published event, optionally attaching a checklist — create a
  fresh one or reuse one from your library; a reused checklist is the same
  list everywhere it's attached, so ticking an item off shows up on every
  event using it. Once subscribed, that checklist is tickable right on the
  event
- Subscribed to an event that has a route? **"Add route to my rides"** copies
  it into your own library on demand (idempotent — no duplicates), so you can
  open, follow, or tweak it like any other
- Creator tools: edit or delete your event, see the subscriber roster
- Public events only: attach a liability-waiver PDF, uploaded straight to
  cloud storage from the device; any viewer can open it, the creator can
  replace or remove it
- Public events carry a comment thread on the detail screen — anyone who can
  see the event can read and post (subscribed or not) and delete their own
  comments anytime; flat and unthreaded, no replies or editing
- **My subscriptions** and **My checklists** screens (⋮ menu on the Events
  tab) round out the library side of this

<!-- SCREENSHOT: events list -->
<!-- SCREENSHOT: event detail -->

### Ride detail
- Route map with an elevation or gradient profile chart, linked together — tapping a point on the chart highlights it on the map
- Adjustable smoothing (50–500 m window) to trade off noise vs. detail in the elevation/gradient profile
- Distance, ascent, descent, and max grade stats
- Notable sections: the ride's climbs and descents, listed and tappable
- Share a snapshot of the ride (map + stats + chart) as an image
- Save a ride for offline use (see below)

<!-- SCREENSHOT: ride detail screen -->
<img width="400" alt="image" src="https://github.com/user-attachments/assets/3cded8b5-7886-4fb3-8768-bfab901df27c" />
<img width="400" alt="image" src="https://github.com/user-attachments/assets/13d9bbbe-48ca-4770-ab4e-a79ce71665c7" />

### Notable sections
- Each climb or descent the server detected on the route, listed under the ride with its length, gradient, and category (e.g. *very steep climb*, *technical descent*)
- Tap one to open it on its own map, zoomed to just that section with the weather that falls on it — so a steep descent in the rain stands out before you ride it
- Section detail also shows the slice's elevation/gradient chart and its stats (length, elevation change, avg/max grade, sharp turns)
- Saved offline with the ride, so sections work with no connection (route line only, no street map)

<!-- SCREENSHOT: notable sections list -->
<img width="400" alt="image" src="https://github.com/user-attachments/assets/6652d780-80f8-4c1b-b84b-483241dba936" />

<!-- SCREENSHOT: section detail (map + weather + stats) -->
<img width="400" alt="image" src="https://github.com/user-attachments/assets/ff6b00e0-fa6c-4f35-a3e6-b8b2cc7aa862" />


### Weather
- Pick a start/finish time window and fetch a forecast along the route
- Per-point temperature, feels-like, wind speed/direction, and precipitation
- Forecasts are cached per ride and persist across app restarts, so a ride keeps its weather badge on the list without refetching — a forecast is dropped once its planned window has passed, rather than lingering as stale

<!-- SCREENSHOT: weather forecast screen -->
<img width="400" alt="image" src="https://github.com/user-attachments/assets/f5280707-8c38-4c34-bb6b-04f0edf81122" />


### Live tracking
- Turn on GPS and follow your position live against the planned route; the camera auto-follows you, and panning the map drops into free-look with a **Recenter** button to jump back and re-engage auto-follow
- Shows distance from the start and a live GPS status pill (searching / locked / signal lost), with a small icon badge — not a distance readout — when you've drifted off route
- Works with only the route line (no street map) when offline

### Offline rides
- Save a route, its weather snapshot, and notable sections for use with no connection
- Offline routes show the route as a line (no street background) and weather frozen at save time; notable sections and live GPS tracking still work offline
- Manage/delete saved offline rides separately from the online list

<!-- SCREENSHOT: offline rides list -->
<img width="400" alt="image" src="https://github.com/user-attachments/assets/286bdca2-fb7c-4fb8-b982-7c863b55955e" />


### Other
- Light / dark / system theme toggle, persisted across restarts
<img width="400" alt="image" src="https://github.com/user-attachments/assets/505b8b2a-60db-4c30-8c94-a7fff57c85b8" />


## Getting started

```
flutter pub get
flutter run
```

See [TESTING.md](TESTING.md) for how the app is tested and what's still manual.

## Architecture

The app is organized feature-first under `lib/`:

```
lib/
  core/      # shared: API client, domain models, cross-feature services/widgets
  features/
    audax/
    auth/
    events/
    home/    # the bottom-nav shell (Rides / Events tabs)
    rides/
    tracking/
    weather/
  main.dart
```

A file lives in `core/` if it's touched by 3+ features (or by the API client itself); otherwise it lives inside the one feature that owns it.

The signed-in app is two tabs under `features/home/HomeShell` — **Rides**
(`RidesListScreen`, unchanged) and **Events** (`features/events/`). Each tab
keeps its own scroll position and provider state when you switch away and
back (an `IndexedStack`, not a route swap).
