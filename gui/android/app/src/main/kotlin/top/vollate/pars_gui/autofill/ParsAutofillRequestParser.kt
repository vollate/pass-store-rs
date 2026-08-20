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
        val fields = mutableListOf<AutofillFieldCandidate<AutofillId>>()
        val queryParts = mutableListOf<String>()
        var traversalIndex = 0

        for (index in 0 until structure.windowNodeCount) {
            val root = structure.getWindowNodeAt(index).rootViewNode
            visit(root) { node ->
                val nodeIndex = traversalIndex++
                if (website == null) {
                    website = node.webDomain?.ifBlank { null }
                }
                val autofillId = node.autofillId ?: return@visit
                if (node.autofillType == 0) {
                    return@visit
                }
                val role = roleFor(node)
                if (role != FieldRole.Unknown) {
                    fields +=
                        AutofillFieldCandidate(
                            value = autofillId,
                            role = role,
                            traversalIndex = nodeIndex,
                            focused = node.isFocused,
                            visible =
                                node.visibility == View.VISIBLE &&
                                    node.width > 0 &&
                                    node.height > 0,
                        )
                }
                node.idEntry?.let(queryParts::add)
                node.hint?.toString()?.let(queryParts::add)
                node.text?.toString()?.let(queryParts::add)
            }
        }

        val selectedFields = selectAutofillFields(fields)
        if (selectedFields.password == null && selectedFields.username == null) {
            return null
        }
        return ParsedAutofillRequest(
            appName = ParsAutofillAppName.resolve(
                context,
                structure.activityComponent?.packageName,
            ),
            website = website,
            query = queryParts.joinToString(" ").takeIf { it.isNotBlank() },
            usernameId = selectedFields.username,
            passwordId = selectedFields.password,
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

    internal data class AutofillFieldCandidate<T>(
        val value: T,
        val role: FieldRole,
        val traversalIndex: Int,
        val focused: Boolean,
        val visible: Boolean,
    )

    internal data class AutofillFieldSelection<T>(
        val username: T?,
        val password: T?,
    )

    internal fun <T> selectAutofillFields(
        candidates: List<AutofillFieldCandidate<T>>,
    ): AutofillFieldSelection<T> {
        val visible = candidates.filter { it.visible }
        val pool = visible.ifEmpty { candidates }
        val focused = pool.lastOrNull { it.focused }
        if (focused != null) {
            val companionRole =
                if (focused.role == FieldRole.Username) FieldRole.Password else FieldRole.Username
            val companion =
                pool.filter { it.role == companionRole }
                    .minWithOrNull(
                        compareBy<AutofillFieldCandidate<T>> {
                            kotlin.math.abs(it.traversalIndex - focused.traversalIndex)
                        }.thenByDescending { it.traversalIndex },
                    )
            return if (focused.role == FieldRole.Username) {
                AutofillFieldSelection(focused.value, companion?.value)
            } else {
                AutofillFieldSelection(companion?.value, focused.value)
            }
        }

        val usernames = pool.filter { it.role == FieldRole.Username }
        val passwords = pool.filter { it.role == FieldRole.Password }
        if (usernames.isNotEmpty() && passwords.isNotEmpty()) {
            val pair =
                usernames.flatMap { username -> passwords.map { password -> username to password } }
                    .minWithOrNull(
                        compareBy<Pair<AutofillFieldCandidate<T>, AutofillFieldCandidate<T>>> {
                            kotlin.math.abs(it.first.traversalIndex - it.second.traversalIndex)
                        }.thenByDescending {
                            maxOf(it.first.traversalIndex, it.second.traversalIndex)
                        },
                    )!!
            return AutofillFieldSelection(pair.first.value, pair.second.value)
        }
        return AutofillFieldSelection(
            username = usernames.lastOrNull()?.value,
            password = passwords.lastOrNull()?.value,
        )
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

    internal enum class FieldRole {
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
