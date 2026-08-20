package top.vollate.pars_gui.autofill

import android.app.Activity
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.credentials.Credential
import android.credentials.GetCredentialResponse
import android.hardware.biometrics.BiometricPrompt
import android.os.Build
import android.os.Bundle
import android.net.Uri
import android.os.CancellationSignal
import android.service.autofill.Dataset
import android.service.credentials.CredentialProviderService
import android.view.autofill.AutofillId
import android.view.autofill.AutofillManager
import android.view.autofill.AutofillValue
import android.widget.RemoteViews
import android.widget.Toast
import java.util.UUID
import java.util.concurrent.Executor
import top.vollate.pars_gui.R

class ParsAutofillUnlockActivity : Activity() {
    private var cancellationSignal: CancellationSignal? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (intent.getStringExtra(EXTRA_MODE) == MODE_NO_MATCHES) {
            Toast.makeText(
                this,
                getString(R.string.autofill_no_matches_toast),
                Toast.LENGTH_SHORT,
            ).show()
            finishCanceled()
            return
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
            finishCanceled()
            return
        }
        authenticate()
    }

    override fun onDestroy() {
        cancellationSignal?.cancel()
        super.onDestroy()
    }

    private fun authenticate() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
            finishCanceled()
            return
        }
        val signal = CancellationSignal()
        cancellationSignal = signal
        val promptBuilder =
            BiometricPrompt.Builder(this)
                .setTitle(getString(R.string.autofill_unlock_title))
                .setSubtitle(getString(R.string.autofill_unlock_subtitle))
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            promptBuilder.setAllowedAuthenticators(
                android.hardware.biometrics.BiometricManager.Authenticators.BIOMETRIC_STRONG or
                    android.hardware.biometrics.BiometricManager.Authenticators.DEVICE_CREDENTIAL,
            )
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            promptBuilder.setDeviceCredentialAllowed(true)
        } else {
            promptBuilder.setNegativeButton(
                getString(R.string.autofill_cancel),
                directExecutor(),
            ) { _, _ -> finishCanceled() }
        }

        promptBuilder.build().authenticate(
            signal,
            directExecutor(),
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult?) {
                    resolveAndReturn()
                }

                override fun onAuthenticationError(errorCode: Int, errString: CharSequence?) {
                    finishCanceled()
                }

                override fun onAuthenticationFailed() {
                    // Keep the prompt open for another biometric attempt.
                }
            },
        )
    }

    private fun resolveAndReturn() {
        val path = intent.getStringExtra(EXTRA_PATH) ?: return finishCanceled()
        val credential = ParsAutofillNativeBridge.resolveCredential(this, path) ?: return finishCanceled()
        when (intent.getStringExtra(EXTRA_MODE)) {
            MODE_AUTOFILL -> finishAutofill(credential)
            MODE_CREDENTIAL -> finishCredentialManager(credential)
            else -> finishCanceled()
        }
    }

    private fun finishAutofill(credential: ParsAutofillCredential) {
        val usernameId = getParcelableExtraCompat<AutofillId>(EXTRA_USERNAME_ID)
        val passwordId = getParcelableExtraCompat<AutofillId>(EXTRA_PASSWORD_ID)
        val presentation =
            presentation(
                this,
                credential.username,
                getString(R.string.autofill_password_source),
            )
        val datasetBuilder = Dataset.Builder(presentation).setId(credential.path)
        if (usernameId != null) {
            datasetBuilder.setValue(usernameId, AutofillValue.forText(credential.username), presentation)
        }
        if (passwordId != null) {
            datasetBuilder.setValue(passwordId, AutofillValue.forText(credential.password), presentation)
        }
        setResult(
            RESULT_OK,
            Intent().putExtra(
                AutofillManager.EXTRA_AUTHENTICATION_RESULT,
                datasetBuilder.build(),
            ),
        )
        finish()
    }

    private fun finishCredentialManager(credential: ParsAutofillCredential) {
        val data =
            Bundle().apply {
                putString("android.credentials.BUNDLE_KEY_ID", credential.username)
                putString("android.credentials.BUNDLE_KEY_PASSWORD", credential.password)
            }
        setResult(
            RESULT_OK,
            Intent().putExtra(
                CredentialProviderService.EXTRA_GET_CREDENTIAL_RESPONSE,
                GetCredentialResponse(Credential(Credential.TYPE_PASSWORD_CREDENTIAL, data)),
            ),
        )
        finish()
    }

    private fun finishCanceled() {
        setResult(RESULT_CANCELED)
        finish()
    }

    private fun directExecutor(): Executor = Executor { command -> command.run() }

    @Suppress("DEPRECATION")
    private inline fun <reified T> getParcelableExtraCompat(key: String): T? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(key, T::class.java)
        } else {
            intent.getParcelableExtra(key) as? T
        }

    companion object {
        private const val EXTRA_MODE = "top.vollate.pars_gui.autofill.MODE"
        private const val EXTRA_PATH = "top.vollate.pars_gui.autofill.PATH"
        private const val EXTRA_USERNAME_ID = "top.vollate.pars_gui.autofill.USERNAME_ID"
        private const val EXTRA_PASSWORD_ID = "top.vollate.pars_gui.autofill.PASSWORD_ID"
        private const val MODE_AUTOFILL = "autofill"
        private const val MODE_CREDENTIAL = "credential"
        private const val MODE_NO_MATCHES = "no_matches"

        fun autofillIntent(
            context: Context,
            path: String,
            usernameId: AutofillId?,
            passwordId: AutofillId?,
        ): Intent =
            Intent(context, ParsAutofillUnlockActivity::class.java)
                .putExtra(EXTRA_MODE, MODE_AUTOFILL)
                .putExtra(EXTRA_PATH, path)
                .putExtra(EXTRA_USERNAME_ID, usernameId)
                .putExtra(EXTRA_PASSWORD_ID, passwordId)

        fun credentialIntent(context: Context, path: String): Intent =
            Intent(context, ParsAutofillUnlockActivity::class.java)
                .putExtra(EXTRA_MODE, MODE_CREDENTIAL)
                .putExtra(EXTRA_PATH, path)

        fun noMatchesIntent(context: Context): Intent =
            Intent(context, ParsAutofillUnlockActivity::class.java)
                .putExtra(EXTRA_MODE, MODE_NO_MATCHES)

        fun pendingIntent(
            context: Context,
            requestCode: Int,
            intent: Intent,
        ): PendingIntent {
            intent.data =
                Uri.Builder()
                    .scheme("pars-autofill")
                    .authority("request")
                    .appendPath(UUID.randomUUID().toString())
                    .build()
            return PendingIntent.getActivity(
                context,
                requestCode,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_ONE_SHOT or mutableFlag(),
            )
        }

        fun presentation(
            context: Context,
            title: String,
            subtitle: String,
        ): RemoteViews =
            RemoteViews(context.packageName, R.layout.pars_autofill_presentation).apply {
                setTextViewText(R.id.autofill_title, title)
                setTextViewText(R.id.autofill_subtitle, subtitle)
            }

        private fun mutableFlag(): Int =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0
    }
}
