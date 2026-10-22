import 'package:flutter_paypal_checkout/flutter_paypal_checkout.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('plugin can be constructed', (WidgetTester tester) async {
    expect(FlutterPaypalCheckout(), isNotNull);
  });
}
