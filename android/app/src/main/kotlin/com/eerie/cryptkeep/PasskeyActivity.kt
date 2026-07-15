package com.eerie.cryptkeep

import android.app.Activity
import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.util.Base64
import android.util.Log
import androidx.annotation.RequiresApi
import androidx.credentials.CreatePublicKeyCredentialRequest
import androidx.credentials.CreatePublicKeyCredentialResponse
import androidx.credentials.GetCredentialResponse
import androidx.credentials.PublicKeyCredential
import androidx.credentials.exceptions.CreateCredentialCancellationException
import androidx.credentials.exceptions.GetCredentialCancellationException
import androidx.credentials.provider.BeginGetCredentialResponse
import androidx.credentials.provider.BeginGetPublicKeyCredentialOption
import androidx.credentials.provider.CallingAppInfo
import androidx.credentials.provider.PendingIntentHandler
import androidx.credentials.provider.PublicKeyCredentialEntry
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.security.MessageDigest
import java.util.concurrent.atomic.AtomicInteger

/**
 * Handles every passkey flow the platform hands us. The vault (and so the key
 * material) lives on the Dart side, so this class stays a thin shim: it unpacks
 * the platform's request, hands the parts to Dart, and posts back what Dart
 * built.
 *
 * Three flows arrive here, by intent action:
 *  - CREATE_PASSKEY: save a new passkey.
 *  - UNLOCK_PASSKEY: the vault is locked, so we could not tell the platform
 *    which passkeys exist. Unlock, then answer with the real entries.
 *  - GET_PASSKEY: the user picked one of those entries; sign the challenge.
 *
 * FlutterFragmentActivity, not FlutterActivity: biometric prompts need it.
 */
class PasskeyActivity : FlutterFragmentActivity() {

    companion object {
        private const val CHANNEL = "cryptkeep/passkey"
        private const val TAG = "CryptKeepPasskey"

        const val EXTRA_CREDENTIAL_ID = "cryptkeep_credential_id"

        // Google's openly published list of browsers allowed to call on a
        // website's behalf. Bundled rather than fetched so a passkey never
        // depends on reaching gstatic; refresh it with app releases.
        // Source: https://www.gstatic.com/gpm-passkeys-privileged-apps/apps.json
        private const val PRIVILEGED_APPS_ASSET = "passkey_privileged_apps.json"

        private val requestCode = AtomicInteger(1000)
    }

