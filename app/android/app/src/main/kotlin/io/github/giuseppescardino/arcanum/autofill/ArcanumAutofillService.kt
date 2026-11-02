package io.github.giuseppescardino.arcanum.autofill

import android.app.PendingIntent
import android.content.Intent
import android.os.CancellationSignal
import android.service.autofill.AutofillService
import android.service.autofill.Dataset
import android.service.autofill.FillCallback
import android.service.autofill.FillRequest
import android.service.autofill.FillResponse
import android.service.autofill.SaveCallback
import android.service.autofill.SaveRequest
import android.widget.RemoteViews
import io.github.giuseppescardino.arcanum.R

/**
 * Never reads the vault itself: it only spots login fields and offers an
 * "unlock" entry. Choosing it opens [AutofillActivity], where the user
 * unlocks and explicitly picks the credential to fill.
 */
class ArcanumAutofillService : AutofillService() {

    override fun onFillRequest(
        request: FillRequest,
        cancellationSignal: CancellationSignal,
        callback: FillCallback,
    ) {
        val structure = request.fillContexts.lastOrNull()?.structure
        if (structure == null) {
            callback.onSuccess(null)
            return
        }
        val form = StructureParser.parse(structure)
        // Never offer to fill our own screens.
        if (!form.isFillable || form.packageName == packageName) {
            callback.onSuccess(null)
            return
        }

        val intent = Intent(this, AutofillActivity::class.java).apply {
            putParcelableArrayListExtra(AutofillActivity.EXTRA_USERNAME_IDS, ArrayList(form.usernameIds))
            putParcelableArrayListExtra(AutofillActivity.EXTRA_PASSWORD_IDS, ArrayList(form.passwordIds))
            putExtra(AutofillActivity.EXTRA_PACKAGE, form.packageName)
            putExtra(AutofillActivity.EXTRA_WEB_DOMAIN, form.webDomain)
        }
        // Mutable: the system adds the assist structure to the intent.
        val pending = PendingIntent.getActivity(
            this,
            request.id,
            intent,
            PendingIntent.FLAG_CANCEL_CURRENT or PendingIntent.FLAG_MUTABLE,
        )
        val presentation = RemoteViews(packageName, R.layout.autofill_item).apply {
            setTextViewText(R.id.autofill_text, getString(R.string.autofill_unlock))
        }
        // Dataset-level authentication: the activity returns a filled
        // Dataset, which Android applies immediately (no extra tap).
        @Suppress("DEPRECATION") // Builder(RemoteViews)/setValue work on all supported APIs.
        val locked = Dataset.Builder(presentation).apply {
            form.allIds.forEach { setValue(it, null) }
            setAuthentication(pending.intentSender)
        }.build()
        callback.onSuccess(FillResponse.Builder().addDataset(locked).build())
    }

    override fun onSaveRequest(request: SaveRequest, callback: SaveCallback) {
        // Saving new logins from other apps is not supported yet.
        callback.onSuccess()
    }
}
