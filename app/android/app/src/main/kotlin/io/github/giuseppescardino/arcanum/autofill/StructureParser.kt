package io.github.giuseppescardino.arcanum.autofill

import android.app.assist.AssistStructure
import android.text.InputType
import android.view.View
import android.view.autofill.AutofillId

/** Login fields found in a screen, plus who is asking. */
data class ParsedForm(
    val packageName: String,
    val webDomain: String?,
    val usernameIds: List<AutofillId>,
    val passwordIds: List<AutofillId>,
) {
    val allIds: List<AutofillId> get() = usernameIds + passwordIds
    val isFillable: Boolean get() = passwordIds.isNotEmpty() || usernameIds.isNotEmpty()
}

/**
 * Finds username/password fields using, in order: autofill hints, HTML
 * attributes (browsers), input types and finally id/hint text.
 */
object StructureParser {
    private enum class Kind { USERNAME, PASSWORD, OTHER }

    private val usernameWords = listOf("user", "email", "e-mail", "login", "account", "utente")
    private val passwordWords = listOf("pass", "pwd", "pin")

    fun parse(structure: AssistStructure): ParsedForm {
        val usernames = mutableListOf<AutofillId>()
        val passwords = mutableListOf<AutofillId>()
        val textFields = mutableListOf<AutofillId>()
        var domain: String? = null

        fun visit(node: AssistStructure.ViewNode) {
            node.webDomain?.takeIf { it.isNotBlank() }?.let { if (domain == null) domain = it }
            val id = node.autofillId
            if (id != null && node.autofillType == View.AUTOFILL_TYPE_TEXT && node.visibility == View.VISIBLE) {
                textFields += id
                when (classify(node)) {
                    Kind.PASSWORD -> passwords += id
                    Kind.USERNAME -> usernames += id
                    Kind.OTHER -> {}
                }
            }
            for (i in 0 until node.childCount) visit(node.getChildAt(i))
        }
        for (i in 0 until structure.windowNodeCount) visit(structure.getWindowNodeAt(i).rootViewNode)

        // Common pattern: an unlabeled text field right before the password.
        if (usernames.isEmpty() && passwords.isNotEmpty()) {
            val idx = textFields.indexOf(passwords.first())
            if (idx > 0 && textFields[idx - 1] !in passwords) usernames += textFields[idx - 1]
        }

        return ParsedForm(
            packageName = structure.activityComponent.packageName,
            webDomain = domain,
            usernameIds = usernames,
            passwordIds = passwords,
        )
    }

    private fun classify(node: AssistStructure.ViewNode): Kind {
        node.autofillHints?.forEach { hint ->
            val h = hint.lowercase()
            if (h.contains("password")) return Kind.PASSWORD
            if (h.contains("username") || h.contains("email")) return Kind.USERNAME
        }

        node.htmlInfo?.attributes?.forEach { attr ->
            val name = attr.first?.lowercase()
            val value = attr.second?.lowercase() ?: return@forEach
            if (name == "type" && value == "password") return Kind.PASSWORD
            if (name == "type" && value == "email") return Kind.USERNAME
            if (name == "autocomplete" && value.contains("password")) return Kind.PASSWORD
            if (name == "autocomplete" && (value.contains("username") || value.contains("email"))) {
                return Kind.USERNAME
            }
        }

        val type = node.inputType
        if (type and InputType.TYPE_MASK_CLASS == InputType.TYPE_CLASS_TEXT) {
            when (type and InputType.TYPE_MASK_VARIATION) {
                InputType.TYPE_TEXT_VARIATION_PASSWORD,
                InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD,
                InputType.TYPE_TEXT_VARIATION_WEB_PASSWORD -> return Kind.PASSWORD
                InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS,
                InputType.TYPE_TEXT_VARIATION_WEB_EMAIL_ADDRESS -> return Kind.USERNAME
            }
        }
        if (type and InputType.TYPE_MASK_CLASS == InputType.TYPE_CLASS_NUMBER &&
            type and InputType.TYPE_MASK_VARIATION == InputType.TYPE_NUMBER_VARIATION_PASSWORD
        ) {
            return Kind.PASSWORD
        }

        val text = listOfNotNull(node.idEntry, node.hint, node.contentDescription?.toString())
            .joinToString(" ")
            .lowercase()
        if (passwordWords.any { text.contains(it) }) return Kind.PASSWORD
        if (usernameWords.any { text.contains(it) }) return Kind.USERNAME
        return Kind.OTHER
    }
}
