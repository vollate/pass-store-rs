package top.vollate.pars_gui.autofill

import android.app.Activity
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.credentials.Credential
import android.credentials.GetCredentialResponse
import android.hardware.biometrics.BiometricManager
import android.hardware.biometrics.BiometricPrompt
import android.os.Build
import android.os.Bundle
import android.net.Uri
import android.os.CancellationSignal
import android.service.autofill.Dataset
import android.service.credentials.CredentialProviderService
import android.util.Log
import android.view.View
import android.view.WindowInsets
import android.view.autofill.AutofillId
import android.view.autofill.AutofillManager
import android.view.autofill.AutofillValue
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.EditText
import android.widget.RemoteViews
import android.widget.TextView
import android.widget.Toast
import java.util.UUID
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import top.vollate.pars_gui.R

// Autofill is not the app lock: it never asks for the Pars gesture or a device
// credential. Decryption needs the PGP passphrase, either typed into a sheet
// matching the Vault or, when biometric unlock is enabled, the stored one
// released by a biometric prompt, exactly as the app itself does.
class ParsAutofillUnlockActivity : Activity() {
    private var cancellationSignal: CancellationSignal? = null
    private val resolver: ExecutorService = Executors.newSingleThreadExecutor()
    private var attempts = 0
    private var biometricStarted = false
    private var biometricSucceeded = false
    private var sheetShown = false
    private var resolving = false
    private var sheetBottomPadding = 0

