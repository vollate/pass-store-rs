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
    ): List<ParsAutofillCandidate> {
        val state = ParsAutofillStateStore.read(context)
        if (!File(state.indexPath).isFile) {
            return emptyList()
        }
        val request =
            JSONObject()
                .put("indexPath", state.indexPath)
                .put("website", website)
                .put("appName", appName)
                .put("query", query)
                .put("limit", limit)
        val response = JSONObject(ParsAutofillNative.queryCandidates(request.toString()))
        if (!response.isNull("error")) {
            return emptyList()
        }
        val candidates = response.optJSONArray("candidates") ?: return emptyList()
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
                            if (candidate.isNull("recentRank")) {
                                null
                            } else {
                                candidate.optInt("recentRank")
                            },
                    ),
                )
            }
        }
    }

    fun resolveCredential(context: Context, path: String): ParsAutofillCredential? {
        val state = ParsAutofillStateStore.read(context)
        val storeRoot = state.storeRoot ?: return null
        if (!File(state.indexPath).isFile) {
            return null
        }
        val request =
            JSONObject()
                .put("configPath", state.configPath)
                .put("indexPath", state.indexPath)
                .put("root", storeRoot)
                .put("path", path)
                .put("pgpExecutable", JSONObject.NULL)
                .put("passphrase", state.passphrase ?: JSONObject.NULL)
        val response = JSONObject(ParsAutofillNative.resolveCredential(request.toString()))
        if (!response.isNull("error") || response.isNull("credential")) {
            return null
        }
        val credential = response.getJSONObject("credential")
        return ParsAutofillCredential(
            path = credential.getString("path"),
            username = credential.getString("username"),
            password = credential.getString("password"),
        )
    }
}
