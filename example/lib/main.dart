import 'package:flutter/services.dart';
import 'package:flutter_credit_card/flutter_credit_card.dart';
import 'package:flutter_paypal_checkout/flutter_paypal_checkout.dart';
import 'package:material_ui/material_ui.dart';

const _clientId =
    'AUCVSFXy48K2dZreXHVgrfhXI-muHSwU0Hpb6iLxwO-oMixIi6w8Oizq6boT77U82PwHxgRh-6Rk6p0x';
const _merchantId = 'YOUR_MERCHANT_ID';
const _returnUrl = 'https://tudo.app/pages/payments-success';
const _cancelUrl = 'https://tudo.app/pages/payments-error';
const _fallbackSchemeUrl = 'flutterpaypalcheckout://paypal-return';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _checkout = FlutterPaypalCheckout();
  final _orderId = TextEditingController();
  final _cardFormKey = GlobalKey<FormState>();

  String _cardNumber = '';
  String _expiryDate = '';
  String _cardHolderName = '';
  String _cvvCode = '';
  bool _isCvvFocused = false;
  String _status = 'Initializing PayPal...';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _orderId.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      await _checkout.initialize(
        PaypalConfigMessage(
          clientId: _clientId,
          merchantId: _merchantId,
          environment: PaypalEnvironment.sandbox,
          returnUrl: _returnUrl,
          cancelUrl: _cancelUrl,
          fallbackSchemeUrl: _fallbackSchemeUrl,
        ),
      );
      if (!mounted) return;
      setState(() => _status = 'PayPal is ready. Enter an order ID from your backend.');
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() => _status = '${error.code}: ${error.message}');
    }
  }

  Future<void> _pay() async {
    setState(() {
      _busy = true;
      _status = 'Starting PayPal checkout...';
    });

    try {
      final result = await _checkout.pay(
        PaymentRequestMessage(orderId: _orderId.text.trim(), userAction: PaypalUserAction.payNow),
      );
      if (!mounted) return;
      setState(() {
        _status = result.success
            ? 'Approved order ${result.orderId}. Capture it on your backend. Payer ${result.payerId}.'
            : 'Checkout finished without approval (${result.errorCode}): ${result.errorMessage}';
      });
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() {
        _status = '${error.code}: ${error.message}';
      });
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _payWithCard() async {
    if (_cardFormKey.currentState?.validate() != true) {
      setState(() => _status = 'Enter a valid card.');
      return;
    }
    final expiry = _expiryParts(_expiryDate);
    if (expiry == null) {
      setState(() => _status = 'Enter a valid expiry date.');
      return;
    }

    setState(() {
      _busy = true;
      _status = 'Starting card payment...';
    });

    try {
      final result = await _checkout.payWithCard(
        CardPaymentRequestMessage(
          orderId: _orderId.text.trim(),
          sca: 'SCA_ALWAYS',
          card: CardMessage(
            number: _cardNumber.replaceAll(' ', ''),
            expirationMonth: expiry.month,
            expirationYear: expiry.year,
            securityCode: _cvvCode,
            cardholderName: _cardHolderName,
          ),
        ),
      );

      debugPrint('result: ${result.toString()}');

      if (!mounted) return;
      setState(() {
        _status = result.success
            ? 'Approved order ${result.orderId}. Capture it on your backend. 3D Secure attempted: ${result.didAttemptThreeDSecureAuthentication}.'
            : 'Card payment finished without approval (${result.errorCode}): ${result.errorMessage}';
      });
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() {
        _status = '${error.code}: ${error.message}';
      });
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  ({String month, String year})? _expiryParts(String expiryDate) {
    final parts = expiryDate.split('/');
    if (parts.length != 2 || parts[0].length != 2 || parts[1].length != 2) {
      return null;
    }
    return (month: parts[0], year: '20${parts[1]}');
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('PayPal Checkout')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _orderId,
                decoration: const InputDecoration(labelText: 'Order ID'),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy ? null : _pay,
                child: Text(_busy ? 'Waiting for PayPal...' : 'Pay'),
              ),
              const SizedBox(height: 24),
              CreditCardWidget(
                cardNumber: _cardNumber,
                expiryDate: _expiryDate,
                cardHolderName: _cardHolderName,
                cvvCode: _cvvCode,
                showBackView: _isCvvFocused,
                isHolderNameVisible: true,
                onCreditCardWidgetChange: (_) {},
              ),
              CreditCardForm(
                formKey: _cardFormKey,
                cardNumber: _cardNumber,
                expiryDate: _expiryDate,
                cardHolderName: _cardHolderName,
                cvvCode: _cvvCode,
                onCreditCardModelChange: (CreditCardModel model) {
                  setState(() {
                    _cardNumber = model.cardNumber;
                    _expiryDate = model.expiryDate;
                    _cardHolderName = model.cardHolderName;
                    _cvvCode = model.cvvCode;
                    _isCvvFocused = model.isCvvFocused;
                  });
                },
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy ? null : _payWithCard,
                child: const Text('Pay with card'),
              ),
              const SizedBox(height: 16),
              Text(_status),
            ],
          ),
        ),
      ),
    );
  }
}
