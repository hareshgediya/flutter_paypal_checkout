import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/generated/paypal_api.g.dart',
    kotlinOut: 'android/src/main/kotlin/com/flutter_paypal_checkout/generated/PaypalApi.g.kt',
    kotlinOptions: KotlinOptions(package: 'com.flutter_paypal_checkout.generated'),
    swiftOut:
        'ios/flutter_paypal_checkout/Sources/flutter_paypal_checkout/generated/PaypalApi.g.swift',
  ),
)
/// Environment for the PayPal SDK.
enum PaypalEnvironment { sandbox, live }

/// Configuration to initialize the PayPal SDK.
class PaypalConfigMessage {
  PaypalConfigMessage({
    required this.clientId,
    required this.merchantId,
    required this.environment,
    required this.returnUrl,
    required this.cancelUrl,
    this.fallbackSchemeUrl,
    this.bnCode,
  });

  final String clientId;

  /// Encrypted PayPal merchant account ID. Required by SDK 3.x and distinct from [clientId].
  final String merchantId;

  final PaypalEnvironment environment;

  /// Universal Link PayPal opens after the buyer approves.
  final String returnUrl;

  /// Universal Link PayPal opens if the buyer cancels.
  final String cancelUrl;

  /// Custom-scheme fallback, for example "merchantapp://paypal-return".
  final String? fallbackSchemeUrl;

  /// Partner attribution code. Omit for a direct merchant integration.
  final String? bnCode;
}

/// Buyer action shown during checkout.
enum PaypalUserAction {
  /// Buyer reviews the order before paying. Maps to PayPal `.continue`.
  review,

  /// Buyer pays immediately. Maps to PayPal `.payNow`.
  payNow,
}

/// Request to start a PayPal checkout payment.
class PaymentRequestMessage {
  PaymentRequestMessage({required this.orderId, this.userAction});

  /// The order ID created on your backend via PayPal Orders API.
  final String orderId;

  /// Defaults to [PaypalUserAction.review] when omitted.
  final PaypalUserAction? userAction;
}

/// Result returned after a payment attempt.
class PaymentResultMessage {
  PaymentResultMessage({
    required this.success,
    this.orderId,
    this.payerId,
    this.errorMessage,
    this.errorCode,
  });

  final bool success;
  final String? orderId;
  final String? payerId;
  final String? errorMessage;
  final String? errorCode;
}

// ─── Card Payments ───

/// A card to use for payment.
class CardBillingAddressMessage {
  CardBillingAddressMessage({
    this.streetAddress,
    this.extendedAddress,
    this.locality,
    this.region,
    this.postalCode,
    this.countryCode,
  });

  final String? streetAddress;
  final String? extendedAddress;
  final String? locality;
  final String? region;
  final String? postalCode;
  final String? countryCode;
}

class CardMessage {
  CardMessage({
    required this.number,
    required this.expirationMonth,
    required this.expirationYear,
    required this.securityCode,
    this.cardholderName,
    this.billingAddress,
  });

  final String number;
  final String expirationMonth;
  final String expirationYear;
  final String securityCode;
  final String? cardholderName;
  final CardBillingAddressMessage? billingAddress;
}

/// Request to approve an order with a card.
class CardPaymentRequestMessage {
  CardPaymentRequestMessage({required this.orderId, required this.card, this.sca});

  final String orderId;
  final CardMessage card;

  /// Strong Customer Authentication preference: "SCA_WHEN_REQUIRED" or "SCA_ALWAYS".
  final String? sca;
}

/// Result after a card payment attempt.
class CardPaymentResultMessage {
  CardPaymentResultMessage({
    required this.success,
    this.orderId,
    this.status,
    this.didAttemptThreeDSecureAuthentication,
    this.errorMessage,
    this.errorCode,
  });

  final bool success;
  final String? orderId;
  final String? status;
  final bool? didAttemptThreeDSecureAuthentication;
  final String? errorMessage;
  final String? errorCode;
}

// ─── Vault ───

/// Request to vault a PayPal account.
class VaultRequestMessage {
  VaultRequestMessage({required this.setupTokenId});

  /// The setup token ID created via PayPal Setup Tokens API.
  final String setupTokenId;
}

/// Result after a vault attempt.
class VaultResultMessage {
  VaultResultMessage({
    required this.success,
    this.setupTokenId,
    this.status,
    this.errorMessage,
    this.errorCode,
  });

  final bool success;
  final String? setupTokenId;
  final String? status;
  final String? errorMessage;
  final String? errorCode;
}

/// Request to vault a card.
class CardVaultRequestMessage {
  CardVaultRequestMessage({required this.setupTokenId, required this.card});

  final String setupTokenId;
  final CardMessage card;
}

/// Host API: Dart calls into native (Kotlin/Swift).
@HostApi()
abstract class PaypalHostApi {
  /// Initialize the PayPal SDK with the given configuration.
  @async
  void initialize(PaypalConfigMessage config);

  /// Start the PayPal checkout flow for the given order.
  @async
  PaymentResultMessage startPayment(PaymentRequestMessage request);

  /// Approve an order with a card (direct card payment).
  @async
  CardPaymentResultMessage startCardPayment(CardPaymentRequestMessage request);

  /// Vault a PayPal account using a setup token.
  @async
  VaultResultMessage startVault(VaultRequestMessage request);

  /// Vault a card using a setup token.
  @async
  VaultResultMessage startCardVault(CardVaultRequestMessage request);
}
