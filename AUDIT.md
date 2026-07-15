# Audit: leaks, stuck spinners, crashes, caching

A read-through of `lib/` (45 files) looking for four things specifically: memory
leaks, API failures that strand the UI on a spinner, crashes, and caching bugs.

**Read this first.** Nothing here was found by using the app — `flutter analyze`
is clean and the test suite passes. Every item below is *latent*: it needs a
condition a developer on their own phone, on their own network, basically never
enters. That is the point of a static read (it finds the tail), and also its
limit (the tail is the tail). Each entry therefore carries an honest
**Likelihood** as well as a consequence. Treat the tiers, not the count, as the
takeaway: **one item was worth dropping everything for, three were worth an
afternoon, and most of the rest are "fix it when you're already in that file."**

Line numbers are as of the fixes below.

---

## Status at a glance

| | Item | State |
|---|---|---|
| F1 | Keystore brick at splash | ✅ fixed |
| F2 | ThemeProvider throw on launch | ✅ fixed |
| F3 | Stuck "Uploading…" FAB | ✅ fixed |
| F4 | GPS leak + live spinner | ✅ fixed |
| O1 | Unexpected errors stranding the UI | ✅ fixed (mitigation) — full decode refactor still deferred |
| O2 | Audax cache race guard | ✅ fixed + tested |
| O3 | Offline rides pinning GPS tracks in RAM | ✅ fixed + tested |
| O19 | Live GPS feed: no `onError`, silent missing fix | ✅ fixed + tested |
| O4–O18 | Small / noted | ⬜ open |

Test suite: **17 → 37**. `flutter analyze` clean.

---

## Fixed

### F1. A failing keystore bricked the app at the splash — unrecoverable ✅

`ApiClient.token` read secure storage unguarded, and
`AuthProvider.tryAutoLogin` called it via `isLoggedIn` **outside** its `try`. A
throw meant `status` was never assigned, so it stayed `AuthStatus.unknown` —
which `AuthGate` renders as a bare `CircularProgressIndicator`. No retry, no
error, no timeout.

- **Trigger:** an Android keystore that can no longer decrypt its entries
  (classic after restore-from-backup onto a new device); iOS keychain refusing
  access before first unlock.
- **Likelihood:** low per user, but **once per affected install, forever**.
- **Why it mattered anyway:** it is invisible to you and unreportable by them.
  The user sees a spinner, has nothing to describe, and uninstalls. You would
  never learn it happened. That shape — rare, fatal, silent — is what earned it
  the fix despite the low odds.
- **Fix:** every access to secure storage is now best-effort, at the source
  (`ApiClient.token`, `_storeToken`, `logout`), which also covers the auth
  interceptor that reads the token on every request. A token that can't be read
  is treated as no token: you land on the landing screen and can sign in again,
  which writes a fresh one.
- **Verified:** with a keystore stubbed to throw `BadPaddingException`, the app
  now reaches the landing screen instead of spinning for the five minutes of
  pumped time I gave it.
- **Caveat:** a `logout()` whose `delete` throws now swallows it, so a
  sufficiently broken keystore could still hold the old entry on disk. It can't
  be *presented* (the same storage fails the read, and `token` answers null),
  but it isn't scrubbed either. See O16.

### F2. `ThemeProvider` threw on every launch on the same devices

Same unguarded read, in a constructor-initiated `_load()`. I initially waved
this off as "degrades harmlessly to system theme" — it does *visually*, but it
threw an unhandled async exception on every launch, which a real crash reporter
would surface as noise. Found only because the F1 verification test caught it.
Both `_load()` and `cycle()` are now best-effort.

### F3. "Add ride" could stick on "Uploading…" until an app restart

`RidesProvider.upload` caught only `ApiException`, but `MultipartFile.fromFile`
throws `FileSystemException` when the picked file is gone by the time it's read.
That escaped, so the caller's `setState(() => _uploading = false)` was never
reached — and the FAB is `onPressed: _uploading ? null : ...`, so it was
**permanently disabled**. `error` was null too, so nothing was shown.

- **Trigger:** Android evicting the file picker's cache copy between pick and
  upload; a file on removed storage.
- **Likelihood:** low — the window is seconds.
- **Consequence:** the app's primary feature is dead until restart.
- **Fix:** `upload` now honours its documented contract (return null, set
  `error`) for *any* failure, and the screen wraps the flag in `try/finally` so
  it cannot strand regardless of what the provider does later.