    override fun getDartEntrypointFunctionName(): String = "passkeyEntryPoint"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getRequest" -> result.success(requestPayload())
                    "completeCreate" -> {
                        val json = call.argument<String>("responseJson")
                        if (json == null) {
                            result.error("no_response", "responseJson missing", null)
                        } else {
                            completeCreate(json)
                            result.success(true)
                        }
                    }
                    "completeUnlock" -> {
                        val passkeys = call.argument<List<Map<String, String>>>("passkeys")
                        completeUnlock(passkeys ?: emptyList())
                        result.success(true)
                    }
                    "completeGet" -> {
                        val json = call.argument<String>("responseJson")
                        if (json == null) {
                            result.error("no_response", "responseJson missing", null)
                        } else {
                            completeGet(json)
                            result.success(true)
                        }
                    }
                    "cancel" -> {
                        cancel()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /** Describes whichever flow we were launched for, for the Dart side. */
    @RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
    private fun requestPayload(): Map<String, Any?>? = when (intent.action) {
        PasskeyProviderService.ACTION_CREATE_PASSKEY -> createPayload()
        PasskeyProviderService.ACTION_UNLOCK_PASSKEY -> unlockPayload()
        PasskeyProviderService.ACTION_GET_PASSKEY -> getPayload()
        else -> null
    }

    // ─────────────────────────── create ───────────────────────────

    @RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
    private fun createPayload(): Map<String, Any?>? {
        val request = PendingIntentHandler
            .retrieveProviderCreateCredentialRequest(intent) ?: return null
        val callingRequest =
            request.callingRequest as? CreatePublicKeyCredentialRequest ?: return null

        val json = JSONObject(callingRequest.requestJson)
        val rp = json.getJSONObject("rp")
        val user = json.getJSONObject("user")

        val claimsOrigin = callingRequest.clientDataHash != null
        val trustedOrigin = if (claimsOrigin) trustedOriginFor(request.callingAppInfo) else null

        Log.i(
            TAG,
            "CRYPTKEEP_PASSKEY create from=${request.callingAppInfo.packageName} " +
                "rpId=${rp.getString("id")} claimsOrigin=$claimsOrigin trusted=$trustedOrigin",
        )

        if (claimsOrigin && trustedOrigin == null) {
            Log.w(TAG, "CRYPTKEEP_PASSKEY refusing untrusted origin claim")
            return null
        }

        val clientDataJson = JSONObject().apply {
            put("type", "webauthn.create")
            put("challenge", json.getString("challenge"))
            put("origin", trustedOrigin ?: originFor(request.callingAppInfo))
            put("androidPackageName", request.callingAppInfo.packageName)
        }.toString()

        return mapOf(
            "mode" to "create",
            "rpId" to rp.getString("id"),
            "rpName" to rp.optString("name", rp.getString("id")),
            "userName" to user.optString("name", ""),
            "userHandle" to user.getString("id"),
            "clientDataJson" to clientDataJson,
            "includeClientDataJson" to (trustedOrigin == null),
        )
    }

    @RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
    private fun completeCreate(responseJson: String) {
        val result = Intent()
        try {
            PendingIntentHandler.setCreateCredentialResponse(
                result,
                CreatePublicKeyCredentialResponse(responseJson),
            )
            Log.i(TAG, "CRYPTKEEP_PASSKEY create response accepted, len=${responseJson.length}")
        } catch (e: Throwable) {
            // Never swallow this: a rejected response is exactly the failure
            // the caller reports as a useless "unknown error".
            Log.e(TAG, "CRYPTKEEP_PASSKEY create response rejected: $responseJson", e)
            throw e
        }
        setResult(Activity.RESULT_OK, result)
        finish()
    }

    // ─────────────────────────── unlock (list) ───────────────────────────

    /** Which site the platform is asking about, so Dart can find matches. */
    @RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
    private fun unlockPayload(): Map<String, Any?>? {
        val request = PendingIntentHandler
            .retrieveBeginGetCredentialRequest(intent) ?: return null
        val option = request.beginGetCredentialOptions
            .filterIsInstance<BeginGetPublicKeyCredentialOption>()
            .firstOrNull() ?: return null

        val rpId = JSONObject(option.requestJson).optString("rpId", "")
        Log.i(TAG, "CRYPTKEEP_PASSKEY unlock rpId=$rpId")

        return mapOf("mode" to "unlock", "rpId" to rpId)
    }

    /**
     * Answers the question we could not answer while locked: here are the
     * passkeys for this site. Each gets its own PendingIntent so picking one
     * comes back to us as GET_PASSKEY.
     */
    @RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
    private fun completeUnlock(passkeys: List<Map<String, String>>) {
        val request = PendingIntentHandler.retrieveBeginGetCredentialRequest(intent)
        val option = request?.beginGetCredentialOptions
            ?.filterIsInstance<BeginGetPublicKeyCredentialOption>()
            ?.firstOrNull()

        val result = Intent()
        if (option == null) {
            Log.w(TAG, "CRYPTKEEP_PASSKEY unlock without a passkey option")
            setResult(Activity.RESULT_CANCELED)
            finish()
            return
        }

        val entries = passkeys.map { passkey ->
            val credentialId = passkey["credentialId"] ?: ""
            PublicKeyCredentialEntry.Builder(
                applicationContext,
                passkey["username"].orEmpty().ifEmpty { "Passkey" },
                signPendingIntent(credentialId),
                option,
            ).build()
        }

        Log.i(TAG, "CRYPTKEEP_PASSKEY unlock returning ${entries.size} entries")
        PendingIntentHandler.setBeginGetCredentialResponse(
            result,
            BeginGetCredentialResponse.Builder().setCredentialEntries(entries).build(),
        )
        setResult(Activity.RESULT_OK, result)
        finish()
    }

    private fun signPendingIntent(credentialId: String): PendingIntent {
        val intent = Intent(PasskeyProviderService.ACTION_GET_PASSKEY)
            .setPackage(packageName)
            .putExtras(Bundle().apply { putString(EXTRA_CREDENTIAL_ID, credentialId) })
        return PendingIntent.getActivity(
            this,
            requestCode.getAndIncrement(),
            intent,
            PendingIntent.FLAG_MUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }

    // ─────────────────────────── get (sign) ───────────────────────────

    @RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
    private fun getPayload(): Map<String, Any?>? {
        val request = PendingIntentHandler
            .retrieveProviderGetCredentialRequest(intent) ?: return null
        val option = request.credentialOptions
            .filterIsInstance<androidx.credentials.GetPublicKeyCredentialOption>()
            .firstOrNull() ?: return null

        val json = JSONObject(option.requestJson)
        val rpId = json.optString("rpId", "")

        val claimsOrigin = option.clientDataHash != null
        val trustedOrigin = if (claimsOrigin) trustedOriginFor(request.callingAppInfo) else null

        Log.i(
            TAG,
            "CRYPTKEEP_PASSKEY get from=${request.callingAppInfo.packageName} " +
                "rpId=$rpId claimsOrigin=$claimsOrigin trusted=$trustedOrigin",
        )

        if (claimsOrigin && trustedOrigin == null) {
            Log.w(TAG, "CRYPTKEEP_PASSKEY refusing untrusted origin claim")
            return null
        }

        val clientDataJson = JSONObject().apply {
            put("type", "webauthn.get")
            put("challenge", json.getString("challenge"))
            put("origin", trustedOrigin ?: originFor(request.callingAppInfo))
            put("androidPackageName", request.callingAppInfo.packageName)
        }.toString()

        return mapOf(
            "mode" to "get",
            "rpId" to rpId,
            "credentialId" to intent.getStringExtra(EXTRA_CREDENTIAL_ID),
            "clientDataJson" to clientDataJson,
            "includeClientDataJson" to (trustedOrigin == null),
            // Signed as-is when a browser supplies it, so the signature matches
            // the client data the site actually receives.
            "clientDataHash" to option.clientDataHash,
        )
    }

    @RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
    private fun completeGet(responseJson: String) {
        val result = Intent()
        try {
            PendingIntentHandler.setGetCredentialResponse(
                result,
                GetCredentialResponse(PublicKeyCredential(responseJson)),
            )
            Log.i(TAG, "CRYPTKEEP_PASSKEY get response accepted, len=${responseJson.length}")
        } catch (e: Throwable) {
            Log.e(TAG, "CRYPTKEEP_PASSKEY get response rejected: $responseJson", e)
            throw e
        }
        setResult(Activity.RESULT_OK, result)
        finish()
    }

    // ─────────────────────────── shared ───────────────────────────

    /**
     * The website origin a browser is calling for, or null if the caller is not
     * a browser we trust to make that claim.
     */
    private fun trustedOriginFor(info: CallingAppInfo): String? = try {
        info.getOrigin(
            assets.open(PRIVILEGED_APPS_ASSET).bufferedReader().use { it.readText() },
        )
    } catch (e: Throwable) {
        Log.w(TAG, "CRYPTKEEP_PASSKEY could not resolve privileged origin", e)
        null
    }

    /**
     * The WebAuthn origin for a native caller: a hash of the signing
     * certificate, so a different app cannot claim to be this one.
     */
    private fun originFor(info: CallingAppInfo): String {
        val cert = info.signingInfo.apkContentsSigners[0].toByteArray()
        val hash = MessageDigest.getInstance("SHA-256").digest(cert)
        val encoded =
            Base64.encodeToString(hash, Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP)
        return "android:apk-key-hash:$encoded"
    }

    @RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
    private fun cancel() {
        val result = Intent()
        if (intent.action == PasskeyProviderService.ACTION_CREATE_PASSKEY) {
            PendingIntentHandler.setCreateCredentialException(
                result,
                CreateCredentialCancellationException(),
            )
        } else {
            PendingIntentHandler.setGetCredentialException(
                result,
                GetCredentialCancellationException(),
            )
        }
        setResult(Activity.RESULT_OK, result)
        finish()
    }
}
