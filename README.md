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
- Sort rides (newest, name, distance)
- Rename or delete a ride
- Pull-to-refresh, infinite scroll

<!-- SCREENSHOT: rides list -->
<img width="400" alt="image" src="https://github.com/user-attachments/assets/022d1daa-d93b-42c5-a727-55118ab3ca8f" />


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
- Forecast is cached per ride for the session, so it's still there if you navigate back

<!-- SCREENSHOT: weather forecast screen -->
<img width="400" alt="image" src="https://github.com/user-attachments/assets/f5280707-8c38-4c34-bb6b-04f0edf81122" />


### Live tracking
- Turn on GPS and follow your position live against the planned route
- Shows distance traveled vs. total, and warns when you've drifted off route
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
    auth/
    rides/
    tracking/
    weather/
  main.dart
```

A file lives in `core/` if it's touched by 3+ features (or by the API client itself); otherwise it lives inside the one feature that owns it.