- **Verified:** `upload()` now returns null with
  `error = "Could not read that file. Please pick it again."`

### F4. Live tracking leaked the GPS stream, and could spin forever

Two holes in `LiveTrackingProvider.start()`:

1. It awaited `ensureReady()` — which blocks on the OS permission prompt — and
   *then* subscribed. Pop the screen while that prompt is open and `dispose()`
   runs with `_positionSub == null`, cancelling nothing; `start()` then resumes
   and opens a high-accuracy position stream **nobody will ever cancel**. GPS
   runs until the process dies.
2. A non-`LocationPermissionDenied` throw from `ensureReady()` (a geolocator
   `PlatformException`) escaped entirely, leaving `isLoading` pinned true — an
   infinite spinner on the one screen you're using mid-ride.

- **Likelihood:** narrower than it first looks. After permission is granted once,
  `ensureReady()` returns in milliseconds and the race window nearly closes. This
  is essentially a first-run bug.
- **Fix:** a `_disposed` flag guards both the subscribe and the notifies, and the
  bare `catch` now surfaces a real error instead of spinning.

---

## Addressed since the first draft

### O1. `ApiClient` doesn't keep its own contract on decode — ✅ mitigated

> **Status:** the *stuck-UI symptom* is fixed; the underlying decode contract is
> deliberately left as-is. See "What was done" at the end of this entry.
>
> **Downgraded twice, read this before acting on the rest.** This started life as
> the top finding. Two of the three triggers I claimed for it turned out not to
> exist — see the corrections inline. The mechanism is real and proven; the odds
> of it firing are very low. That's why the cheap mitigation was the right call
> and the 20-endpoint refactor was not.

The class doc says everything above it "deals in models and `ApiException`".
That holds for transport failures (`_send`) and non-2xx bodies (`_ensure`) — but
**not** for a 200 whose body isn't the shape the endpoint expected. Then
`Model.fromJson(response.data as Map<String, dynamic>)` throws a raw `TypeError`
that slips past every `on ApiException catch` in the app. Confirmed against the
real client:

```
listAudaxEvents, 200 + HTML body  →  _TypeError: 'String' is not a subtype of 'Map<String, dynamic>'
listAudaxEvents, 200 + JSON list  →  _TypeError: 'List<dynamic>' is not a subtype of 'Map<String, dynamic>'
```

**Correction 1 — not a captive-portal bug.** Originally sold as one. Wrong:
`baseUrl` is `https://`, so a portal can't hand you a 200 HTML page without
breaking the TLS handshake — you get a cert or connection error, which
`_asApiException` already maps correctly. **The app already handles captive
portals.**

**Correction 2 — not a scraped-data bug either.** The fallback trigger was "the
audax scraper emits a surprise null and the whole month fails to decode". It
can't. `AudaxEvent.brevet_date` *is* nullable on the model
(`audax_events/models.py:78`) and `event_date = DateTimeField(source="brevet_date")`
has no `allow_null`, so a null *would* serialize to `"event_date": null` and blow
up `DateTime.parse(json['event_date'] as String)` — killing the whole page, not
one row. But `api/views.py:get_queryset` already forbids it:

```python
brevet_date__isnull=False,        # event_date is guaranteed non-null
brevet_date__year=data["year"],   # (would exclude nulls anyway)
...
.exclude(audax_id__isnull=True)   # audax_id is guaranteed non-null
.exclude(audax_id="")
```

Both fields the Flutter model calls "guaranteed non-null" are *enforced*
server-side, and every remaining nullable field maps to a nullable Dart type
(`event_fee`→`numOrNull`, `category`/`club`→`String?`,
`registration_close_date`→`dateOrNull`). The app/API contract is sound.

**What's actually left:** you change the API and forget to update the app. Then
you get a spinner instead of an error message — a diagnosability cost to *you*
during a migration, not users suffering. Nothing else realistic remains. Also
note an nginx/proxy error page carries its real status (502/504), which `_ensure`
already turns into `ApiException('Unexpected server error (502).')` — handled.

Consequences, given the trigger:

