import 'package:flutter_test/flutter_test.dart';
import 'package:quotex_signal_app/main.dart';
import 'package:quotex_signal_app/services/signal_service.dart';

void main() {
  testWidgets('App loads dashboard screen smoke test', (WidgetTester tester) async {
    final service = SignalService(autoConnect: false);
    try {
      await tester.pumpWidget(QuotexSignalApp(signalService: service));
      await tester.pump();
      expect(find.text('QUOTEX PRO BOT'), findsOneWidget);
    } finally {
      service.dispose();
    }
  });
}
