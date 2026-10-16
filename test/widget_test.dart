import 'package:flutter_test/flutter_test.dart';
import 'package:record_mi/main.dart';

void main() {
  testWidgets('CallRecorderApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const CallRecorderApp());
    expect(find.text('Shizuku Call Recorder'), findsOneWidget);
  });
}