- **`AudaxEventsCacheProvider.fetchFirst`** (`:111`) leaves `_events[key]` null,
  `_firstErrors[key]` null and `_loadingFirst[key]` false — which lands on
  `audax_events_screen.dart:279`, the branch commented "a brief transitional
  state". It isn't transitional here, it's terminal, and there's no
  `RefreshIndicator` or Retry in that branch to escape with. **Spinner forever.**
- **`RidesProvider.loadFirst`** (`:78`) leaves `error` null and the list empty,
  so the screen renders **"No rides yet"** to someone who has plenty — which
  reads as data loss.

**Fix (deliberate, ~20 endpoints, own PR):** put it back where the contract
lives. Add one helper and route each decode through it:

```dart
/// Converts a body that isn't the shape this endpoint expects into an
/// ApiException. Without this a decode failure escapes as a raw TypeError and
/// slips past every `on ApiException catch` above.
T _decode<T>(T Function() decode) {
  try {
    return decode();
  } on ApiException {
    rethrow;
  } catch (_) {
    throw ApiException('The server sent a response the app could not read.');
  }
}
```

then `return _decode(() => Ride.fromJson(response.data as Map<String, dynamic>));`
at each call site. Mechanical and low-risk, and the existing
`api_client_test.dart` gives you a net. Add a case per body shape (string, list,
missing key) while you're there.

**What was done (mitigation, not the refactor).** Given how low the odds are,
the `_decode` refactor was not worth scheduling. But the *stuck* symptom was
worth killing on its own merits, because it costs nothing and covers causes
neither of us predicted.

**Correction to my own recommendation:** the first draft said to fix
`audax_events_screen.dart:279` (the `if (events == null)` branch) in the UI.
That was wrong — that branch is *legitimately* reachable on the first frame,
before the post-frame fetch starts, so putting a Retry there would flash it on
every normal screen open. The fix belongs in the provider, where "loaded
nothing, with no error" is genuinely impossible to reach except on failure. So
instead:

- `AudaxEventsCacheProvider.fetchFirst`/`fetchMore`/`fetchFilters` each grew a
  bare `catch (_)` that records a user-facing error, reusing the error+Retry UI
  the screen already had for `ApiException`. A `TypeError` now surfaces as
  "Couldn't load these events" with a Retry, not a dead-end spinner.
- `RidesProvider.loadFirst`/`loadMore` got the same, so an unexpected failure
  shows "Couldn't load your rides" instead of the **"No rides yet"** empty state
  that read as data loss.

Pinned by `test/features/audax/audax_events_cache_provider_test.dart` ("a
non-ApiException surfaces as an error, not a stuck spinner"). The `_decode`
refactor above remains the *correct* fix if you're ever already in `ApiClient` —
this just makes the failure recoverable in the meantime.

### O2. The audax cache is missing the race guard the rides cache has — ✅ fixed

The most interesting finding. `RidesProvider` carries a `_generation` counter
with a ten-line comment explaining that a `loadMore` landing after a `refresh`
"splices page 2 of the old list onto the freshly refreshed page 1, duplicating
or dropping rides", and four tests pinning the behaviour.

`AudaxEventsCacheProvider` — same shape, same screen pattern, same
scroll-triggered `fetchMore` plus pull-to-refresh — **has no guard at all**:

- `fetchFirst` sets `_events[key] = page.results` (`:108`) and
  `_nextUrls[key] = page.next` (`:109`)
- an in-flight `fetchMore` then does
  `_events[key] = [...?_events[key], ...page.results]` (`:130`) and overwrites
  the cursor (`:131`) with the stale one

It is the exact bug `_generation` was written to prevent, in the provider that
didn't get it. `fetchFirst(force: true)` also ignores in-flight `fetchMore`
calls entirely.

- **Likelihood:** low. Needs a load-more in flight when you pull to refresh — a
  sub-second window you'd have to be trying for.
- **Consequence:** briefly duplicated/missing event rows; self-corrects on the
  next fetch.
- **What was done:** the `_generation` pattern ported across as
  `Map<String, int> _generations`, keyed per cache key — each month/filter combo
  is its own list, so a refresh of one must not invalidate another's `fetchMore`.
  `fetchFirst` bumps and captures it; `fetchMore` captures without bumping (it
  extends a list rather than replacing one), exactly as in `RidesProvider`.
  `fetchFirst`'s `finally` is conditional (a superseded fetch leaves the flag to
  the newer one that owns it); `fetchMore`'s is unconditional (only one runs per
  key at a time). `AudaxEventsCacheProvider` also became injectable
  (`{ApiClient? api}`), matching `RidesProvider`, because a guard this subtle
  can't be verified against a live API.
