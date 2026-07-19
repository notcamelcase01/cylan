[← Back to TESTING.md](../TESTING.md)

# Offline rides — **manual only** (needs no connection)

- [ ] On a ride, tap the **download / save-offline** icon → read the limitations dialog → **Save** → a determinate progress spinner runs, then the icon becomes a filled pin.
- [ ] Open **Offline rides** (⋮ menu on My Rides → **Offline rides**) → the saved ride is listed with its saved date and weather snapshot.
- [ ] Turn the device fully offline (airplane mode) → open the offline ride → the route line, saved weather, and stats load with no connection.
- [ ] While offline, the **Notable sections** list is present (if the ride had any) → tap a section → its detail opens with the section map (route line only, no street basemap) and the frozen weather on it — same UI as online.
- [ ] Start **Live** tracking on the offline ride → GPS tracking still works (route line only, no street basemap).
- [ ] Confirm offline limitations hold: no street map background, weather is frozen from save time, smoothing is fixed.
- [ ] Remove the offline copy (pin icon → **Remove**, or swipe in the offline list) → it disappears from Offline rides; the online ride is unaffected.
- [ ] Save a ride offline, then **delete the online ride** (from My Rides) while its offline copy still exists → reconnect and open the offline copy → the green **"Internet available — switch to the live view"** banner appears (connectivity detected) → tap it → since the online ride no longer exists, this should show a "ride not found" state, not crash or hang.
