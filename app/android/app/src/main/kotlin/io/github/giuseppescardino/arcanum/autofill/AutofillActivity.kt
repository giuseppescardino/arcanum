package io.github.giuseppescardino.arcanum.autofill

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.service.autofill.Dataset
import android.view.autofill.AutofillId
import android.view.autofill.AutofillManager
import android.view.autofill.AutofillValue
import android.widget.RemoteViews
import io.github.giuseppescardino.arcanum.R
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts the Flutter `autofillMain` entrypoint: unlock + pick a credential.
 * The chosen username/password come back over the `pm/autofill` channel
 * and are returned to the requesting app as a single Dataset.
 */
class AutofillActivity : FlutterFragmentActivity() {

    companion object {
        const val EXTRA_USERNAME_IDS = "pm.autofill.username_ids"
        const val EXTRA_PASSWORD_IDS = "pm.autofill.password_ids"
        const val EXTRA_PACKAGE = "pm.autofill.package"
        const val EXTRA_WEB_DOMAIN = "pm.autofill.web_domain"
        private const val CHANNEL = "pm/autofill"
    }

    private var usernameIds: List<AutofillId> = emptyList()
    private var passwordIds: List<AutofillId> = emptyList()
    private var requestingPackage: String = ""
    private var webDomain: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        @Suppress("DEPRECATION")
        usernameIds = intent.getParcelableArrayListExtra<AutofillId>(EXTRA_USERNAME_IDS).orEmpty()
        @Suppress("DEPRECATION")
        passwordIds = intent.getParcelableArrayListExtra<AutofillId>(EXTRA_PASSWORD_IDS).orEmpty()
        requestingPackage = intent.getStringExtra(EXTRA_PACKAGE).orEmpty()
        webDomain = intent.getStringExtra(EXTRA_WEB_DOMAIN)
        setResult(Activity.RESULT_CANCELED)
        super.onCreate(savedInstanceState)
    }

    override fun getDartEntrypointFunctionName(): String = "autofillMain"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "request" -> result.success(
                    mapOf(
                        "packageName" to requestingPackage,
                        "webDomain" to webDomain,
                        "appLabel" to appLabel(requestingPackage),
                        "hasUsername" to usernameIds.isNotEmpty(),
                        "hasPassword" to passwordIds.isNotEmpty(),
                    ),
                )
                "fill" -> {
                    finishWith(call.argument<String>("username"), call.argument<String>("password"))
                    result.success(null)
                }
                "cancel" -> {
                    setResult(Activity.RESULT_CANCELED)
                    finish()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun appLabel(pkg: String): String? = try {
        val info = packageManager.getApplicationInfo(pkg, 0)
        packageManager.getApplicationLabel(info).toString()
    } catch (_: Exception) {
        null
    }

    @Suppress("DEPRECATION") // Dataset.Builder(RemoteViews) works on every API level we support.
    private fun finishWith(username: String?, password: String?) {
        val presentation = RemoteViews(packageName, R.layout.autofill_item).apply {
            setTextViewText(R.id.autofill_text, username?.takeIf { it.isNotEmpty() } ?: "••••••••")
        }
        val dataset = Dataset.Builder(presentation).apply {
            if (username != null) usernameIds.forEach { setValue(it, AutofillValue.forText(username)) }
            if (password != null) passwordIds.forEach { setValue(it, AutofillValue.forText(password)) }
        }.build()
        setResult(
            Activity.RESULT_OK,
            Intent().putExtra(AutofillManager.EXTRA_AUTHENTICATION_RESULT, dataset),
        )
        finish()
    }
}
