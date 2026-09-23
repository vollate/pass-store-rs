package top.vollate.pars_gui.autofill

import android.content.Context
import java.io.File
import org.json.JSONObject

object ParsAutofillNative {
    private val loaded = runCatching { System.loadLibrary("pars_bridge") }.isSuccess

    @JvmStatic
    external fun queryCandidatesJson(requestJson: String): String

    @JvmStatic
    external fun resolveCredentialJson(requestJson: String): String

    @JvmStatic
    external fun recordCompletionJson(requestJson: String): String

    fun queryCandidates(requestJson: String): String =
        if (loaded) {
            queryCandidatesJson(requestJson)
        } else {
            nativeUnavailableJson()
        }

    fun resolveCredential(requestJson: String): String =
        if (loaded) {
            resolveCredentialJson(requestJson)
        } else {
            nativeUnavailableJson()
        }

    fun recordCompletion(requestJson: String): String =
        if (loaded) {
            recordCompletionJson(requestJson)
        } else {
            nativeUnavailableJson()
        }

    private fun nativeUnavailableJson(): String =
        """{"error":{"category":"native_unavailable","message":"pars_bridge is not loaded"}}"""
}

data class ParsAutofillCandidate(
    val path: String,
    val displayName: String,
    val username: String,
    val matchKind: String,
    val matchValue: String,
    val score: Int,
    val generation: String,
)

data class ParsAutofillCredential(
    val path: String,
    val username: String,
    val password: String,
)

// Why a credential resolution ended, so callers can tell a passphrase the user
// can still correct from a publication that must fail closed.
sealed interface ParsAutofillResolution {
    data class Resolved(val credential: ParsAutofillCredential) : ParsAutofillResolution

    // Decryption failed; another passphrase may still unlock the entry.
    data object PassphraseRequired : ParsAutofillResolution

    // State, index, or generation no longer serves this request.
    data object Unavailable : ParsAutofillResolution
}

object ParsAutofillNativeBridge {
    private const val PGP_ERROR_CATEGORY = "PgpError"

    fun queryCandidates(
        context: Context,
        website: String?,
        appName: String?,
        query: String?,
        limit: Int,
    ): List<ParsAutofillCandidate> =
        queryCandidatesWith(
            website = website,
            appName = appName,
            query = query,
            limit = limit,
            stateReader = { ParsAutofillStateStore.read(context) },
            nativeQuery = ParsAutofillNative::queryCandidates,
        )

    internal fun queryCandidatesWith(
        website: String?,
        appName: String?,
        query: String?,
        limit: Int,
        stateReader: () -> ParsAutofillState,
        nativeQuery: (String) -> String,
    ): List<ParsAutofillCandidate> {
        val state = stateReader()
        if (!ParsAutofillStateStore.canServe(state, File(state.indexPath).isFile)) return emptyList()
        val request =
            JSONObject()
                .put("indexPath", state.indexPath)
                .put("website", website)
                .put("appName", appName)
                .put("query", query)
                .put("limit", limit)
        val response = JSONObject(nativeQuery(request.toString()))
        if (!response.isNull("error")) return emptyList()
        val candidates = response.optJSONArray("candidates") ?: return emptyList()
        if (!ParsAutofillStateStore.samePublication(state, stateReader())) return emptyList()
        val generation = state.generation ?: return emptyList()
        return buildList {
            for (index in 0 until candidates.length()) {
                val candidate = candidates.optJSONObject(index) ?: continue
                add(
                    ParsAutofillCandidate(
                        path = candidate.getString("path"),
                        displayName = candidate.getString("displayName"),
                        username = candidate.getString("username"),
                        matchKind = candidate.getString("matchKind"),
                        matchValue = candidate.optString("matchValue"),
                        score = candidate.optInt("score"),
                        generation = generation,
                    ),
                )
            }
        }
    }

    fun resolveCredential(
        context: Context,
        path: String,
        generation: String,
        passphrase: String? = null,
    ): ParsAutofillResolution =
        resolveCredentialWith(
            path = path,
            generation = generation,
            passphrase = passphrase,
            stateReader = { ParsAutofillStateStore.read(context) },
            nativeResolve = ParsAutofillNative::resolveCredential,
        )

    internal fun resolveCredentialWith(
        path: String,
        generation: String,
        passphrase: String? = null,
        stateReader: () -> ParsAutofillState,
        nativeResolve: (String) -> String,
    ): ParsAutofillResolution {
        val state = stateReader()
        if (state.generation != generation ||
            !ParsAutofillStateStore.canServe(state, File(state.indexPath).isFile)
        ) return ParsAutofillResolution.Unavailable
        val storeRoot = state.storeRoot ?: return ParsAutofillResolution.Unavailable
        // A supplied passphrase is session-only and overrides the published one.
        val effective = passphrase?.takeIf { it.isNotEmpty() } ?: state.passphrase
        val request =
            JSONObject()
                .put("configPath", state.configPath)
                .put("indexPath", state.indexPath)
                .put("root", storeRoot)
                .put("path", path)
                .put("pgpExecutable", JSONObject.NULL)
                .put("passphrase", effective ?: JSONObject.NULL)
        val response =
            runCatching { JSONObject(nativeResolve(request.toString())) }.getOrNull()
                ?: return ParsAutofillResolution.Unavailable
        if (!response.isNull("error")) {
            // Only a failed decrypt can be retried with different input.
            val category = response.optJSONObject("error")?.optString("category")
            return if (category == PGP_ERROR_CATEGORY) {
                ParsAutofillResolution.PassphraseRequired
            } else {
                ParsAutofillResolution.Unavailable
            }
        }
        if (response.isNull("credential")) return ParsAutofillResolution.Unavailable
        val credential = response.getJSONObject("credential")
        if (!ParsAutofillStateStore.samePublication(state, stateReader())) {
            return ParsAutofillResolution.Unavailable
        }
        return ParsAutofillResolution.Resolved(
            ParsAutofillCredential(
                path = credential.getString("path"),
                username = credential.getString("username"),
                password = credential.getString("password"),
            ),
        )
    }

    fun recordCompletion(
        context: Context,
        path: String,
        generation: String,
    ): Boolean =
        recordCompletionWith(
            path = path,
            generation = generation,
            stateReader = { ParsAutofillStateStore.read(context) },
            nativeRecord = ParsAutofillNative::recordCompletion,
        )

    internal fun recordCompletionWith(
        path: String,
        generation: String,
        stateReader: () -> ParsAutofillState,
        nativeRecord: (String) -> String,
    ): Boolean {
        val state = stateReader()
        if (state.generation != generation ||
            !ParsAutofillStateStore.canServe(state, File(state.indexPath).isFile)
        ) return false
        val request =
            JSONObject()
                .put("indexPath", state.indexPath)
                .put("path", path)
        val response = runCatching { JSONObject(nativeRecord(request.toString())) }.getOrNull()
            ?: return false
        if (!response.isNull("error") || !response.optBoolean("recorded")) return false
        return ParsAutofillStateStore.samePublication(state, stateReader())
    }
}
