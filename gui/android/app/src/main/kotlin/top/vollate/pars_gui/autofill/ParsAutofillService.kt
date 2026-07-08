package top.vollate.pars_gui.autofill

import android.content.IntentSender
import android.os.CancellationSignal
import android.service.autofill.AutofillService
import android.service.autofill.Dataset
import android.service.autofill.FillCallback
import android.service.autofill.FillRequest
import android.service.autofill.FillResponse
import android.service.autofill.SaveCallback
import android.service.autofill.SaveRequest
import android.view.autofill.AutofillValue

class ParsAutofillService : AutofillService() {
    override fun onFillRequest(
        request: FillRequest,
        cancellationSignal: CancellationSignal,
        callback: FillCallback,
    ) {
        if (cancellationSignal.isCanceled) {
            callback.onSuccess(null)
            return
        }

        val structure = request.fillContexts.lastOrNull()?.structure
        val parsed = structure?.let(ParsAutofillRequestParser::parse)
        if (parsed == null) {
            callback.onSuccess(null)
            return
        }

        val candidates =
            ParsAutofillNativeBridge.queryCandidates(
                context = this,
                website = parsed.website,
                androidPackage = parsed.androidPackage,
                query = parsed.query,
                limit = 5,
            )
        if (candidates.isEmpty()) {
            callback.onSuccess(null)
            return
        }

        val response = FillResponse.Builder()
        for (candidate in candidates) {
            response.addDataset(datasetFor(candidate, parsed))
        }
        callback.onSuccess(response.build())
    }

    override fun onSaveRequest(
        request: SaveRequest,
        callback: SaveCallback,
    ) {
        callback.onSuccess()
    }

    private fun datasetFor(
        candidate: ParsAutofillCandidate,
        parsed: ParsedAutofillRequest,
    ): Dataset {
        val presentation =
            ParsAutofillUnlockActivity.presentation(
                context = this,
                title = candidate.displayName,
                subtitle = candidate.username ?: candidate.matchValue.ifBlank { "Pars password" },
            )
        val intent =
            ParsAutofillUnlockActivity.autofillIntent(
                context = this,
                path = candidate.path,
                usernameId = parsed.usernameId,
                passwordId = parsed.passwordId,
            )
        val auth: IntentSender =
            ParsAutofillUnlockActivity.pendingIntent(
                context = this,
                requestCode = candidate.path.hashCode(),
                intent = intent,
            ).intentSender
        val builder = Dataset.Builder(presentation)
            .setId(candidate.path)
            .setAuthentication(auth)
        parsed.usernameId?.let { id ->
            builder.setValue(id, null as AutofillValue?, presentation)
        }
        parsed.passwordId?.let { id ->
            builder.setValue(id, null as AutofillValue?, presentation)
        }
        return builder.build()
    }
}
