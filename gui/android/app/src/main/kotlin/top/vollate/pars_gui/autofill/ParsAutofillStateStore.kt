package top.vollate.pars_gui.autofill

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.io.File
import java.security.KeyStore
import java.util.UUID
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

data class ParsAutofillState(
    val enabled: Boolean,
    val configPath: String,
    val indexPath: String,
    val storeRoot: String?,
    val passphrase: String?,
    val generation: String?,
)

object ParsAutofillStateStore {
    private const val PREFS_NAME = "pars_autofill_state"
    private const val KEY_ENABLED = "enabled"
    private const val KEY_CONFIG_PATH = "config_path"
    private const val KEY_INDEX_PATH = "index_path"
    private const val KEY_STORE_ROOT = "store_root"
    private const val KEY_GENERATION = "generation"
    private const val KEY_PASSPHRASE_CIPHERTEXT = "passphrase_ciphertext"
    private const val KEY_PASSPHRASE_IV = "passphrase_iv"
    private const val KEYSTORE_PROVIDER = "AndroidKeyStore"
    private const val KEY_ALIAS = "pars_autofill_passphrase"
    private const val CIPHER_TRANSFORMATION = "AES/GCM/NoPadding"

    fun publish(
        context: Context,
        configPath: String?,
        indexPath: String?,
        storeRoot: String?,
        passphrase: String?,
    ): Boolean {
        val resolvedIndexPath = indexPath ?: defaultIndexPath(context)
        if (storeRoot.isNullOrBlank() || !File(resolvedIndexPath).isFile) {
            clear(context)
            return false
        }
        val encrypted = passphrase?.takeIf { it.isNotEmpty() }?.let(::encrypt)
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.edit().apply {
            clear()
            putString(KEY_CONFIG_PATH, configPath ?: defaultConfigPath(context))
            putString(KEY_INDEX_PATH, resolvedIndexPath)
            putString(KEY_STORE_ROOT, storeRoot)
            putString(KEY_GENERATION, UUID.randomUUID().toString())
            if (encrypted != null) {
                putString(KEY_PASSPHRASE_CIPHERTEXT, encrypted.ciphertext)
                putString(KEY_PASSPHRASE_IV, encrypted.iv)
            }
            // Enabled is committed with the validated paths, never inferred from files.
            putBoolean(KEY_ENABLED, true)
        }.commit()
    }

    fun clear(context: Context): Boolean =
        context
            .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .clear()
            .putBoolean(KEY_ENABLED, false)
            .commit()

    fun read(context: Context): ParsAutofillState {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val enabled = prefs.getBoolean(KEY_ENABLED, false)
        val configPath = prefs.getString(KEY_CONFIG_PATH, null) ?: defaultConfigPath(context)
        val indexPath = prefs.getString(KEY_INDEX_PATH, null) ?: defaultIndexPath(context)
        val ciphertext = prefs.getString(KEY_PASSPHRASE_CIPHERTEXT, null)
        val iv = prefs.getString(KEY_PASSPHRASE_IV, null)
        val passphrase =
            if (!enabled || ciphertext == null || iv == null) {
                null
            } else {
                decryptOrNull(ciphertext, iv)
            }
        return ParsAutofillState(
            enabled = enabled,
            configPath = configPath,
            indexPath = indexPath,
            storeRoot = if (enabled) prefs.getString(KEY_STORE_ROOT, null) else null,
            passphrase = passphrase,
            generation = if (enabled) prefs.getString(KEY_GENERATION, null) else null,
        )
    }

    internal fun canServe(state: ParsAutofillState, indexExists: Boolean): Boolean =
        state.enabled &&
            indexExists &&
            !state.storeRoot.isNullOrBlank() &&
            !state.generation.isNullOrBlank()

    internal fun samePublication(expected: ParsAutofillState, current: ParsAutofillState): Boolean =
        canServe(current, File(current.indexPath).isFile) &&
            current.generation == expected.generation &&
            current.storeRoot == expected.storeRoot &&
            current.indexPath == expected.indexPath

    private fun defaultConfigPath(context: Context): String =
        File(context.filesDir, "pars_config.toml").absolutePath

    private fun defaultIndexPath(context: Context): String = "${defaultConfigPath(context)}.autofill.json"

    private fun encrypt(value: String): EncryptedValue {
        val cipher = Cipher.getInstance(CIPHER_TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, getOrCreateKey())
        val encrypted = cipher.doFinal(value.toByteArray(Charsets.UTF_8))
        return EncryptedValue(
            ciphertext = Base64.encodeToString(encrypted, Base64.NO_WRAP),
            iv = Base64.encodeToString(cipher.iv, Base64.NO_WRAP),
        )
    }

    private fun decryptOrNull(ciphertext: String, iv: String): String? =
        runCatching {
            val cipher = Cipher.getInstance(CIPHER_TRANSFORMATION)
            cipher.init(
                Cipher.DECRYPT_MODE,
                getOrCreateKey(),
                GCMParameterSpec(128, Base64.decode(iv, Base64.NO_WRAP)),
            )
            String(
                cipher.doFinal(Base64.decode(ciphertext, Base64.NO_WRAP)),
                Charsets.UTF_8,
            )
        }.getOrNull()

    private fun getOrCreateKey(): SecretKey {
        val keyStore = KeyStore.getInstance(KEYSTORE_PROVIDER).apply { load(null) }
        (keyStore.getEntry(KEY_ALIAS, null) as? KeyStore.SecretKeyEntry)?.let {
            return it.secretKey
        }

        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE_PROVIDER)
        generator.init(
            KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setRandomizedEncryptionRequired(true)
                .build(),
        )
        return generator.generateKey()
    }

    private data class EncryptedValue(
        val ciphertext: String,
        val iv: String,
    )
}
