package top.vollate.pars_gui.autofill

import android.annotation.TargetApi
import android.app.slice.Slice
import android.app.slice.SliceSpec
import android.credentials.Credential
import android.credentials.ClearCredentialStateException
import android.credentials.CreateCredentialException
import android.credentials.GetCredentialException
import android.net.Uri
import android.os.Build
import android.os.CancellationSignal
import android.os.OutcomeReceiver
import android.service.credentials.BeginCreateCredentialRequest
import android.service.credentials.BeginCreateCredentialResponse
import android.service.credentials.BeginGetCredentialRequest
import android.service.credentials.BeginGetCredentialResponse
import android.service.credentials.ClearCredentialStateRequest
import android.service.credentials.CredentialEntry
import android.service.credentials.CredentialProviderService

@TargetApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
class ParsCredentialProviderService : CredentialProviderService() {
    override fun onBeginGetCredential(
        request: BeginGetCredentialRequest,
        cancellationSignal: CancellationSignal,
        callback: OutcomeReceiver<BeginGetCredentialResponse, GetCredentialException>,
    ) {
        if (cancellationSignal.isCanceled) {
            callback.onResult(BeginGetCredentialResponse.Builder().build())
            return
        }
        val options =
            request.beginGetCredentialOptions.filter {
                it.type == Credential.TYPE_PASSWORD_CREDENTIAL
            }
        if (options.isEmpty()) {
            callback.onResult(BeginGetCredentialResponse.Builder().build())
            return
        }

        val candidates =
            ParsAutofillNativeBridge.queryCandidates(
                context = this,
                website = request.callingAppInfo?.origin,
                appName = ParsAutofillAppName.resolve(
                    this,
                    request.callingAppInfo?.packageName,
                ),
                query = null,
                limit = 5,
            )
        val response = BeginGetCredentialResponse.Builder()
        for (option in options) {
            for (candidate in candidates) {
                response.addCredentialEntry(CredentialEntry(option, credentialSlice(candidate)))
            }
        }
        callback.onResult(response.build())
    }

    override fun onBeginCreateCredential(
        request: BeginCreateCredentialRequest,
        cancellationSignal: CancellationSignal,
        callback: OutcomeReceiver<BeginCreateCredentialResponse, CreateCredentialException>,
    ) {
        callback.onResult(BeginCreateCredentialResponse.Builder().build())
    }

    override fun onClearCredentialState(
        request: ClearCredentialStateRequest,
        cancellationSignal: CancellationSignal,
        callback: OutcomeReceiver<Void?, ClearCredentialStateException>,
    ) {
        callback.onResult(null)
    }

    private fun credentialSlice(candidate: ParsAutofillCandidate): Slice {
        val uri =
            Uri.Builder()
                .scheme("content")
                .authority(packageName)
                .appendPath("credential")
                .appendPath(candidate.path.hashCode().toString())
                .appendPath(candidate.generation)
                .build()
        val pendingIntent =
            ParsAutofillUnlockActivity.pendingIntent(
                context = this,
                requestCode = 31 * candidate.path.hashCode() + candidate.generation.hashCode(),
                intent =
                    ParsAutofillUnlockActivity.credentialIntent(
                        this,
                        candidate.path,
                        candidate.generation,
                    ),
            )
        val actionSlice =
            Slice.Builder(
                uri.buildUpon().appendPath("action").build(),
                SliceSpec("pars_credential_action", 1),
            )
                .addText(candidate.displayName, null, listOf(Slice.HINT_TITLE))
                .build()

        return Slice.Builder(uri, SliceSpec("CredentialEntry", 1))
            .addText(candidate.displayName, null, listOf(Slice.HINT_TITLE))
            .addText(candidate.username, null, listOf(Slice.HINT_SUMMARY))
            .addAction(pendingIntent, actionSlice, null)
            .build()
    }
}
