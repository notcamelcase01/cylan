[← Back to TESTING.md](../TESTING.md)

# Integration tests

### `integration_test/app_test.dart`

Unlike the automated tests, this drives the **real app against the live
API**, so it needs a device and the test account.

An end-to-end script driving this flow against the live API with a test account:

**logout → login → open a ride → weather → notable section (open, exit) → smoothing → offline map (save, open, exit)**

The notable-section and smoothing/offline steps are guarded — they run only if
the test ride actually has sections / a GPS track, so the script still passes on
a ride without them.

It's kept as a starting point, not the primary test path — manual testing
is. Verified passing on a physical device; running on macOS desktop is
flakier (see below). Credentials come from a gitignored `test_config.json`
(shape in `test_config.example.json`) via `--dart-define-from-file`:

```
flutter test integration_test/app_test.dart \
  --dart-define-from-file=test_config.json -d <device-id>
```

Known rough edges on **macOS desktop only** (not seen on a real device): the
app window needs real focus to receive taps (run from a normal Terminal, not
a headless shell), and the default scroll-drag point can land on the route
map and pan it instead of scrolling the list. A wirelessly-tethered iOS
device needs `--publish-port`.