    private lateinit var scrim: View
    private lateinit var sheet: View
    private lateinit var passphraseInput: EditText
    private lateinit var passphraseError: TextView
    private lateinit var unlockButton: View
    private lateinit var unlockProgress: View
    private lateinit var unlockIcon: View

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
            Log.w(TAG, "Autofill unlock needs Android P or newer, got ${Build.VERSION.SDK_INT}")
            finishCanceled()
            return
        }
        if (intent.getStringExtra(EXTRA_PATH) == null ||
            intent.getStringExtra(EXTRA_GENERATION) == null
        ) {
            finishCanceled()
            return
        }
        // An autofill session on this sheet would make Pars answer its own
        // passphrase field and strand the requesting app's session.
        window.decorView.importantForAutofill = View.IMPORTANT_FOR_AUTOFILL_NO_EXCLUDE_DESCENDANTS
        setContentView(R.layout.pars_autofill_passphrase)
        bindSheet()
        if (!ParsAutofillNativeBridge.offersBiometricUnlock(this) || !biometricReady()) {
            showPassphraseSheet(error = null)
        }
    }

    // BiometricPrompt rejects callers that are not yet in the foreground, and this
    // activity is launched from a backgrounded process, so authentication waits for
    // the first window focus instead of starting during onCreate.
    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (!hasFocus || isFinishing) {
            return
        }
        // The IME only attaches to a focused window, so the keyboard is requested
        // here as well as when the sheet first appears.
        if (sheetShown) {
            showKeyboard()
            return
        }
        if (biometricStarted) {
            return
        }
        biometricStarted = true
        authenticateWithBiometrics()
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        finishCanceled()
    }

    override fun onDestroy() {
        cancellationSignal?.cancel()
        resolver.shutdownNow()
        super.onDestroy()
    }

    private fun bindSheet() {
        val root = findViewById<View>(R.id.autofill_root)
        scrim = findViewById(R.id.autofill_scrim)
        sheet = findViewById(R.id.autofill_sheet)
        passphraseInput = findViewById(R.id.autofill_passphrase)
        passphraseError = findViewById(R.id.autofill_passphrase_error)
        unlockButton = findViewById(R.id.autofill_passphrase_unlock)
        unlockProgress = findViewById(R.id.autofill_passphrase_progress)
        unlockIcon = findViewById(R.id.autofill_passphrase_icon)
        findViewById<TextView>(R.id.autofill_passphrase_path).text =
            intent.getStringExtra(EXTRA_PATH)

        scrim.setOnClickListener { if (sheetShown) finishCanceled() }
        unlockButton.setOnClickListener { submitPassphrase() }
        passphraseInput.setOnEditorActionListener { _, actionId, _ ->
            if (actionId == EditorInfo.IME_ACTION_DONE) {
                submitPassphrase()
                true
            } else {
                false
            }
        }

        sheetBottomPadding = sheet.paddingBottom
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            // Edge-to-edge windows are not resized for the keyboard, so the sheet
            // lifts itself above the IME and navigation bar.
            window.setDecorFitsSystemWindows(false)
            root.setOnApplyWindowInsetsListener { _, insets ->
                val bottom =
                    insets.getInsets(WindowInsets.Type.ime() or WindowInsets.Type.systemBars()).bottom
                sheet.setPadding(
                    sheet.paddingLeft,
                    sheet.paddingTop,
                    sheet.paddingRight,
                    sheetBottomPadding + bottom,
                )
                insets
            }
        }
    }

    private fun biometricReady(): Boolean =
        when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.R ->
                getSystemService(BiometricManager::class.java)
                    ?.canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_STRONG) ==
                    BiometricManager.BIOMETRIC_SUCCESS
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q ->
                @Suppress("DEPRECATION")
                getSystemService(BiometricManager::class.java)?.canAuthenticate() ==
                    BiometricManager.BIOMETRIC_SUCCESS
            else -> true
        }

    private fun authenticateWithBiometrics() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
            finishCanceled()
            return
        }
        val signal = CancellationSignal()
        cancellationSignal = signal
        val promptBuilder =
            BiometricPrompt.Builder(this)
                .setTitle(getString(R.string.autofill_biometric_title))
                .setSubtitle(intent.getStringExtra(EXTRA_PATH).orEmpty())
                .setNegativeButton(
                    getString(R.string.autofill_biometric_use_passphrase),
                    mainExecutor,
                ) { _, _ -> showPassphraseSheet(error = null) }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            promptBuilder.setAllowedAuthenticators(BiometricManager.Authenticators.BIOMETRIC_STRONG)
        }

        promptBuilder.build().authenticate(
            signal,
            mainExecutor,
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult?) {
                    biometricSucceeded = true
                    resolve(passphrase = null)
                }

                override fun onAuthenticationError(errorCode: Int, errString: CharSequence?) {
                    Log.w(TAG, "Autofill biometric prompt ended: code=$errorCode, message=$errString")
                    // Some OEM builds cancel the sensor while dismissing a successful
                    // prompt and report it as an error; that must not cancel the fill.
                    if (biometricSucceeded) return
                    when (errorCode) {
                        BiometricPrompt.BIOMETRIC_ERROR_USER_CANCELED,
                        BiometricPrompt.BIOMETRIC_ERROR_CANCELED -> finishCanceled()
                        // Lockout, missing enrollment, or hardware trouble still
                        // leaves the passphrase as a way in.
                        else -> showPassphraseSheet(error = null)
                    }
                }

                override fun onAuthenticationFailed() {
                    // Keep the prompt open for another biometric attempt.
                }
            },
        )
    }

    private fun showPassphraseSheet(error: String?) {
        if (isFinishing) return
        setError(error)
        setResolving(false)
        if (!sheetShown) {
            sheetShown = true
            sheet.translationY = resources.displayMetrics.heightPixels.toFloat()
            sheet.visibility = View.VISIBLE
            sheet.post {
                sheet.translationY = sheet.height.toFloat()
                sheet.animate().translationY(0f).setDuration(SHEET_ANIMATION_MS).start()
                scrim.animate().alpha(1f).setDuration(SHEET_ANIMATION_MS).start()
            }
        }
        passphraseInput.post { showKeyboard() }
    }

    private fun showKeyboard() {
        if (!sheetShown || isFinishing) return
        passphraseInput.requestFocus()
        if (!hasWindowFocus()) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.insetsController?.show(WindowInsets.Type.ime())
        } else {
            getSystemService(InputMethodManager::class.java)?.showSoftInput(passphraseInput, 0)
        }
    }

    private fun submitPassphrase() {
        if (resolving) return
        val passphrase = passphraseInput.text.toString()
        if (passphrase.isEmpty()) {
            setError(getString(R.string.autofill_passphrase_empty))
            return
        }
        attempts += 1
        resolve(passphrase)
    }

    // Decryption runs off the UI thread; a typed passphrase is used for this
    // single request and never persisted.
    private fun resolve(passphrase: String?) {
        val path = intent.getStringExtra(EXTRA_PATH) ?: return finishCanceled()
        val generation = intent.getStringExtra(EXTRA_GENERATION) ?: return finishCanceled()
        setResolving(true)
        resolver.execute {
            val resolution =
                ParsAutofillNativeBridge.resolveCredential(this, path, generation, passphrase)
            runOnUiThread {
                if (isFinishing || isDestroyed) return@runOnUiThread
                handleResolution(resolution, generation, typed = passphrase != null)
            }
        }
    }

    private fun handleResolution(
        resolution: ParsAutofillResolution,
        generation: String,
        typed: Boolean,
    ) {
        Log.i(TAG, "Autofill resolution: ${resolution::class.simpleName}, typed=$typed")
        when (resolution) {
            is ParsAutofillResolution.Resolved ->
                when (intent.getStringExtra(EXTRA_MODE)) {
                    MODE_AUTOFILL -> finishAutofill(resolution.credential, generation)
                    MODE_CREDENTIAL -> finishCredentialManager(resolution.credential, generation)
                    else -> finishCanceled()
                }
            ParsAutofillResolution.PassphraseRequired -> {
                passphraseInput.text.clear()
                if (typed && attempts >= MAX_PASSPHRASE_ATTEMPTS) {
                    Toast.makeText(
                        this,
                        getString(R.string.autofill_passphrase_failed_toast),
                        Toast.LENGTH_SHORT,
                    ).show()
                    finishCanceled()
                } else {
                    showPassphraseSheet(
                        error = if (typed) getString(R.string.autofill_passphrase_rejected) else null,
                    )
                }
            }
            ParsAutofillResolution.Unavailable -> {
                Log.w(TAG, "Autofill credential is unavailable for the published state")
                finishCanceled()
            }
        }
    }

    private fun setError(message: String?) {
        passphraseError.text = message
        passphraseError.visibility = if (message == null) View.GONE else View.VISIBLE
        passphraseInput.setBackgroundResource(
            if (message == null) {
                R.drawable.pars_autofill_field_background
            } else {
                R.drawable.pars_autofill_field_background_error
            },
        )
    }

    private fun setResolving(value: Boolean) {
        resolving = value
        unlockButton.isEnabled = !value
        unlockProgress.visibility = if (value) View.VISIBLE else View.GONE
        unlockIcon.visibility = if (value) View.GONE else View.VISIBLE
    }

    private fun finishAutofill(credential: ParsAutofillCredential, generation: String) {
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
        val dataset = datasetBuilder.build()
        Log.i(
            TAG,
            "Returning autofill dataset: username=${usernameId != null}, password=${passwordId != null}",
        )
        ParsAutofillNativeBridge.recordCompletion(this, credential.path, generation)
        setResult(
            RESULT_OK,
            Intent().putExtra(
                AutofillManager.EXTRA_AUTHENTICATION_RESULT,
                dataset,
            ),
        )
        finish()
    }

    private fun finishCredentialManager(credential: ParsAutofillCredential, generation: String) {
        val data =
            Bundle().apply {
                putString("android.credentials.BUNDLE_KEY_ID", credential.username)
                putString("android.credentials.BUNDLE_KEY_PASSWORD", credential.password)
            }
        val response = GetCredentialResponse(Credential(Credential.TYPE_PASSWORD_CREDENTIAL, data))
        ParsAutofillNativeBridge.recordCompletion(this, credential.path, generation)
        setResult(
            RESULT_OK,
            Intent().putExtra(
                CredentialProviderService.EXTRA_GET_CREDENTIAL_RESPONSE,
                response,
            ),
        )
        finish()
    }

    private fun finishCanceled() {
        Log.i(TAG, "Autofill request canceled", Throwable("cancel origin"))
        setResult(RESULT_CANCELED)
        finish()
    }

    @Suppress("DEPRECATION")
    private inline fun <reified T> getParcelableExtraCompat(key: String): T? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(key, T::class.java)
        } else {
            intent.getParcelableExtra(key) as? T
        }

    companion object {
        private const val TAG = "ParsAutofillUnlock"
        private const val EXTRA_MODE = "top.vollate.pars_gui.autofill.MODE"
        private const val EXTRA_PATH = "top.vollate.pars_gui.autofill.PATH"
        private const val EXTRA_GENERATION = "top.vollate.pars_gui.autofill.GENERATION"
        private const val EXTRA_USERNAME_ID = "top.vollate.pars_gui.autofill.USERNAME_ID"
        private const val EXTRA_PASSWORD_ID = "top.vollate.pars_gui.autofill.PASSWORD_ID"
        private const val MODE_AUTOFILL = "autofill"
        private const val MODE_CREDENTIAL = "credential"
        private const val MODE_NO_MATCHES = "no_matches"
        private const val MAX_PASSPHRASE_ATTEMPTS = 3
        private const val SHEET_ANIMATION_MS = 220L

        fun autofillIntent(
            context: Context,
            path: String,
            generation: String,
            usernameId: AutofillId?,
            passwordId: AutofillId?,
        ): Intent =
            Intent(context, ParsAutofillUnlockActivity::class.java)
                .putExtra(EXTRA_MODE, MODE_AUTOFILL)
                .putExtra(EXTRA_PATH, path)
                .putExtra(EXTRA_GENERATION, generation)
                .putExtra(EXTRA_USERNAME_ID, usernameId)
                .putExtra(EXTRA_PASSWORD_ID, passwordId)

        fun credentialIntent(context: Context, path: String, generation: String): Intent =
            Intent(context, ParsAutofillUnlockActivity::class.java)
                .putExtra(EXTRA_MODE, MODE_CREDENTIAL)
                .putExtra(EXTRA_PATH, path)
                .putExtra(EXTRA_GENERATION, generation)

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
                // Not one-shot: after a cancel the framework re-sends this same
                // sender when the user picks the dataset again.
                PendingIntent.FLAG_UPDATE_CURRENT or mutableFlag(),
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
