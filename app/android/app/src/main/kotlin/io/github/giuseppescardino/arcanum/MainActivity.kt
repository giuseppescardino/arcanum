package io.github.giuseppescardino.arcanum

import android.app.LocaleManager
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.LocaleList
import android.provider.Settings
import android.view.autofill.AutofillManager
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FragmentActivity is required by the biometric prompt (local_auth and
// flutter_secure_storage's Keystore-bound biometric storage).
class MainActivity : FlutterFragmentActivity() {

    /// Export waiting for the user to pick where the document goes.
    private var pendingSave: Pair<ByteArray, MethodChannel.Result>? = null

    private val createDocument =
        registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { outcome ->
            val (bytes, result) = pendingSave ?: return@registerForActivityResult
            pendingSave = null
            val uri = outcome.data?.data
            if (outcome.resultCode != RESULT_OK || uri == null) {
                result.success(false)
                return@registerForActivityResult
            }
            try {
                val stream = contentResolver.openOutputStream(uri)
                    ?: throw java.io.IOException("cannot open $uri")
                stream.use { it.write(bytes) }
                result.success(true)
            } catch (e: Exception) {
                result.error("save_failed", e.message, null)
            }
        }

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
                    "saveFile" -> {
                        // Storage Access Framework: no storage permission,
                        // the user chooses the destination.
                        val bytes = call.argument<ByteArray>("bytes")
                        if (bytes == null || pendingSave != null) {
                            result.error("save_failed", "invalid request", null)
                        } else {
                            pendingSave = bytes to result
                            createDocument.launch(
                                Intent(Intent.ACTION_CREATE_DOCUMENT)
                                    .addCategory(Intent.CATEGORY_OPENABLE)
                                    .setType(call.argument<String>("mimeType") ?: "application/octet-stream")
                                    .putExtra(Intent.EXTRA_TITLE, call.argument<String>("name")),
                            )
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
