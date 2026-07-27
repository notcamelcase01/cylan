[← Back to TESTING.md](../TESTING.md)

# Automated tests

Unit tests over the API layer and the providers. They exist for the things the
manual checklist genuinely **can't** reach: two overlapping network requests
resolving in the wrong order, and the exact JSON shapes the server returns on
failure. You can't hand-time a pull-to-refresh against an in-flight page load;
these do it deterministically, every run, in milliseconds.

### Running them

Everything here runs headless from the project root — no device, no network,
no test account. The whole suite takes about four seconds.

Run **all** of them:

```
flutter test
```

Run **one file**:

```
flutter test test/core/api/api_client_test.dart
```

Run **one test** by name (a substring of its description is enough):

```
flutter test --plain-name "a 401 detail body carries its status code through"
```

### Reading the output

`flutter test` prints one line that keeps overwriting itself, ending in
something like:

```
00:01 +85: All tests passed!
```

The `+85` is the number of **individual tests** that passed — not files, not
features. So `flutter test` reporting `+85` and
`flutter test test/core/api/api_client_test.dart` reporting `+14` aren't in
conflict: the second is just the 14 tests that live in that one file. Today
the 85 break down as **14 + 12 + 2 + 7 + 19 + 11 + 6 + 7 + 6 + 1** across the
ten files below.

A failure looks like `+15 -1:` (fifteen passed, one failed), prints the
expected vs. actual value, and exits non-zero — so CI catches it too. Add
`-r expanded` to list every test name as it runs instead of a single updating
line.

### `test/core/api/api_client_test.dart` — 14 tests

The Dio layer in `lib/core/api/api_client.dart`. Swaps Dio's transport for an
in-memory fake, so the **real** auth interceptor, timeouts, and status handling
all still run — only the network is faked.

- The auth interceptor attaches the stored token to private endpoints, and
  deliberately **doesn't** to `/audax-events/` or login. (DRF authenticates
  before checking permissions, so a stale token would turn the public calendar
  into a 401.)
- Error mapping: a `{"detail": …}` body keeps its status code (so a 401 is
  recognisable as one); field errors are collected; a dead connection produces
  a `null` status code, which is how callers tell "never reached the server"
  from "the server said no".
- URL building: relative paths join `baseUrl` correctly, query params survive,
  and absolute pagination URLs are used as-is.
- Google Maps import: the request carries `url` and (when given) `name`, and
  omits `name` entirely rather than sending it blank; a domain error (e.g. a
  route outside India) surfaces its server message rather than throwing a raw
  type; a dropped connection resolves to an `ApiException`, not a hang.

### `test/features/rides/rides_provider_test.dart` — 12 tests

Request races on the rides list. These stage two overlapping requests and
settle them **in the wrong order on purpose** — the thing you can't do by hand.
Covers: a page-2 load landing after a pull-to-refresh must be discarded rather
than spliced onto the fresh list; two overlapping refreshes settle on the newer
answer; a superseded load doesn't clear the newer one's spinner or surface a
phantom error.

Also covers Google Maps import: a successful import prepends the new ride and
clears any prior error; a domain error (`ApiException`, e.g. route outside
India) surfaces its message without adding a phantom ride; and — since not
every failure arrives as an `ApiException` (a 2xx with an unexpected body
shape, say) — an arbitrary unanticipated exception is still caught rather
than crashing the caller or stranding its busy flag.

### `test/features/rides/offline_rides_provider_test.dart` — 2 tests

The same request-race idea for the offline store: a disk read that started
**before** a save must not land afterwards and erase it (that bug flipped a
just-saved ride's "Saved ✓" back to unsaved), and an invalidated refresh must
still release its spinner.

### `test/features/rides/offline_ride_store_test.dart` — 7 tests

The on-disk offline store itself (`meta.json` + saved track). Covers: a ride
lists from its metadata alone without needing to open the full GPS track;
`load()` returns the full ride for the offline map; `save()` reports back the
`savedAt` it actually wrote; and rides saved by an older app version (missing
newer metadata fields) are still listed via a fallback, get upgraded in place
the first time they're read so the slow path only runs once, and survive a
save directory that can't be read at all.

### `test/features/rides/control_point_store_test.dart` — 19 tests

The rider's personal control points: the on-disk store and the provider over
it. Storage covers a round-trip through a real temp directory, rides staying
separate, and two files-from-elsewhere cases — an unreadable file reads as
empty **without deleting it** (unlike the weather cache, these can't be
refetched from anywhere), and a point written by a newer build with a type this
one doesn't know still loads, falling back to a default icon.

The rest covers importing an event's points, which is where the rules live.
Two of these exist because of a bug the first design shipped with: control
points are stored per **ride**, but a ride can back any number of events, so
anything that seeded them automatically made two events fight over one file.
Hence `two events using the same organiser id do not collide` (organiser ids
are unique only within their own event) and `removing one event leaves the
other and the rider alone`.

The others: an import copies points in and places them along the route;
importing the same event twice adds nothing; removing an event re-arms its
import while deleting the rider's own points never does; and an imported point
can be neither edited nor deleted singly, so a point attributed to an organiser
really is what they published.

### `test/core/models/ride_profile_test.dart` — 11 tests

The route geometry both control-point add-methods depend on: `pointAtKm`
(distance → coordinate, interpolating between samples and clamping outside the
ride) and its inverse `nearestDistanceKm` (coordinate → distance, for a point
tapped on the map), including that the two round-trip. Plus an empty profile —
no track, zero total, and no throw — since a ride without GPS reaches these.

### `test/core/models/event_test.dart` — 6 tests

The event payload's control-point fields, in both directions. Reading:
`default_control_points` parses (and is empty on a summary payload, which never
carries it), an unknown `type` from a newer server falls back to `checkpoint`,
and a parsed point has no `sourceEventId` until the rider imports it. Writing:
`toEventJson` sends **only** what the API stores — no client-derived distance,
no `sourceEventId` — and round-trips.

### `test/features/audax/audax_events_cache_provider_test.dart` — 7 tests

The same request-race and unexpected-failure coverage as the rides list,
applied to the per-month/filter Audax events cache: a late `fetchMore`
doesn't get appended after a refresh replaces the list, overlapping refreshes
settle on the newer one, a superseded fetch doesn't clobber the current
spinner or surface a stale error, and refreshing one cache key doesn't
invalidate an unrelated key's in-flight `fetchMore`. Plus: a non-`ApiException`
failure (from either `refresh` or `fetchMore`) still surfaces as an error
instead of a stuck spinner, and `fetchMore` failing keeps whatever was already
loaded rather than clearing it.

### `test/features/tracking/live_tracking_provider_test.dart` — 6 tests

The GPS follow-mode provider, without real location hardware. Covers: leaving
the screen while the permission prompt is still open never opens the GPS feed
afterwards; a start failure surfaces an error instead of spinning forever; a
permission refusal explains itself and stops (rather than retrying blindly);
a feed error is shown as a dismissable note rather than replacing the whole
screen; a subsequent good fix clears that note; and a fix that never arrives
says so explicitly instead of leaving the rider staring at a silent screen.

### `test/widget_test.dart` — 1 test

Boots the app headless and checks it reaches the auth gate. A smoke test — it
catches "the app doesn't start at all", nothing finer.
