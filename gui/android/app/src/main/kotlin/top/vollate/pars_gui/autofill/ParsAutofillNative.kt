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
    val isFavorite: Boolean,
    val recentRank: Int?,
    val generation: String,
)

data class ParsAutofillCredential(
    val path: String,
    val username: String,
    val password: String,
)

object ParsAutofillNativeBridge {
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
                        isFavorite = candidate.optBoolean("isFavorite"),
                        recentRank =
                            if (candidate.isNull("recentRank")) null else candidate.optInt("recentRank"),
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
    ): ParsAutofillCredential? =
        resolveCredentialWith(
            path = path,
            generation = generation,
            stateReader = { ParsAutofillStateStore.read(context) },
            nativeResolve = ParsAutofillNative::resolveCredential,
        )

    internal fun resolveCredentialWith(
        path: String,
        generation: String,
        stateReader: () -> ParsAutofillState,
        nativeResolve: (String) -> String,
    ): ParsAutofillCredential? {
        val state = stateReader()
        if (state.generation != generation ||
            !ParsAutofillStateStore.canServe(state, File(state.indexPath).isFile)
        ) return null
        val storeRoot = state.storeRoot ?: return null
        val request =
            JSONObject()
                .put("configPath", state.configPath)
                .put("indexPath", state.indexPath)
                .put("root", storeRoot)
                .put("path", path)
                .put("pgpExecutable", JSONObject.NULL)
                .put("passphrase", state.passphrase ?: JSONObject.NULL)
        val response = JSONObject(nativeResolve(request.toString()))
        if (!response.isNull("error") || response.isNull("credential")) return null
        val credential = response.getJSONObject("credential")
        if (!ParsAutofillStateStore.samePublication(state, stateReader())) return null
        return ParsAutofillCredential(
            path = credential.getString("path"),
            username = credential.getString("username"),
            password = credential.getString("password"),
        )
    }
}
