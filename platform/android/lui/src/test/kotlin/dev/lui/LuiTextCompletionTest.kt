package dev.lui

import androidx.compose.ui.input.key.KeyEvent
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.input.TextFieldValue
import app.cash.paparazzi.Paparazzi
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

class LuiTextCompletionTest {
    @get:Rule val paparazzi = Paparazzi()

    private val textKinds = listOf(LuiNodeKind.textField, LuiNodeKind.secureField,
        LuiNodeKind.input, LuiNodeKind.searchField, LuiNodeKind.textarea)
    private fun escape(action: Int = android.view.KeyEvent.ACTION_DOWN, repeat: Int = 0, modifiers: Int = 0) =
        KeyEvent(android.view.KeyEvent(0, 0, action, android.view.KeyEvent.KEYCODE_ESCAPE, repeat, modifiers))

    @Test fun `only opted in enabled noncomposing fields own ordinary Escape`() {
        for (kind in textKinds) {
            val node = LuiNode(kind)
            val value = TextFieldValue("draft", selection = TextRange(1, 3))
            assertFalse(luiTextDismissRequested(node, value, escape()))
            node.properties["dismiss-enabled"] = LuiWireValue.Bool(true)
            assertTrue(luiTextDismissRequested(node, value, escape()))
            assertFalse(luiTextDismissRequested(node, value.copy(composition = TextRange(0, 3)), escape()))
            for (modifiers in listOf(android.view.KeyEvent.META_SHIFT_ON, android.view.KeyEvent.META_CTRL_ON,
                android.view.KeyEvent.META_META_ON, android.view.KeyEvent.META_ALT_ON)) {
                assertFalse(luiTextDismissRequested(node, value, escape(modifiers = modifiers)))
            }
            assertFalse(luiTextDismissRequested(node, value, escape(repeat = 1)))
            assertFalse(luiTextDismissRequested(node, value, escape(action = android.view.KeyEvent.ACTION_UP)))
            node.properties["enabled"] = LuiWireValue.Bool(false)
            assertFalse(luiTextDismissRequested(node, value, escape()))
            node.properties.remove("enabled")
            node.properties.remove("dismiss-enabled")
            assertFalse(luiTextDismissRequested(node, value, escape()))
            assertEquals(TextRange(1, 3), value.selection)
        }
    }

    @Test fun `completion owns synchronous blur exactly once and fresh editing or focus releases it`() {
        val lifecycle = LuiTextBlurLifecycle()
        val events = mutableListOf<String>()
        fun focus(next: Boolean, enabled: Boolean = true, subscribed: Boolean = true, composing: Boolean = false) =
            lifecycle.focusChanged(next, enabled, subscribed, composing) { events += "submit" }
        focus(false)
        assertTrue(events.isEmpty())
        focus(true)
        lifecycle.beforeDismiss { events += "dismiss"; focus(false) }
        lifecycle.beforeSubmit { events += "late submit" }
        lifecycle.beforeDismiss { events += "duplicate dismiss" }
        assertEquals(listOf("dismiss"), events)
        focus(true)
        focus(false)
        assertEquals(listOf("dismiss", "submit"), events)
        events.clear()
        focus(true)
        lifecycle.beforeSubmit { events += "submit"; focus(false) }
        assertEquals(listOf("submit"), events)
        events.clear()
        focus(true)
        lifecycle.beforeDismiss { events += "dismiss" }
        focus(true)
        focus(false)
        assertEquals("duplicate focused notifications must not retire cancellation", listOf("dismiss"), events)
        events.clear()
        focus(true)
        lifecycle.beforeDismiss { events += "dismiss" }
        lifecycle.edited()
        focus(false)
        assertEquals(listOf("dismiss", "submit"), events)
        events.clear()
        for (guard in listOf("disabled", "composing", "unsubscribed")) {
            focus(true)
            focus(false, enabled = guard != "disabled", subscribed = guard != "unsubscribed",
                composing = guard == "composing")
        }
        assertTrue(events.isEmpty())
    }

    @Test fun `native composition finish cannot revive a canceled draft but new composition can`() {
        val lifecycle = LuiTextBlurLifecycle()
        val events = mutableListOf<String>()
        fun focus(next: Boolean) = lifecycle.focusChanged(next, true, true, false) { events += "submit" }
        focus(true)
        lifecycle.beforeDismiss { events += "dismiss"; focus(false) }
        lifecycle.compositionChanged(false)
        lifecycle.beforeSubmit { events += "late submit" }
        lifecycle.beforeDismiss { events += "duplicate dismiss" }
        assertEquals(listOf("dismiss"), events)
        lifecycle.compositionChanged(true)
        lifecycle.compositionChanged(false)
        lifecycle.beforeDismiss { events += "new dismiss" }
        assertEquals(listOf("dismiss", "new dismiss"), events)
    }

    @Test fun `text completion flags validate their bool type and five text kinds transactionally`() {
        for (kind in textKinds) {
            val backend = LuiBackend()
            assertTrue(backend.lastError, backend.applyBatch("""{"generation":1,"ops":[
                {"op":"create-node","id":1,"kind":"${kind.wireName}"},
                {"op":"set-prop","id":1,"property":"dismiss-enabled","value":true},
                {"op":"set-prop","id":1,"property":"submit-on-blur","value":true}
            ]}"""))
            assertFalse(backend.applyBatch("""{"generation":2,"ops":[
                {"op":"set-prop","id":1,"property":"text","value":"must roll back"},
                {"op":"set-prop","id":1,"property":"dismiss-enabled","value":"true"}
            ]}"""))
            assertEquals("", backend.node(1)!!.text())
        }
        for (kind in listOf("button", "combobox", "text")) {
            val backend = LuiBackend()
            assertFalse(backend.applyBatch("""{"generation":1,"ops":[
                {"op":"create-node","id":1,"kind":"$kind"},
                {"op":"set-prop","id":1,"property":"dismiss-enabled","value":false}
            ]}"""))
            assertNull(backend.node(1))
        }
    }
}
