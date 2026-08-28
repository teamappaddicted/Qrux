// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:qrux/main.dart';

void main() {
  testWidgets('QRUX opens with its splash branding', (WidgetTester tester) async {
    await tester.pumpWidget(const QruxApp());
    expect(find.text('QRUX'), findsOneWidget);
    expect(find.text('SECURE MOTION SYSTEMS'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(find.text('Welcome to QRUX'), findsOneWidget);
  });
}