- **Pinned by** `test/features/audax/audax_events_cache_provider_test.dart`:
  five race tests mirroring `rides_provider_test.dart` one-for-one, plus one
  proving a refresh of one key doesn't discard another key's page 2. Each was
  checked against a deliberately neutered guard first — the splice test fails
  with `['fresh', 'stale']` instead of `['fresh']` — so they can actually fail.

**Why this one mattered more than its odds suggest:** the guard existing in one
provider and not its twin is how the codebase teaches its own conventions. The
next cache someone writes will be copied from whichever they read first.

### O3. Offline rides hold every full GPS track in RAM, permanently — ✅ fixed

`OfflineRidesProvider` is app-scoped in `main.dart` (lives for the whole
process), and `refresh()` → `OfflineRideStore.list()` fully decoded **every**
saved ride — complete `latitude`/`longitude`/`elevationM`/`gradientPct` arrays —
just to render a list of names and distances. It was also `listSync()` plus
`jsonDecode` of potentially multi-MB files **on the UI thread**.

- **Likelihood:** deterministic, but scales with saved rides. At 2–3 rides it's
  a few MB and invisible. At 10+ recorded rides (a 200 km ride at 1 Hz is ~29k
  points) it's tens of MB held forever, and a visible hitch opening the list.
- **What was done:** the store now writes the four fields a list row needs
  (id, name, distanceKm, savedAt, first weather point) into `meta.json` at save
  time, and `listSummaries()` reads *only* those. `OfflineRidesProvider.rides`
  is now `List<OfflineRideSummary>` — a type with no profile on it, so the
  regression is impossible to reintroduce by accident rather than merely
  discouraged. The full ride is read by `OfflineRidesProvider.load(id)` when a
  detail screen opens, and released with that screen. Directory listing moved
  from `listSync()` to the async `list()`.
- **Two things fell out of it:** `save()` now returns the `savedAt` it wrote, so
  the provider builds its new row from what it already holds instead of reading
  the multi-megabyte ride straight back off the disk it just wrote it to. And
  `OfflineRideDetailScreen` now takes a `rideId` rather than a loaded
  `OfflineRide`, matching `RideDetailScreen`.

**The upgrade path was the risky part.** Rides saved by an older build have a
`meta.json` carrying only `saved_at` — nothing to render a row from. Those fall
back to reading the ride once and then rewrite their `meta.json` in place, so
the slow path is paid once per ride rather than forever. Getting this wrong
would have shown existing users an empty offline list on upgrade, which is
exactly the silent-breakage pattern this whole document is about — so it is
tested against a real filesystem (`path_provider` pointed at a temp dir), not a
fake: `test/features/rides/offline_ride_store_test.dart`.

That suite also pins both constraints you named:

- **"the route must be visible offline"** — `load()` returns the full ride
  *with* its profile; the offline detail draws `RouteMap` from it. Without a
  profile the map has nothing to render, so this is asserted directly.
- **"tapping a notable section must still work"** — the same loaded profile is
  what `NotableSectionsCard` passes to `SectionDetailScreen`. Only *when* the
  profile loads changed, never *whether*.

One test proves the point structurally: it saves a ride, **deletes `ride.json`**,
and asserts the listing still works. If listing still renders with the GPS track
physically gone from disk, it provably never reads it.

### O19. The live GPS feed had no `onError`, and a fix that never came was silent — ✅ fixed

Found while chasing a real report: `LOCATION UPDATE FAILURE … kCLErrorDomain
error 0` on macOS.

**That log itself is benign.** `kCLErrorLocationUnknown` (code 0) is Core
Location saying "no fix right now". geolocator's `didFailWithError` NSLogs it
and then *explicitly returns* for that code — per Apple's guidance that it's
transient — so it never becomes a Dart error and never reaches this app:

```objc
NSLog(@"LOCATION UPDATE FAILURE:" ...);
if ([error.domain isEqualToString:kCLErrorDomain]
    && error.code == kCLErrorLocationUnknown) {
  return;   // swallowed
}
if (self.errorHandler) { ... }   // everything else does reach Dart
```

Two real gaps behind it, though:

