package com.flutter_paypal_checkout

import android.content.Intent
import com.flutter_paypal_checkout.generated.CardBillingAddressMessage
import com.flutter_paypal_checkout.generated.CardMessage
import com.flutter_paypal_checkout.generated.CardPaymentRequestMessage
import com.flutter_paypal_checkout.generated.CardPaymentResultMessage
import com.flutter_paypal_checkout.generated.CardVaultRequestMessage
import com.flutter_paypal_checkout.generated.FlutterError
import com.flutter_paypal_checkout.generated.PaymentRequestMessage
import com.flutter_paypal_checkout.generated.PaymentResultMessage
import com.flutter_paypal_checkout.generated.PaypalConfigMessage
import com.flutter_paypal_checkout.generated.PaypalEnvironment
import com.flutter_paypal_checkout.generated.PaypalHostApi
import com.flutter_paypal_checkout.generated.PaypalUserAction
import com.flutter_paypal_checkout.generated.VaultRequestMessage
import com.flutter_paypal_checkout.generated.VaultResultMessage
import com.paypal.android.cardpayments.Card
import com.paypal.android.cardpayments.CardApproveOrderCallback
import com.paypal.android.cardpayments.CardApproveOrderResult
import com.paypal.android.cardpayments.CardClient
import com.paypal.android.cardpayments.CardFinishApproveOrderResult
import com.paypal.android.cardpayments.CardPresentAuthChallengeResult
import com.paypal.android.cardpayments.CardRequest
import com.paypal.android.cardpayments.threedsecure.SCA
import com.paypal.android.corepayments.Address
import com.paypal.android.corepayments.CoreConfig
import com.paypal.android.corepayments.CoreEnvironment
import com.paypal.android.corepayments.PayPalSDKError
import com.paypal.android.corepayments.model.TokenType
import com.paypal.android.paypalpayments.PayPalClient
import com.paypal.android.paypalpayments.PayPalFinishStartResult
import com.paypal.android.paypalpayments.PayPalPresentAuthChallengeResult
import com.paypal.android.paypalpayments.PayPalResultCallback
import com.paypal.android.paypalpayments.PayPalUserAction
import com.paypal.android.paypalpayments.ReturnToAppUrlConfig
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.PluginRegistry
import kotlinx.coroutines.CompletableDeferred

