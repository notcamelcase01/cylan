import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:cylan/main.dart';

// Run with a real test account, e.g.:
//   flutter test integration_test/app_test.dart \
//     --dart-define-from-file=test_config.json -d <device-id>
//
// Buttons that hand off to native OS UI (share sheet, location permission,
// file picker, Strava's browser redirect) are intentionally not exercised
// here — they leave the Flutter widget tree, where WidgetTester can't drive
// or wait on them, and would hang a headless run.
const _username = String.fromEnvironment('TEST_USERNAME');
const _password = String.fromEnvironment('TEST_PASSWORD');

// Most loading states in this app (AuthGate's initial check, the login
// button's busy spinner, ride/weather loading, offline-save progress) use an
// *indeterminate* CircularProgressIndicator, whose animation never stops.
// tester.pumpAndSettle() waits for animations to stop, so it just spins
// until it times out whenever one of these is on screen. Poll for the
// expected finder instead.
Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final end = DateTime.now().add(timeout);
  while (finder.evaluate().isEmpty) {
    if (DateTime.now().isAfter(end)) {
      fail('Timed out waiting for $finder');
    }
    await tester.pump(const Duration(milliseconds: 200));
  }
  // Let any in-flight (non-looping) transition frames flush too.
  await tester.pump(const Duration(milliseconds: 200));
}

// On a small desktop window, content can be taller than the visible
// viewport (e.g. the landing screen's hero + feature list), so a target
// below the fold never receives the tap even though the finder locates it.
// Scroll it into view first.
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('logout -> login -> ride -> weather -> smoothing', (tester) async {
    expect(
      _username.isNotEmpty && _password.isNotEmpty,
      isTrue,
      reason: 'Pass credentials with '
          '--dart-define-from-file=test_config.json (see test_config.example.json)',
    );

    await tester.pumpWidget(const CylanApp());

    // AuthGate resolves to either the rides list (already logged in) or the
    // landing screen (logged out) once tryAutoLogin() finishes.
    final loggedInIcon = find.byIcon(Icons.account_circle_outlined);
    final loggedOutText = find.text('I already have an account');
    await _pumpUntilFound(
      tester,
      find.byWidgetPredicate(
        (_) =>
            loggedInIcon.evaluate().isNotEmpty ||
            loggedOutText.evaluate().isNotEmpty,
      ),
      timeout: const Duration(seconds: 20),
    );

    if (loggedInIcon.evaluate().isNotEmpty) {
      await _tap(tester, loggedInIcon);
      await _pumpUntilFound(tester, find.text('Log out'));
      await _tap(tester, find.text('Log out'));
      await _pumpUntilFound(tester, loggedOutText);
    }

    expect(loggedOutText, findsOneWidget);
    await _tap(tester, loggedOutText);
    await _pumpUntilFound(tester, find.byType(TextFormField));

    await tester.enterText(find.byType(TextFormField).at(0), _username);
    await tester.enterText(find.byType(TextFormField).at(1), _password);
    await _tap(tester, find.text('Log in'));
    await _pumpUntilFound(
      tester,
      find.text('My Rides'),
      timeout: const Duration(seconds: 20),
    );

    final themeToggle = find.byWidgetPredicate(
      (w) => w is Tooltip && (w.message?.startsWith('Theme:') ?? false),
    );
    if (themeToggle.evaluate().isNotEmpty) {
      await _tap(tester, themeToggle);
      await tester.pump(const Duration(milliseconds: 300));
    }

    expect(find.byType(Card), findsWidgets);
    await _tap(tester, find.byType(Card).first);
    await _pumpUntilFound(tester, find.text('Weather'));

    await _tap(tester, find.text('Weather'));
    await _pumpUntilFound(tester, find.text('Get forecast'));

    await _tap(tester, find.text('Get forecast'));
    await _pumpUntilFound(
      tester,
      find.byWidgetPredicate(
        (w) =>
            w is Icon && w.icon == Icons.refresh, // appears once fetch completes
      ),
      timeout: const Duration(seconds: 20),
    );

    await _tap(tester, find.byTooltip('Back'));
    await _pumpUntilFound(tester, find.text('Weather'));

    final slider = find.byType(Slider);
    if (slider.evaluate().isNotEmpty) {
      await tester.ensureVisible(slider);
      await tester.pump();
      await tester.drag(slider, const Offset(40, 0));
      await tester.pump(const Duration(milliseconds: 500));
    }

    final offlineToggle = find.byIcon(Icons.download_for_offline_outlined);
    if (offlineToggle.evaluate().isNotEmpty) {
      await _tap(tester, offlineToggle);
      await _pumpUntilFound(tester, find.text('Save'));
      await _tap(tester, find.text('Save'));
      await _pumpUntilFound(
        tester,
        find.byIcon(Icons.offline_pin),
        timeout: const Duration(seconds: 20),
      );

      await _tap(tester, find.byIcon(Icons.offline_pin));
      await _pumpUntilFound(tester, find.text('Remove'));
      await _tap(tester, find.text('Remove'));
      await _pumpUntilFound(tester, offlineToggle);
    }
  });
}