1. **No `onError` on the position stream.** Errors geolocator *does* forward
   become Dart stream errors, and `positionStream().listen(_onPosition)` passed
   no `onError` — so they went to the zone unhandled while the rider watched a
   dot that never moved.
2. **A fix that never arrives is completely silent.** Nothing is emitted,
   because there's nothing to emit. Worst case of all: no error, no dot, no
   explanation. Especially likely on a Mac, which has no GPS and triangulates
   from surrounding wifi it may not recognise.

- **What was done:** an `onError` that records `gpsMessage`, plus a 10-second
  first-fix timer that says so if nothing has arrived. Both render as a note
  *over* the map rather than as `error`, which replaces the whole screen —
  losing the route because the signal dipped under a bridge would be wildly
  disproportionate. Cleared by the next fix. `LiveTrackingProvider` also became
  injectable (`{LocationService? locationService}`).
- **Pinned by** `test/features/tracking/live_tracking_provider_test.dart`,
  which also — finally — pins **F4**: the leak test drives dispose-during-the-
  permission-prompt and asserts nothing ever subscribes. Verified against a
  neutered guard, so it can fail.

---

## Outstanding — small / cheap

### O4. `_renameRide` leaks a `TextEditingController`

`rides_list_screen.dart:144` creates one per rename dialog and never disposes it.
Technically a leak; practically a few hundred bytes per rename. Fix: dispose it
after the `await showDialog`, or hoist it into a small `StatefulWidget`.

### O5. A failed "load more" hammers the server

`audax_events_screen.dart:54`'s scroll listener calls `fetchMore` on every scroll
frame near the bottom. After a failure `_nextUrls[key]` stays non-null and
`isLoadingMore` is false, so **every subsequent scroll event re-fires the failing
request**. There's a Retry button for this already; the listener shouldn't
compete with it. Fix: skip the listener's call when `moreErrorFor(key) != null`
and let the explicit Retry clear it.

### O6. `RideDetailProvider.applySmoothing` can strand the slider

`_applySmoothing` clears `_pendingSmoothingWindow` after the await, not in a
`finally`. A non-`ApiException` (see O1) rethrows past it, leaving the slider
pinned at the pending value. `isApplyingSmoothing` *is* cleared, so it's cosmetic.
Fix: `try/finally`.

### O7. `reachable()`'s timeout doesn't cancel the request

`api_client.dart:198` — `.timeout()` on the future stops you *waiting*; the HTTP
request keeps running to completion in the background. Harmless (a HEAD), but if
you ever poll this it's wasted sockets. Fix: pass a `CancelToken` and cancel it
on timeout.

### O8. Login can succeed while the screen says it failed

`AuthProvider.login` calls `_api.login` (which stores the token) then
`_api.me()`. If `me()` fails, `error` is set and `login` returns false — so you
stay on the login screen looking rejected, **but you are logged in**, and a
restart will auto-login you. Fix: treat a post-token `me()` failure as
non-fatal (proceed authenticated with a null `currentUser`), or roll the token
back.

### O9. `tryAutoLogin` treats unknown failures as authenticated

The `catch (_)` sets `status = authenticated` on any non-`ApiException`. That's
deliberate and documented for offline (don't sign someone out just because the
network is down), and it's the right call — but it now also swallows genuine
bugs into a logged-in state with a possibly-null `currentUser`. Worth narrowing
to the failure types you actually mean.

### O10. `WeatherScreen` doesn't validate the window

Picking a start after the finish is corrected on the start path
(`weather_screen.dart`) but not the finish path — you can request an inverted
window and the server decides what that means. Fix: mirror the clamp.

---

## Outstanding — noted, probably ignore

### O11. Use-after-dispose on screen-scoped providers

`notifyListeners()` asserts `debugAssertNotDisposed` (`change_notifier.dart:413`
in your Flutter 3.44.6), so this **throws in debug/profile and is a silent no-op
in release**. Exposed: `RideDetailProvider.load`, `RidesProvider.loadFirst`,
`StravaImportProvider.refreshStatus`, and `ConnectivityService._evaluate` (which
can be mid-5s-ping when its screen pops, `connectivity_service.dart:41`). Pop a
screen while a request is in flight and its `finally` notifies a dead provider.

App-level providers (`main.dart`) are immune — they outlive everything.

