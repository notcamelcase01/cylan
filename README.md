# Cylan

A Flutter companion app for [cyclingngin.duckdns.org](https://cyclingngin.duckdns.org) — upload rides, see them mapped with elevation and weather, and follow along live while riding.

<!-- SCREENSHOT: app icon / hero banner -->

## Features

### Auth
- Username + password login and signup
- Auto-login on app restart (session token stored securely on-device)
- Profile screen: set an optional display name/email, log out

<!-- SCREENSHOT: login screen -->
<!-- SCREENSHOT: profile screen -->

### Rides
- Upload a route from a GPX, FIT, or KML file
- Import routes from Strava
- Sort rides (newest, name, distance)
- Rename or delete a ride
- Pull-to-refresh, infinite scroll

<!-- SCREENSHOT: rides list -->

### Ride detail
- Route map with an elevation or gradient profile chart, linked together — tapping a point on the chart highlights it on the map
- Adjustable smoothing (50–500 m window) to trade off noise vs. detail in the elevation/gradient profile
- Distance, ascent, descent, and max grade stats
- Share a snapshot of the ride (map + stats + chart) as an image
- Save a ride for offline use (see below)

<!-- SCREENSHOT: ride detail screen -->

### Weather
- Pick a start/finish time window and fetch a forecast along the route
- Per-point temperature, feels-like, wind speed/direction, and precipitation
- Forecast is cached per ride for the session, so it's still there if you navigate back

<!-- SCREENSHOT: weather forecast screen -->

### Live tracking
- Turn on GPS and follow your position live against the planned route
- Shows distance traveled vs. total, and warns when you've drifted off route
- Works with only the route line (no street map) when offline

<!-- SCREENSHOT: live tracking screen -->

### Offline rides
- Save a route, its weather snapshot, and map tiles for use with no connection
- Offline routes show the route as a line (no street background) and weather frozen at save time; live GPS tracking still works offline
- Manage/delete saved offline rides separately from the online list

<!-- SCREENSHOT: offline rides list -->

### Other
- Light / dark / system theme toggle, persisted across restarts

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
