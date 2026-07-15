package com.eerie.cryptkeep

import io.flutter.embedding.android.FlutterFragmentActivity

/// Launched by the autofill service when the user taps the CryptKeep entry in
/// another app's autofill popup. Runs the `autofillEntryPoint` Dart entrypoint
/// (unlock -> match -> return credentials) instead of the normal app.
///
/// Must be a FlutterFragmentActivity so the biometric prompt can show here.
class AutofillActivity : FlutterFragmentActivity() {
    override fun getDartEntrypointFunctionName(): String = "autofillEntryPoint"
}
