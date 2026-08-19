package top.vollate.pars_gui.autofill

import android.app.assist.AssistStructure
import android.content.Context
import android.text.InputType
import android.view.View
import android.view.autofill.AutofillId

data class ParsedAutofillRequest(
    val appName: String?,
    val website: String?,
    val query: String?,
    val usernameId: AutofillId?,
    val passwordId: AutofillId?,
)

object ParsAutofillRequestParser {
    fun parse(
        context: Context,
        structure: AssistStructure,
    ): ParsedAutofillRequest? {
        var website: String? = null
        var usernameId: AutofillId? = null
        var passwordId: AutofillId? = null
        val queryParts = mutableListOf<String>()

        for (index in 0 until structure.windowNodeCount) {
            val root = structure.getWindowNodeAt(index).rootViewNode
            visit(root) { node ->
                if (website == null) {
                    website = node.webDomain?.ifBlank { null }
                }
                val autofillId = node.autofillId ?: return@visit
                if (node.autofillType == 0) {
                    return@visit
                }
                val role = roleFor(node)
                when {
                    role == FieldRole.Password && passwordId == null -> passwordId = autofillId
                    role == FieldRole.Username && usernameId == null -> usernameId = autofillId
                }
                node.idEntry?.let(queryParts::add)
                node.hint?.toString()?.let(queryParts::add)
                node.text?.toString()?.let(queryParts::add)
            }
        }

        if (passwordId == null && usernameId == null) {
            return null
        }
        return ParsedAutofillRequest(
            appName = ParsAutofillAppName.resolve(
                context,
                structure.activityComponent?.packageName,
            ),
            website = website,
            query = queryParts.joinToString(" ").takeIf { it.isNotBlank() },
            usernameId = usernameId,
            passwordId = passwordId,
        )
    }

    private fun visit(
        node: AssistStructure.ViewNode,
        block: (AssistStructure.ViewNode) -> Unit,
    ) {
        block(node)
        for (index in 0 until node.childCount) {
            visit(node.getChildAt(index), block)
        }
    }

    private fun roleFor(node: AssistStructure.ViewNode): FieldRole {
        val hints = node.autofillHints.orEmpty().map { it.lowercase() }
        if (hints.any { it == View.AUTOFILL_HINT_PASSWORD.lowercase() }) {
            return FieldRole.Password
        }
        if (hints.any {
                it == View.AUTOFILL_HINT_USERNAME.lowercase() ||
                    it == View.AUTOFILL_HINT_EMAIL_ADDRESS.lowercase()
            }
        ) {
            return FieldRole.Username
        }

        val tokens =
            listOfNotNull(
                node.idEntry,
                node.hint?.toString(),
                node.textIdEntry,
                node.contentDescription?.toString(),
            ).joinToString(" ").lowercase()
        val inputType = node.inputType
        val variation = inputType and InputType.TYPE_MASK_VARIATION
        return when {
            variation == InputType.TYPE_TEXT_VARIATION_PASSWORD ||
                variation == InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD ||
                variation == InputType.TYPE_TEXT_VARIATION_WEB_PASSWORD ||
                tokens.contains("password") ||
                tokens.contains("passwd") ||
                tokens.contains("pwd") -> FieldRole.Password
            variation == InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS ||
                variation == InputType.TYPE_TEXT_VARIATION_WEB_EMAIL_ADDRESS ||
                tokens.contains("username") ||
                tokens.contains("user") ||
                tokens.contains("login") ||
                tokens.contains("email") -> FieldRole.Username
            else -> FieldRole.Unknown
        }
    }

    private enum class FieldRole {
        Username,
        Password,
        Unknown,
    }
}

object ParsAutofillAppName {
    @Suppress("DEPRECATION")
    fun resolve(
        context: Context,
        packageName: String?,
    ): String? {
        if (packageName.isNullOrBlank()) return null
        return runCatching {
            val applicationInfo = context.packageManager.getApplicationInfo(packageName, 0)
            context.packageManager.getApplicationLabel(applicationInfo).toString().trim()
        }.getOrNull()?.ifBlank { null }
    }
}
