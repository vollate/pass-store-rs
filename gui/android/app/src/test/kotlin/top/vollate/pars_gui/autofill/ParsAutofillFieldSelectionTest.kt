package top.vollate.pars_gui.autofill

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import top.vollate.pars_gui.autofill.ParsAutofillRequestParser.AutofillFieldCandidate
import top.vollate.pars_gui.autofill.ParsAutofillRequestParser.FieldRole

class ParsAutofillFieldSelectionTest {
    @Test
    fun `focused active form wins when one page has multiple login methods`() {
        val selected =
            ParsAutofillRequestParser.selectAutofillFields(
                listOf(
                    field("hidden-user", FieldRole.Username, 3, visible = false),
                    field("hidden-pass", FieldRole.Password, 4, visible = false),
                    field("visible-user", FieldRole.Username, 9, focused = true),
                    field("visible-pass", FieldRole.Password, 10),
                ),
            )

        assertEquals("visible-user", selected.username)
        assertEquals("visible-pass", selected.password)
    }

    @Test
    fun `latest adjacent visible pair wins when browser omits focus state`() {
        val selected =
            ParsAutofillRequestParser.selectAutofillFields(
                listOf(
                    field("old-user", FieldRole.Username, 3),
                    field("old-pass", FieldRole.Password, 4),
                    field("current-user", FieldRole.Username, 9),
                    field("current-pass", FieldRole.Password, 10),
                ),
            )

        assertEquals("current-user", selected.username)
        assertEquals("current-pass", selected.password)
    }

    @Test
    fun `username-only step remains fillable`() {
        val selected =
            ParsAutofillRequestParser.selectAutofillFields(
                listOf(field("username-step", FieldRole.Username, 7, focused = true)),
            )

        assertEquals("username-step", selected.username)
        assertNull(selected.password)
    }

    @Test
    fun `password-only second step remains fillable`() {
        val selected =
            ParsAutofillRequestParser.selectAutofillFields(
                listOf(field("password-step", FieldRole.Password, 12, focused = true)),
            )

        assertNull(selected.username)
        assertEquals("password-step", selected.password)
    }

    private fun field(
        value: String,
        role: FieldRole,
        index: Int,
        focused: Boolean = false,
        visible: Boolean = true,
    ): AutofillFieldCandidate<String> =
        AutofillFieldCandidate(
            value = value,
            role = role,
            traversalIndex = index,
            focused = focused,
            visible = visible,
        )
}
