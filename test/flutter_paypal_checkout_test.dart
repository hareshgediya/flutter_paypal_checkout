import 'package:flutter/services.dart';
import 'package:flutter_paypal_checkout/flutter_paypal_checkout.dart';
import 'package:flutter_paypal_checkout/src/generated/paypal_api.g.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const initializeChannelName =
      'dev.flutter.pigeon.flutter_paypal_checkout.PaypalHostApi.initialize';
  const payChannelName =
      'dev.flutter.pigeon.flutter_paypal_checkout.PaypalHostApi.startPayment';
  const cardChannelName =
      'dev.flutter.pigeon.flutter_paypal_checkout.PaypalHostApi.startCardPayment';

  late FlutterPaypalCheckout checkout;

  setUp(() {
    checkout = FlutterPaypalCheckout();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler<Object?>(
          BasicMessageChannel<Object?>(
            initializeChannelName,
            PaypalHostApi.pigeonChannelCodec,
          ),
          null,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler<Object?>(
          BasicMessageChannel<Object?>(
            payChannelName,
            PaypalHostApi.pigeonChannelCodec,
          ),
          null,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler<Object?>(
          BasicMessageChannel<Object?>(
            cardChannelName,
            PaypalHostApi.pigeonChannelCodec,
          ),
          null,
        );
  });

  test('initialize sends the PayPal SDK configuration', () async {
    PaypalConfigMessage? sent;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler<Object?>(
          BasicMessageChannel<Object?>(
            initializeChannelName,
            PaypalHostApi.pigeonChannelCodec,
          ),
          (Object? message) async {
            final args = message! as List<Object?>;
            sent = args.single! as PaypalConfigMessage;
            return <Object?>[null];
          },
        );

    await checkout.initialize(
      PaypalConfigMessage(
        clientId: 'client',
        merchantId: 'merchant',
        environment: PaypalEnvironment.sandbox,
        returnUrl: 'https://example.com/paypal/return',
        cancelUrl: 'https://example.com/paypal/cancel',
        fallbackSchemeUrl: 'flutterpaypalcheckout://paypal-return',
      ),
    );

    expect(sent?.clientId, 'client');
    expect(sent?.merchantId, 'merchant');
    expect(sent?.environment, PaypalEnvironment.sandbox);
    expect(sent?.returnUrl, 'https://example.com/paypal/return');
    expect(sent?.cancelUrl, 'https://example.com/paypal/cancel');
    expect(sent?.fallbackSchemeUrl, 'flutterpaypalcheckout://paypal-return');
  });

  test('pay returns the approved order for backend capture', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler<Object?>(
          BasicMessageChannel<Object?>(
            payChannelName,
            PaypalHostApi.pigeonChannelCodec,
          ),
          (Object? message) async {
            final request =
                (message! as List<Object?>).single! as PaymentRequestMessage;
            expect(request.orderId, 'ORDER-1');
            expect(request.userAction, PaypalUserAction.payNow);
            return <Object?>[
              PaymentResultMessage(
                success: true,
                orderId: 'ORDER-1',
                payerId: 'PAYER-1',
              ),
            ];
          },
        );

    final result = await checkout.pay(
      PaymentRequestMessage(
        orderId: 'ORDER-1',
        userAction: PaypalUserAction.payNow,
      ),
    );

    expect(result.success, isTrue);
    expect(result.orderId, 'ORDER-1');
    expect(result.payerId, 'PAYER-1');
  });

  test('pay surfaces a buyer cancellation', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler<Object?>(
          BasicMessageChannel<Object?>(
            payChannelName,
            PaypalHostApi.pigeonChannelCodec,
          ),
          (Object? message) async {
            return <Object?>[
              PaymentResultMessage(
                success: false,
                orderId: 'ORDER-1',
                errorCode: 'canceled',
                errorMessage: 'PayPal checkout has been canceled by the user',
              ),
            ];
          },
        );

    final result = await checkout.pay(
      PaymentRequestMessage(orderId: 'ORDER-1'),
    );

    expect(result.success, isFalse);
    expect(result.errorCode, 'canceled');
  });

  test('payWithCard sends the card and 3D Secure preference', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler<Object?>(
          BasicMessageChannel<Object?>(
            cardChannelName,
            PaypalHostApi.pigeonChannelCodec,
          ),
          (Object? message) async {
            final request =
                (message! as List<Object?>).single!
                    as CardPaymentRequestMessage;
            expect(request.orderId, 'ORDER-1');
            expect(request.sca, 'SCA_ALWAYS');
            expect(request.card.number, '4111111111111111');
            expect(request.card.expirationMonth, '01');
            expect(request.card.expirationYear, '2028');
            return <Object?>[
              CardPaymentResultMessage(
                success: true,
                orderId: 'ORDER-1',
                status: 'APPROVED',
                didAttemptThreeDSecureAuthentication: true,
              ),
            ];
          },
        );

    final result = await checkout.payWithCard(
      CardPaymentRequestMessage(
        orderId: 'ORDER-1',
        sca: 'SCA_ALWAYS',
        card: CardMessage(
          number: '4111111111111111',
          expirationMonth: '01',
          expirationYear: '2028',
          securityCode: '123',
        ),
      ),
    );

    expect(result.success, isTrue);
    expect(result.didAttemptThreeDSecureAuthentication, isTrue);
  });
}
