import 'package:flutter_test/flutter_test.dart';
import 'package:chatapp/main.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const ProviderScope(child: ChatApp()));

    // Verify that we start at the empty state
    expect(find.text('Ready to explore?'), findsOneWidget);
  });
}
