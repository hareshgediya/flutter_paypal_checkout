import CardPayments
import CorePayments
import Flutter
import PayPalPayments
import UIKit

public class FlutterPaypalCheckoutPlugin: NSObject, FlutterPlugin, FlutterSceneLifeCycleDelegate, PaypalHostApi {
  private var client: PayPalClient?
  private var cardClient: CardClient?
  private var urlConfig: PayPalURLConfig?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = FlutterPaypalCheckoutPlugin()
    PaypalHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: instance)
    registrar.addApplicationDelegate(instance)
    registrar.addSceneDelegate(instance)
  }

  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    PaypalHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: nil)
    client = nil
    cardClient = nil
    urlConfig = nil
  }

  func initialize(config: PaypalConfigMessage) async throws {
    guard let returnURL = URL(string: config.returnUrl),
          let cancelURL = URL(string: config.cancelUrl) else {
      throw PigeonError(
        code: "invalid_url",
        message: "returnUrl and cancelUrl must be valid URLs.",
        details: nil
      )
    }

    let fallbackURL = try fallbackURL(from: config.fallbackSchemeUrl)
    let coreConfig = CoreConfig(
      clientID: config.clientId,
      environment: coreEnvironment(from: config.environment),
      merchantID: config.merchantId,
      bnCode: config.bnCode
    )
    urlConfig = PayPalURLConfig(
      returnAppURL: returnURL,
      cancelAppURL: cancelURL,
      fallbackSchemeURL: fallbackURL
    )
    client = PayPalClient(config: coreConfig)
    cardClient = CardClient(config: coreConfig)
  }

  func startPayment(request: PaymentRequestMessage) async throws -> PaymentResultMessage {
    guard let client, let urlConfig else {
      throw PigeonError(
        code: "not_initialized",
        message: "Call initialize before starting a payment.",
        details: nil
      )
    }

    client.createPayPalSession(
      sessionType: .checkout,
      userIdentity: nil,
      urlConfig: urlConfig,
      userAction: payPalUserAction(from: request.userAction)
    )

    let result: Result<PayPalCheckoutResult, CoreSDKError> = await withCheckedContinuation { continuation in
      client.start(orderID: request.orderId) { result in
        continuation.resume(returning: result)
      }
    }

    switch result {
    case .success(let checkout):
      return PaymentResultMessage(
        success: true,
        orderId: checkout.orderID,
        payerId: checkout.payerID
      )
    case .failure(let error):
      let canceled = PayPalError.isCheckoutCanceled(error)
      return PaymentResultMessage(
        success: false,
        orderId: request.orderId,
        errorMessage: error.errorDescription ?? error.localizedDescription,
        errorCode: canceled ? "canceled" : sdkErrorCode(error)
      )
    }
  }

  func startCardPayment(request: CardPaymentRequestMessage) async throws -> CardPaymentResultMessage {
    guard let cardClient else {
      throw PigeonError(
        code: "not_initialized",
        message: "Call initialize before starting a card payment.",
        details: nil
      )
    }

    let cardRequest = CardRequest(
      orderID: request.orderId,
      card: try makeCard(from: request.card),
      sca: try makeSca(from: request.sca)
    )

    do {
      let result = try await cardClient.approveOrder(request: cardRequest)
      return CardPaymentResultMessage(
        success: true,
        orderId: result.orderID,
        status: result.status,
        didAttemptThreeDSecureAuthentication: result.didAttemptThreeDSecureAuthentication
      )
    } catch {
      let sdkError = error as? CoreSDKError
      let canceled = CardError.isThreeDSecureCanceled(error)
      return CardPaymentResultMessage(
        success: false,
        orderId: request.orderId,
        didAttemptThreeDSecureAuthentication: false,
        errorMessage: sdkError?.errorDescription ?? error.localizedDescription,
        errorCode: canceled ? "canceled" : sdkErrorCode(sdkError)
      )
    }
  }

  func startVault(request _: VaultRequestMessage) async throws -> VaultResultMessage {
    throw unsupported("Vaulting a PayPal account is not supported.")
  }

  func startCardVault(request _: CardVaultRequestMessage) async throws -> VaultResultMessage {
    throw unsupported("Vaulting a card is not supported.")
  }

  public func application(
    _: UIApplication,
    open url: URL,
    options _: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    handleReturn(url: url)
  }

  public func application(
    _: UIApplication,
    continue userActivity: NSUserActivity,
    restorationHandler _: @escaping ([Any]) -> Void
  ) -> Bool {
    handleReturn(userActivity: userActivity)
  }

  public func scene(
    _: UIScene,
    willConnectTo _: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions?
  ) -> Bool {
    var handled = false
    if let connectionOptions {
      for context in connectionOptions.urlContexts where handleReturn(url: context.url) {
        handled = true
      }
      for activity in connectionOptions.userActivities where handleReturn(userActivity: activity) {
        handled = true
      }
    }
    return handled
  }

  public func scene(_: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) -> Bool {
    var handled = false
    for context in URLContexts where handleReturn(url: context.url) {
      handled = true
    }
    return handled
  }

  public func scene(_: UIScene, continue userActivity: NSUserActivity) -> Bool {
    handleReturn(userActivity: userActivity)
  }

  private func handleReturn(userActivity: NSUserActivity) -> Bool {
    guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
          let url = userActivity.webpageURL else {
      return false
    }
    return handleReturn(url: url)
  }

  private func handleReturn(url: URL) -> Bool {
    guard let client, let urlConfig, isPayPalReturn(url, config: urlConfig) else {
      return false
    }
    client.handleReturnURL(url)
    return true
  }

  private func isPayPalReturn(_ url: URL, config: PayPalURLConfig) -> Bool {
    if matches(url, configured: config.returnAppURL) || matches(url, configured: config.cancelAppURL) {
      return true
    }
    if let fallback = config.fallbackSchemeURL, matches(url, configured: fallback) {
      return true
    }
    return false
  }

  private func matches(_ incoming: URL, configured: URL) -> Bool {
    guard incoming.scheme?.lowercased() == configured.scheme?.lowercased() else {
      return false
    }
    guard incoming.host?.lowercased() == configured.host?.lowercased() else {
      return false
    }
    let configuredPath = configured.path
    if configuredPath.isEmpty || configuredPath == "/" {
      return true
    }
    return incoming.path.lowercased().hasPrefix(configuredPath.lowercased())
  }

  private func coreEnvironment(from environment: PaypalEnvironment) -> CoreEnvironment {
    switch environment {
    case .sandbox:
      return .sandbox
    case .live:
      return .live
    }
  }

  private func payPalUserAction(from action: PaypalUserAction?) -> PayPalUserAction {
    switch action {
    case .payNow:
      return .payNow
    case .review, .none:
      return .continue
    }
  }

  private func fallbackURL(from value: String?) throws -> URL? {
    guard let value, !value.isEmpty else {
      return nil
    }
    guard let url = URL(string: value) else {
      throw PigeonError(
        code: "invalid_url",
        message: "fallbackSchemeUrl must be a valid URL.",
        details: nil
      )
    }
    return url
  }

  private func makeCard(from message: CardMessage) throws -> Card {
    let number = message.number.filter(\.isNumber)
    guard !number.isEmpty else {
      throw PigeonError(code: "invalid_card", message: "Card number is required.", details: nil)
    }
    guard message.expirationMonth.count == 2, message.expirationYear.count == 4 else {
      throw PigeonError(code: "invalid_card", message: "Expiration must be MM and YYYY.", details: nil)
    }
    guard !message.securityCode.isEmpty else {
      throw PigeonError(code: "invalid_card", message: "Security code is required.", details: nil)
    }

    return Card(
      number: number,
      expirationMonth: message.expirationMonth,
      expirationYear: message.expirationYear,
      securityCode: message.securityCode,
      cardholderName: message.cardholderName,
      billingAddress: makeAddress(from: message.billingAddress)
    )
  }

  private func makeAddress(from message: CardBillingAddressMessage?) -> Address? {
    guard let message, let countryCode = message.countryCode, !countryCode.isEmpty else {
      return nil
    }
    return Address(
      addressLine1: message.streetAddress,
      addressLine2: message.extendedAddress,
      locality: message.locality,
      region: message.region,
      postalCode: message.postalCode,
      countryCode: countryCode
    )
  }

  private func makeSca(from value: String?) throws -> SCA {
    switch value {
    case nil, "", "SCA_WHEN_REQUIRED":
      return .scaWhenRequired
    case "SCA_ALWAYS":
      return .scaAlways
    default:
      throw PigeonError(
        code: "invalid_sca",
        message: "sca must be SCA_ALWAYS or SCA_WHEN_REQUIRED.",
        details: nil
      )
    }
  }

  private func sdkErrorCode(_ error: CoreSDKError?) -> String {
    if let code = error?.code {
      return String(code)
    }
    return "unknown"
  }

  private func unsupported(_ message: String) -> PigeonError {
    PigeonError(code: "unimplemented", message: message, details: nil)
  }
}
