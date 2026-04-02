package com.eerie.cryptkeep

import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.BillingClientStateListener
import com.android.billingclient.api.BillingResult
import com.android.billingclient.api.BillingProgramReportingDetailsParams
import com.android.billingclient.api.BillingProgramReportingDetailsListener
import com.android.billingclient.api.BillingProgramReportingDetails
import com.android.billingclient.api.BillingProgramAvailabilityListener
import com.android.billingclient.api.BillingProgramAvailabilityDetails
import com.android.billingclient.api.LaunchExternalLinkParams
import com.android.billingclient.api.LaunchExternalLinkResponseListener

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.eerie.cryptkeep/external_offers"
    private var billingClient: BillingClient? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "launchExternalOffer" -> {
                    val url = call.argument<String>("url")
                    if (url == null) {
                        result.error("MISSING_URL", "URL is required", null)
                        return@setMethodCallHandler
                    }
                    launchExternalOffer(url, result)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun launchExternalOffer(url: String, result: MethodChannel.Result) {
        val client = BillingClient.newBuilder(this)
            .enableBillingProgram(BillingClient.BillingProgram.EXTERNAL_OFFER)
            .setListener { _, _ -> }
            .build()

        billingClient = client

        client.startConnection(object : BillingClientStateListener {
            override fun onBillingSetupFinished(billingResult: BillingResult) {
                if (billingResult.responseCode != BillingClient.BillingResponseCode.OK) {
                    result.success(mapOf("fallback" to true))
                    client.endConnection()
                    return
                }

                client.isBillingProgramAvailableAsync(
                    BillingClient.BillingProgram.EXTERNAL_OFFER,
                    object : BillingProgramAvailabilityListener {
                        override fun onBillingProgramAvailabilityResponse(
                            billingResult: BillingResult,
                            details: BillingProgramAvailabilityDetails
                        ) {
                            if (billingResult.responseCode != BillingClient.BillingResponseCode.OK) {
                                result.success(mapOf("fallback" to true))
                                client.endConnection()
                                return
                            }

                            val reportingParams = BillingProgramReportingDetailsParams.newBuilder()
                                .setBillingProgram(BillingClient.BillingProgram.EXTERNAL_OFFER)
                                .build()

                            client.createBillingProgramReportingDetailsAsync(
                                reportingParams,
                                object : BillingProgramReportingDetailsListener {
                                    override fun onCreateBillingProgramReportingDetailsResponse(
                                        billingResult: BillingResult,
                                        reportingDetails: BillingProgramReportingDetails?
                                    ) {
                                        if (billingResult.responseCode != BillingClient.BillingResponseCode.OK) {
                                            result.success(mapOf("fallback" to true))
                                            client.endConnection()
                                            return
                                        }

                                        val token = reportingDetails?.externalTransactionToken

                                        val linkParams = LaunchExternalLinkParams.newBuilder()
                                            .setBillingProgram(BillingClient.BillingProgram.EXTERNAL_OFFER)
                                            .setLinkUri(Uri.parse(url))
                                            .build()

                                        client.launchExternalLink(
                                            this@MainActivity,
                                            linkParams,
                                            object : LaunchExternalLinkResponseListener {
                                                override fun onLaunchExternalLinkResponse(billingResult: BillingResult) {
                                                    if (billingResult.responseCode == BillingClient.BillingResponseCode.OK) {
                                                        result.success(mapOf("success" to true, "token" to token))
                                                    } else {
                                                        result.success(mapOf("fallback" to true))
                                                    }
                                                    client.endConnection()
                                                }
                                            }
                                        )
                                    }
                                }
                            )
                        }
                    }
                )
            }

            override fun onBillingServiceDisconnected() {}
        })
    }

    override fun onDestroy() {
        billingClient?.endConnection()
        super.onDestroy()
    }
}