Given you ship release builds, impact is ~zero; the cost is noisy debug sessions
masking real errors. `LiveTrackingProvider` had the same shape and *was* fixed
(F4) because there it also leaked the GPS receiver. Fix if it ever bothers you:
the same `_disposed` flag.

### O12. `RouteMap` / `ElevationChart` re-allocate everything each build

`route_map.dart:209` builds a fresh `List<LatLng>` of every profile point (plus
`_thinWeather` and `_placeWeatherBubbles`) inside `build()`, with no
memoization; `ElevationChart` does the same with `FlSpot`. During live tracking
every GPS fix → `notifyListeners` → rebuild → the whole route re-allocated.

**I over-dramatized this originally** ("50k LatLng per fix") without checking
your typical `pointCount`. At a few thousand points this is sub-millisecond and
completely fine, and your not having noticed is real evidence. Only worth
touching if you see live-tracking jank on long recorded rides. Fix then: cache
the derived lists against `profile` identity in a `StatefulWidget`, recomputing
in `didUpdateWidget`.

### O13. `_onPosition` rescans the whole route per fix

`live_tracking_provider.dart:73` — a full linear scan with a Haversine per point
on every GPS fix, on the UI thread. Same calibration as O12: fine at a few
thousand points. It also snaps to the globally nearest point, so a self-crossing
route (loop, out-and-back) can report progress from the wrong lap — that's a
correctness quirk, not a performance one. Fix if needed: search a window around
the last matched index instead of the whole array.

### O14. Session caches are unbounded

`AudaxEventsCacheProvider`, `WeatherCacheProvider` and `SectionsCacheProvider`
grow for the life of the process, keyed by query/ride. Documented as deliberate
and in-memory only. Entries are small; a user would have to step through a great
many months to notice. No action.

### O15. The audax `upcoming` filter goes stale

Session-long caching is deliberate, but `upcoming` is time-dependent — events
that pass during a long session keep showing. Fix if it ever matters: exempt
`upcomingOnly` keys from the cache, or give them a TTL.

### O16. `logout()` now swallows a failed delete

Introduced by F1, consciously. A keystore that can't delete may keep the entry
on disk. It can't be presented (`token` answers null when a read fails), so this
is belt-and-braces, but if you want it airtight: attempt an overwrite-then-delete
and surface a warning if both fail.

### O17. `RideDetailScreen` `_highlightIndex` could `RangeError`

`_highlightIndex` indexes the profile arrays. Re-smoothing replaces `ride` with a
profile that may have **fewer** points, so a retained index could run past the
end. In practice `onIndexSelected(null)` fires on finger-lift, so the index is
almost always null before you can reach the slider — you'd need multi-touch.
Latent, very unlikely. `SectionDetailScreen` already clamps defensively
(`_sectionProfile`); the same instinct would fit here.

### O18. `StravaImportProvider.disconnectOnExit()` runs from `dispose()`

`strava_import_screen.dart:49` fires an un-awaited network call from `dispose()`.
It works (the provider outlives the widget briefly and the call is
fire-and-forget by design, as documented), but nothing can observe or retry it —
if the disconnect fails, the athlete slot silently stays occupied. Acceptable
given it's explicitly best-effort cleanup; worth knowing.

---

## Scorecard

| Tier | Items |
|---|---|
| Fixed | F1 keystore brick, F2 theme throw, F3 stuck FAB, F4 GPS leak + live spinner, O1 mitigation, O2 race guard, O3 offline memory, O19 GPS feed feedback |
| Still open, cheap | O4–O10 |
| Noted, likely ignore | O1's full `_decode` refactor, O11–O18 |

**On O1 specifically:** it led this list in the first draft and has since been
downgraded twice, both times by checking a claim instead of asserting it (the
HTTPS scheme; then the backend queryset). The mechanism is proven, the triggers
mostly aren't real. If you read one thing here as a lesson about the audit
itself: a finding's mechanism being real says nothing about whether it will ever
fire, and only the second question decides whether it's worth your time.

**Context that belongs next to the list:** `flutter analyze` is clean, all 17
tests pass, and the codebase is above average — the `_generation` guards and
their race tests, the `_anonymous` interceptor rationale, the offline store's
cleanup-on-failure, and the comments that explain *why* rather than *what* are
all things most projects don't have. O2 is only findable *because* the good
pattern already exists one file over.
