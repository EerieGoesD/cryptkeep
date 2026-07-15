package com.eerie.cryptkeep

import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import android.os.CancellationSignal
import android.os.OutcomeReceiver
import androidx.annotation.RequiresApi
import androidx.credentials.exceptions.ClearCredentialException
import androidx.credentials.exceptions.CreateCredentialException
import androidx.credentials.exceptions.CreateCredentialUnknownException
import androidx.credentials.exceptions.GetCredentialException
import androidx.credentials.provider.AuthenticationAction
import androidx.credentials.provider.BeginCreateCredentialRequest
import androidx.credentials.provider.BeginCreateCredentialResponse
import androidx.credentials.provider.BeginCreatePublicKeyCredentialRequest
import androidx.credentials.provider.BeginGetCredentialRequest
import androidx.credentials.provider.BeginGetCredentialResponse
import androidx.credentials.provider.BeginGetPublicKeyCredentialOption
import androidx.credentials.provider.CreateEntry
import androidx.credentials.provider.CredentialProviderService
import androidx.credentials.provider.ProviderClearCredentialStateRequest
import java.util.concurrent.atomic.AtomicInteger

/**
 * Makes CryptKeep selectable as a passkey provider (Android 14+ only; the
 * platform never binds this below that, which is why minSdk stays at 29).
 *
 * This class only answers "can you save a passkey?" and "do you have one?".
 * The real work happens in [PasskeyActivity], which the returned PendingIntent
 * launches once the user picks CryptKeep - only there can we unlock the vault.
 */
@RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
class PasskeyProviderService : CredentialProviderService() {

    companion object {
        const val ACTION_CREATE_PASSKEY = "com.eerie.cryptkeep.CREATE_PASSKEY"
        const val ACTION_UNLOCK_PASSKEY = "com.eerie.cryptkeep.UNLOCK_PASSKEY"
        const val ACTION_GET_PASSKEY = "com.eerie.cryptkeep.GET_PASSKEY"

        // Each entry needs its own request code, or PendingIntents collide.
        private val requestCode = AtomicInteger(0)
    }

    override fun onBeginCreateCredentialRequest(
        request: BeginCreateCredentialRequest,
        cancellationSignal: CancellationSignal,
        callback: OutcomeReceiver<BeginCreateCredentialResponse, CreateCredentialException>,
    ) {
        if (request is BeginCreatePublicKeyCredentialRequest) {
            callback.onResult(
                BeginCreateCredentialResponse(
                    listOf(CreateEntry("CryptKeep", createPendingIntent(ACTION_CREATE_PASSKEY)))
                )
            )
            return
        }
        // Passwords are handled by the autofill service, not here.
        callback.onError(CreateCredentialUnknownException())
    }

    override fun onBeginGetCredentialRequest(
        request: BeginGetCredentialRequest,
        cancellationSignal: CancellationSignal,
        callback: OutcomeReceiver<BeginGetCredentialResponse, GetCredentialException>,
    ) {
        val wantsPasskey = request.beginGetCredentialOptions
            .any { it is BeginGetPublicKeyCredentialOption }
        if (!wantsPasskey) {
            callback.onResult(BeginGetCredentialResponse())
            return
        }

        // The vault is encrypted, so we genuinely cannot say which passkeys
        // exist until the user unlocks it - listing them here would mean
        // keeping site names readable outside the vault. Offer an unlock step
        // instead; PasskeyActivity answers with the real entries afterwards.
        callback.onResult(
            BeginGetCredentialResponse.Builder()
                .setAuthenticationActions(
                    listOf(
                        AuthenticationAction(
                            "Unlock CryptKeep",
                            createPendingIntent(ACTION_UNLOCK_PASSKEY),
                        ),
                    ),
                )
                .build(),
        )
    }

    override fun onClearCredentialStateRequest(
        request: ProviderClearCredentialStateRequest,
        cancellationSignal: CancellationSignal,
        callback: OutcomeReceiver<Void?, ClearCredentialException>,
    ) {
        // No sticky selection state is kept.
        callback.onResult(null)
    }

    private fun createPendingIntent(action: String): PendingIntent {
        val intent = Intent(action).setPackage(packageName)
        return PendingIntent.getActivity(
            this,
            requestCode.getAndIncrement(),
            intent,
            // MUTABLE is required: the platform adds the request to this intent.
            PendingIntent.FLAG_MUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }
}
