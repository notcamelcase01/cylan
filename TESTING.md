# Testing

Cylan is tested at three levels. They cover different things and none replaces
another:

| Level | What it is | Command | Needs |
|---|---|---|---|
| **[Manual](#manual-checklist)** | The checklists below — the primary path. Anything involving a real map, GPS, file picker, share sheet, or your eyes on a colour. | — | A device + the test account |
| **[Automated](TESTINGMD/automated-tests.md)** | Unit tests over the API layer and the providers. Covers request races and error handling that **can't** be staged by hand. | `flutter test` | Nothing — ~4s, headless |
| **[Integration](TESTINGMD/integration-tests.md)** | One end-to-end script driving the real app against the live API. | `flutter test integration_test/app_test.dart …` | A device + the test account |

**Before a release:** run `flutter test` (cheap, catches regressions in logic),
then work the manual checklist for whatever you touched. The integration script
is a bonus — it's a starting point, not a gate.

Use the shared test account for anything that hits the backend
(`cyclingngin.duckdns.org`). It has enough rides/data to exercise every screen.

---

# Manual checklist

Work through the relevant file below before a release, or after touching that
feature's area. Each item is a step to perform and the result to confirm. Split
by feature so a change to one area doesn't require scrolling past everything
else:

| Area | File |
|---|---|
| Auth (signup, login, session, profile) | [TESTINGMD/auth.md](TESTINGMD/auth.md) |
| Rides (list, upload, Strava import, Google Maps import) | [TESTINGMD/rides.md](TESTINGMD/rides.md) |
| Audax events (calendar, filters, badges, caching) | [TESTINGMD/audax-events.md](TESTINGMD/audax-events.md) |
| Events (browse, create, subscribe, checklists, waiver docs) | [TESTINGMD/events.md](TESTINGMD/events.md) |
| Ride detail (map, chart, notable sections, share) | [TESTINGMD/ride-detail.md](TESTINGMD/ride-detail.md) |
| Weather (forecast, persistence) | [TESTINGMD/weather.md](TESTINGMD/weather.md) |
| Live tracking (GPS follow mode) | [TESTINGMD/live-tracking.md](TESTINGMD/live-tracking.md) |
| Offline rides | [TESTINGMD/offline-rides.md](TESTINGMD/offline-rides.md) |
| Cross-cutting (nav, app bar, theme, network, layout) | [TESTINGMD/cross-cutting.md](TESTINGMD/cross-cutting.md) |

---

# Automated tests

See [TESTINGMD/automated-tests.md](TESTINGMD/automated-tests.md) — what each
test file covers and why, plus how to run one file or one test by name.

---

# Integration tests

See [TESTINGMD/integration-tests.md](TESTINGMD/integration-tests.md) — the
end-to-end script against the live API and its known rough edges.