class FlutterPaypalCheckoutPlugin :
    FlutterPlugin,
    ActivityAware,
    PluginRegistry.NewIntentListener,
    PaypalHostApi {
    private var activityBinding: ActivityPluginBinding? = null
    private var applicationContext: android.content.Context? = null
    private var paypalClient: PayPalClient? = null
    private var cardClient: CardClient? = null
    private var urlConfig: ReturnToAppUrlConfig? = null
    private var cardReturnUrl: String? = null
    private var paymentResult: CompletableDeferred<PaymentResultMessage>? = null
    private var cardResult: CompletableDeferred<CardPaymentResultMessage>? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext
        PaypalHostApi.setUp(binding.binaryMessenger, this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        PaypalHostApi.setUp(binding.binaryMessenger, null)
        applicationContext = null
        paypalClient = null
        cardClient = null
        urlConfig = null
        cardReturnUrl = null
        paymentResult?.cancel()
        cardResult?.cancel()
        paymentResult = null
        cardResult = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        attachActivity(binding)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        detachActivity()
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        attachActivity(binding)
    }

    override fun onDetachedFromActivity() {
        detachActivity()
    }

    override suspend fun initialize(config: PaypalConfigMessage) {
        val context = applicationContext
            ?: throw FlutterError("not_initialized", "Android context is unavailable.")
        if (config.returnUrl.isBlank() || config.cancelUrl.isBlank()) {
            throw FlutterError("invalid_url", "returnUrl and cancelUrl must be valid URLs.")
        }
        val fallbackSchemeUrl = config.fallbackSchemeUrl?.takeIf { it.isNotBlank() }
            ?: throw FlutterError(
                "invalid_url",
                "fallbackSchemeUrl is required so Android can return from PayPal and 3D Secure.",
            )

        val coreConfig = CoreConfig(
            clientId = config.clientId,
            merchantId = config.merchantId,
            coreEnvironment = when (config.environment) {
                PaypalEnvironment.SANDBOX -> CoreEnvironment.SANDBOX
                PaypalEnvironment.LIVE -> CoreEnvironment.LIVE
            },
            bnCode = config.bnCode,
        )
        urlConfig = ReturnToAppUrlConfig(
            returnAppUrl = config.returnUrl,
            cancelAppUrl = config.cancelUrl,
            fallbackSchemeUrl = fallbackSchemeUrl,
        )
        cardReturnUrl = fallbackSchemeUrl
        paypalClient = PayPalClient(context, coreConfig)
        cardClient = CardClient(context, coreConfig)
    }

    override suspend fun startPayment(request: PaymentRequestMessage): PaymentResultMessage {
        val client = paypalClient
            ?: throw FlutterError("not_initialized", "Call initialize before starting a payment.")
        val config = urlConfig
            ?: throw FlutterError("not_initialized", "Call initialize before starting a payment.")
        val activity = activityBinding?.activity
            ?: throw FlutterError("no_activity", "A foreground activity is required to start checkout.")
        if (paymentResult?.isActive == true) {
            throw FlutterError("payment_in_progress", "A PayPal checkout is already in progress.")
        }

        val deferred = CompletableDeferred<PaymentResultMessage>()
        paymentResult = deferred
        client.createPayPalSession(
            tokenType = TokenType.ORDER_ID,
            userIdentity = null,
            urlConfig = config,
            userAction = when (request.userAction) {
                PaypalUserAction.PAY_NOW -> PayPalUserAction.PAY_NOW
                PaypalUserAction.REVIEW, null -> PayPalUserAction.CONTINUE
            },
        )
        client.start(
            activity,
            request.orderId,
            PayPalResultCallback { result ->
                if (result is PayPalPresentAuthChallengeResult.Failure) {
                    finishPayment(
                        PaymentResultMessage(
                            success = false,
                            orderId = request.orderId,
                            errorMessage = result.error.errorDescription,
                            errorCode = result.error.code.toString(),
                        ),
                    )
                }
            },
        )
        return deferred.await()
    }

    override suspend fun startCardPayment(request: CardPaymentRequestMessage): CardPaymentResultMessage {
        val client = cardClient
            ?: throw FlutterError("not_initialized", "Call initialize before starting a card payment.")
        val activity = activityBinding?.activity
            ?: throw FlutterError("no_activity", "A foreground activity is required to start checkout.")
        val returnUrl = cardReturnUrl
            ?: throw FlutterError("invalid_url", "fallbackSchemeUrl is required for 3D Secure.")
        if (cardResult?.isActive == true) {
            throw FlutterError("payment_in_progress", "A card payment is already in progress.")
        }

        val deferred = CompletableDeferred<CardPaymentResultMessage>()
        cardResult = deferred
        client.approveOrder(
            CardRequest(
                orderId = request.orderId,
                card = makeCard(request.card),
                returnUrl = returnUrl,
                sca = makeSca(request.sca),
            ),
            CardApproveOrderCallback { result ->
                when (result) {
                    is CardApproveOrderResult.Success -> finishCard(
                        CardPaymentResultMessage(
                            success = true,
                            orderId = result.orderId,
                            status = result.status,
                            didAttemptThreeDSecureAuthentication = result.didAttemptThreeDSecureAuthentication,
                        ),
                    )

                    is CardApproveOrderResult.AuthorizationRequired -> {
                        when (val presented = client.presentAuthChallenge(activity, result.authChallenge)) {
                            is CardPresentAuthChallengeResult.Success -> Unit
                            is CardPresentAuthChallengeResult.Failure -> finishCard(
                                cardFailure(request.orderId, presented.error),
                            )
                        }
                    }

                    is CardApproveOrderResult.Failure -> finishCard(cardFailure(request.orderId, result.error))
                }
            },
        )
        return deferred.await()
    }

    override suspend fun startVault(request: VaultRequestMessage): VaultResultMessage {
        throw FlutterError("unimplemented", "Vaulting a PayPal account is not supported.")
    }

    override suspend fun startCardVault(request: CardVaultRequestMessage): VaultResultMessage {
        throw FlutterError("unimplemented", "Vaulting a card is not supported.")
    }

    override fun onNewIntent(intent: Intent): Boolean = handleReturn(intent)

    private fun attachActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addOnNewIntentListener(this)
    }

    private fun detachActivity() {
        activityBinding?.removeOnNewIntentListener(this)
        activityBinding = null
    }

    private fun handleReturn(intent: Intent): Boolean {
        if (paymentResult?.isActive == true) {
            when (val result = paypalClient?.finishStart(intent)) {
                is PayPalFinishStartResult.Success -> {
                    finishPayment(
                        PaymentResultMessage(
                            success = true,
                            orderId = result.orderId,
                            payerId = result.payerId,
                        ),
                    )
                    return true
                }

                is PayPalFinishStartResult.Canceled -> {
                    finishPayment(
                        PaymentResultMessage(
                            success = false,
                            orderId = result.orderId,
                            errorMessage = "PayPal checkout has been canceled by the user",
                            errorCode = "canceled",
                        ),
                    )
                    return true
                }

                is PayPalFinishStartResult.Failure -> {
                    finishPayment(
                        PaymentResultMessage(
                            success = false,
                            orderId = result.orderId,
                            errorMessage = result.error.errorDescription,
                            errorCode = result.error.code.toString(),
                        ),
                    )
                    return true
                }

                PayPalFinishStartResult.NoResult, null -> Unit
            }
        }

        if (cardResult?.isActive == true) {
            when (val result = cardClient?.finishApproveOrder(intent)) {
                is CardFinishApproveOrderResult.Success -> {
                    finishCard(
                        CardPaymentResultMessage(
                            success = true,
                            orderId = result.orderId,
                            status = result.status,
                            didAttemptThreeDSecureAuthentication = true,
                        ),
                    )
                    return true
                }

                is CardFinishApproveOrderResult.Failure -> {
                    finishCard(cardFailure(null, result.error))
                    return true
                }

                CardFinishApproveOrderResult.Canceled -> {
                    finishCard(
                        CardPaymentResultMessage(
                            success = false,
                            didAttemptThreeDSecureAuthentication = false,
                            errorMessage = "3DS verification has been canceled by the user.",
                            errorCode = "canceled",
                        ),
                    )
                    return true
                }

                CardFinishApproveOrderResult.NoResult, null -> Unit
            }
        }
        return false
    }

    private fun finishPayment(result: PaymentResultMessage) {
        val deferred = paymentResult
        paymentResult = null
        if (deferred?.isActive == true) {
            deferred.complete(result)
        }
    }

    private fun finishCard(result: CardPaymentResultMessage) {
        val deferred = cardResult
        cardResult = null
        if (deferred?.isActive == true) {
            deferred.complete(result)
        }
    }

    private fun makeCard(message: CardMessage): Card {
        val number = message.number.filter { it.isDigit() }
        if (number.isEmpty()) {
            throw FlutterError("invalid_card", "Card number is required.")
        }
        if (message.expirationMonth.length != 2 || message.expirationYear.length != 4) {
            throw FlutterError("invalid_card", "Expiration must be MM and YYYY.")
        }
        if (message.securityCode.isEmpty()) {
            throw FlutterError("invalid_card", "Security code is required.")
        }
        return Card(
            number = number,
            expirationMonth = message.expirationMonth,
            expirationYear = message.expirationYear,
            securityCode = message.securityCode,
            cardholderName = message.cardholderName,
            billingAddress = makeAddress(message.billingAddress),
        )
    }

    private fun makeAddress(message: CardBillingAddressMessage?): Address? {
        val countryCode = message?.countryCode?.takeIf { it.isNotEmpty() } ?: return null
        return Address(
            countryCode = countryCode,
            streetAddress = message.streetAddress,
            extendedAddress = message.extendedAddress,
            locality = message.locality,
            region = message.region,
            postalCode = message.postalCode,
        )
    }

    private fun makeSca(value: String?): SCA {
        return when (value) {
            null, "", "SCA_WHEN_REQUIRED" -> SCA.SCA_WHEN_REQUIRED
            "SCA_ALWAYS" -> SCA.SCA_ALWAYS
            else -> throw FlutterError("invalid_sca", "sca must be SCA_ALWAYS or SCA_WHEN_REQUIRED.")
        }
    }

    private fun cardFailure(orderId: String?, error: PayPalSDKError): CardPaymentResultMessage {
        return CardPaymentResultMessage(
            success = false,
            orderId = orderId,
            didAttemptThreeDSecureAuthentication = false,
            errorMessage = error.errorDescription,
            errorCode = error.code.toString(),
        )
    }
}
