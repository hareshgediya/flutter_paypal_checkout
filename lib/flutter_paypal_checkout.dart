import 'src/generated/paypal_api.g.dart';

export 'src/generated/paypal_api.g.dart'
    show
        CardBillingAddressMessage,
        CardMessage,
        CardPaymentRequestMessage,
        CardPaymentResultMessage,
        PaymentRequestMessage,
        PaymentResultMessage,
        PaypalConfigMessage,
        PaypalEnvironment,
        PaypalUserAction;

/// Starts PayPal or card checkout on iOS.
///
/// Create and capture the order on your backend. This plugin initializes the
/// PayPal iOS SDK and approves an existing order with PayPal or a card.
class FlutterPaypalCheckout {
  FlutterPaypalCheckout({PaypalHostApi? api}) : _api = api ?? PaypalHostApi();

  final PaypalHostApi _api;

  /// Configures the PayPal SDK. No network call is made.
  ///
  /// `returnUrl` and `cancelUrl` must be Universal Links, and the host app must
  /// register their domain as an Associated Domain. Also add `paypal` to
  /// `LSApplicationQueriesSchemes`. When `fallbackSchemeUrl` is set, register
  /// that scheme under `CFBundleURLTypes`.
  Future<void> initialize(PaypalConfigMessage config) {
    return _api.initialize(config);
  }

  /// Approves [request.orderId] in the PayPal app or an in-app browser.
  ///
  /// On success, capture the order on your backend using [PaymentResultMessage.orderId].
  /// A buyer cancel returns `success: false` and `errorCode: "canceled"`.
  Future<PaymentResultMessage> pay(PaymentRequestMessage request) {
    return _api.startPayment(request);
  }

  /// Approves [request.orderId] with a card.
  ///
  /// Set `request.sca` to `SCA_ALWAYS` to launch 3D Secure on every payment, or
  /// `SCA_WHEN_REQUIRED` to launch it only when the issuer requires it.
  /// 3D Secure runs inside the SDK. On success, capture the order on your
  /// backend. A buyer cancel returns `success: false` and `errorCode: "canceled"`.
  Future<CardPaymentResultMessage> payWithCard(
    CardPaymentRequestMessage request,
  ) {
    return _api.startCardPayment(request);
  }
}
