package top.vollate.pars_gui.autofill

import android.content.IntentSender
import android.os.CancellationSignal
import android.service.autofill.AutofillService
import android.service.autofill.Dataset
import android.service.autofill.FillCallback
import android.service.autofill.FillRequest
import android.service.autofill.FillResponse
import android.service.autofill.SaveCallback
import android.view.autofill.AutofillId
import android.service.autofill.SaveRequest
import android.view.autofill.AutofillValue
import top.vollate.pars_gui.R

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
        val parsed = structure?.let { ParsAutofillRequestParser.parse(this, it) }
        if (parsed == null) {
            callback.onSuccess(null)
            return
        }

        val candidates =
            ParsAutofillNativeBridge.queryCandidates(
                context = this,
                website = parsed.website,
                appName = parsed.appName,
                query = parsed.query,
                limit = 5,
            )
        if (candidates.isEmpty()) {
            callback.onSuccess(noMatchesResponse(parsed))
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

    @Suppress("DEPRECATION")
    private fun noMatchesResponse(parsed: ParsedAutofillRequest): FillResponse {
        val ids =
            listOfNotNull(parsed.usernameId, parsed.passwordId)
                .distinct()
                .toTypedArray<AutofillId>()
        val target = parsed.website ?: parsed.appName ?: getString(R.string.app_name)
        val presentation =
            ParsAutofillUnlockActivity.presentation(
                context = this,
                title = getString(R.string.autofill_no_matches_title),
                subtitle = target,
            )
        val intent = ParsAutofillUnlockActivity.noMatchesIntent(this)
        val authentication =
            ParsAutofillUnlockActivity.pendingIntent(
                context = this,
                requestCode = NO_MATCH_REQUEST_CODE,
                intent = intent,
            ).intentSender
        return FillResponse.Builder()
            .setAuthentication(ids, authentication, presentation)
            .build()
    }

    private fun datasetFor(
        candidate: ParsAutofillCandidate,
        parsed: ParsedAutofillRequest,
    ): Dataset {
        val presentation =
            ParsAutofillUnlockActivity.presentation(
                context = this,
                title = candidate.displayName,
                subtitle = candidate.username,
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

    private companion object {
        const val NO_MATCH_REQUEST_CODE = 0x50415253
    }
}
