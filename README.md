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
    rides/
    tracking/
    weather/
  main.dart
```

A file lives in `core/` if it's touched by 3+ features (or by the API client itself); otherwise it lives inside the one feature that owns it.
