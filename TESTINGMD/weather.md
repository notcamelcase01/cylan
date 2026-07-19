[← Back to TESTING.md](../TESTING.md)

# Weather

- [ ] From a ride, tap **Weather** → the forecast screen opens.
- [ ] Pick a **Start** and **Finish** date/time → tap **Get forecast** → a list of per-point forecasts loads (temp, feels-like, wind, precipitation).
- [ ] Once loaded, the route map shows temperature/wind bubbles.
- [ ] Tap the **reset/refresh** icon → the forecast clears back to the empty state.
- [ ] Go back to the ride, then reopen Weather → the previously fetched forecast is still there (cache).
- [ ] Set the finish before the start → the app auto-corrects / handles it sensibly.
- [ ] Once fetched, an **"Updated `<date, time>`"** line shows under the Get forecast button.

### Forecast persistence (survives app restart)
> Online forecasts are cached to disk. This is separate from **Offline rides**,
> which freeze their own weather on purpose — that behaviour is unchanged.

- [ ] Fetch a forecast for a window **in the future** → force-quit the app → reopen → the ride's weather icon/temp is still on the **My Rides** list (it no longer vanishes), and reopening Weather still shows the forecast with its original "Updated …" time.
- [ ] Fetch a forecast whose window has **already passed** (e.g. finish an hour ago) → force-quit → reopen → that ride's badge is **gone** and Weather is back to its empty state. Expired forecasts are dropped rather than shown as if current.
- [ ] Fetch for ride A, force-quit, reopen, fetch for ride B → both A and B keep their badges; they don't overwrite each other.
- [ ] Tap **reset** on a ride's forecast → force-quit → reopen → it stays cleared (the on-disk copy was deleted too, not just the in-memory one).
- [ ] Refetch a forecast for a ride that already had one → the "Updated" time advances and the new forecast survives a restart (the old file is replaced, not duplicated).
- [ ] Fetch a forecast for a ride, then **delete that ride** (swipe on My Rides) → force-quit → reopen → no orphaned forecast remains; re-uploading the same route starts with no weather.
- [ ] Delete a ride that has **both** an online forecast and an offline copy → the online forecast is dropped, but the offline copy keeps its own frozen weather and still opens from **Offline rides**.
- [ ] With no connection at launch → cached forecasts still appear from disk (no network needed to show them).
- [ ] Save a ride **offline**, then reset its online forecast → the offline copy's frozen weather is **unaffected** (the two caches are independent).
