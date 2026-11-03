package io.github.giuseppescardino.arcanum

import android.app.LocaleManager
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.LocaleList
import android.provider.Settings
import android.view.autofill.AutofillManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FragmentActivity is required by the biometric prompt (local_auth and
// flutter_secure_storage's Keystore-bound biometric storage).
class MainActivity : FlutterFragmentActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pm/platform")
            .setMethodCallHandler { call, result ->
                val autofill = getSystemService(AutofillManager::class.java)
                when (call.method) {
                    "isAutofillEnabled" -> result.success(autofill?.hasEnabledAutofillServices() == true)
                    "openAutofillSettings" -> {
                        // Asks the user to pick this app as autofill service.
                        startActivity(
                            Intent(Settings.ACTION_REQUEST_SET_AUTOFILL_SERVICE)
                                .setData(Uri.parse("package:$packageName")),
                        )
                        result.success(null)
                    }
                    "setAppLanguage" -> {
                        // Android 13+: the in-app choice becomes the per-app
                        // language, so the autofill entry follows it too.
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            val code = call.argument<String>("code")
                            getSystemService(LocaleManager::class.java).applicationLocales =
                                if (code == null) LocaleList.getEmptyLocaleList() else LocaleList.forLanguageTags(code)
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
