import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cylan/main.dart';

void main() {
  testWidgets('App boots to the auth gate', (WidgetTester tester) async {
    await tester.pumpWidget(const CylanApp());
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
