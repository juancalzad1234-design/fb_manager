import 'package:flutter_test/flutter_test.dart';
import 'package:fb_manager/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Cyber FB Manager Pro smoke test', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const CyberFBManagerApp());
    await tester.pumpAndSettle();

    expect(find.text('CYBER FB MANAGER PRO'), findsOneWidget);
    expect(find.text('AÑADIR'), findsOneWidget);
    expect(find.text('IR AL ACTUAL'), findsOneWidget);
  });
}
