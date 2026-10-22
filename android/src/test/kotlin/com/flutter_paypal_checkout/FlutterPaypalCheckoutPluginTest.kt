package com.flutter_paypal_checkout

import com.flutter_paypal_checkout.generated.FlutterError
import com.flutter_paypal_checkout.generated.VaultRequestMessage
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlinx.coroutines.runBlocking

internal class FlutterPaypalCheckoutPluginTest {
    @Test
    fun startVaultIsUnsupported() = runBlocking {
        val plugin = FlutterPaypalCheckoutPlugin()

        val error = assertFailsWith<FlutterError> {
            plugin.startVault(VaultRequestMessage("setup-token"))
        }

        assertEquals("unimplemented", error.code)
    }
}
