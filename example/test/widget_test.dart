import 'package:flutter_credit_card/flutter_credit_card.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:flutter_paypal_checkout_example/main.dart';

void main() {
  testWidgets('shows the order ID field', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('PayPal Checkout'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Order ID'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Pay'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Pay with card'), findsOneWidget);
    expect(find.byType(CreditCardForm), findsOneWidget);
    expect(find.text('Client ID'), findsNothing);
    expect(find.text('Return URL'), findsNothing);
  });
}
