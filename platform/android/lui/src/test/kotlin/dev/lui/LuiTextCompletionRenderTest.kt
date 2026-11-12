package dev.lui

import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsNode
import androidx.compose.ui.semantics.SemanticsOwner
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.text.TextRange
import app.cash.paparazzi.Paparazzi
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

class LuiTextCompletionRenderTest {
    @get:Rule val paparazzi = Paparazzi()

    @Test fun `native text aliases cancel without saving and accepted Enter submits once`() {
        for (kind in listOf("text-field", "secure-field", "input", "search-field", "textarea")) {
            val events = mutableListOf<LuiEvent>()
            var clearFocus: () -> Unit = {}
            var clearOnSubmit = false
            val backend = LuiBackend(onEvent = {
                events += it
                if (it is LuiEvent.Dismiss || (clearOnSubmit && it is LuiEvent.Submit)) clearFocus()
            })
            val borderless = if (kind == "input") "composer-input" else ""
            assertTrue(backend.lastError, backend.applyBatch("""{"generation":1,"ops":[
                {"op":"create-node","id":1,"kind":"$kind"},
                {"op":"set-prop","id":1,"property":"text","value":"draft"},
                {"op":"set-prop","id":1,"property":"style-class","value":"$borderless"},
                {"op":"set-prop","id":1,"property":"dismiss-enabled","value":true},
                {"op":"set-prop","id":1,"property":"submit-enabled","value":true},
                {"op":"set-prop","id":1,"property":"submit-on-blur","value":true}
            ]}"""))
            var checked = false
            val view = ComposeView(paparazzi.context).apply { setContent {
                val native = LocalView.current
                val focusManager = LocalFocusManager.current
                clearFocus = { focusManager.clearFocus(force = true) }
                LuiTheme { Box { backend.Content(1) } }
                LaunchedEffect(Unit) {
                    suspend fun settle() { repeat(3) { withFrameNanos {} } }
                    fun nodes(root: SemanticsNode): List<SemanticsNode> = listOf(root) + root.children.flatMap(::nodes)
                    fun field(): SemanticsNode {
                        val owner = native.javaClass.methods.first { it.name == "getSemanticsOwner" }.invoke(native) as SemanticsOwner
                        return nodes(owner.unmergedRootSemanticsNode).first {
                            it.config.getOrNull(SemanticsProperties.EditableText) != null
                        }
                    }
                    fun key(code: Int) {
                        native.dispatchKeyEvent(android.view.KeyEvent(android.view.KeyEvent.ACTION_DOWN, code))
                        native.dispatchKeyEvent(android.view.KeyEvent(android.view.KeyEvent.ACTION_UP, code))
                    }
                    suspend fun focus() {
                        assertTrue(field().config[SemanticsActions.RequestFocus].action!!.invoke())
                        settle()
                    }
                    settle(); focus(); events.clear()
                    key(android.view.KeyEvent.KEYCODE_ESCAPE); settle()
                    assertEquals("cancel then synchronous blur must only dismiss: $kind", listOf(LuiEvent.Dismiss(1)), events)
                    assertEquals("cancel preserves the controlled draft", "draft", backend.node(1)!!.text())
                    focus(); events.clear(); clearFocus(); settle()
                    assertEquals("a fresh ordinary focus loss commits once: $kind", listOf(LuiEvent.Submit(1)), events)
                    assertTrue(backend.applyBatch("""{"generation":2,"ops":[
                        {"op":"remove-prop","id":1,"property":"dismiss-enabled"}
                    ]}"""))
                    settle(); focus(); events.clear()
                    key(android.view.KeyEvent.KEYCODE_ESCAPE); settle()
                    assertTrue("removed cancellation cannot consume a native key", events.isEmpty())
                    clearFocus(); settle()
                    assertEquals(listOf(LuiEvent.Submit(1)), events)
                    val enterOps = if (kind == "textarea")
                        """,{"op":"set-prop","id":1,"property":"submit-on-enter","value":true}""" else ""
                    assertTrue(backend.applyBatch("""{"generation":3,"ops":[
                        {"op":"set-prop","id":1,"property":"dismiss-enabled","value":true}$enterOps
                    ]}"""))
                    settle(); focus(); events.clear(); clearOnSubmit = true
                    key(android.view.KeyEvent.KEYCODE_ENTER); settle()
                    assertEquals("Enter and its blur are one acceptance: $kind", listOf(LuiEvent.Submit(1)), events)
                    if (kind != "textarea") {
                        focus(); events.clear()
                        assertTrue(field().config[SemanticsActions.OnImeAction].action!!.invoke())
                        settle()
                        assertEquals("IME acceptance and its blur are one submission: $kind", listOf(LuiEvent.Submit(1)), events)
                    }
                    clearOnSubmit = false
                    focus(); events.clear()
                    assertTrue(field().config[SemanticsActions.SetSelection].action!!.invoke(1, 3, false))
                    settle()
                    assertTrue("selection-only native updates must not emit TextChanged", events.isEmpty())
                    assertTrue(backend.applyBatch("""{"generation":4,"ops":[
                        {"op":"set-prop","id":1,"property":"text","value":"fresh"}
                    ]}"""))
                    settle()
                    assertEquals(TextRange(1, 3), field().config[SemanticsProperties.TextSelectionRange])
                    assertTrue("controlled echoes must not manufacture input events", events.isEmpty())
                    assertTrue(backend.applyBatch("""{"generation":5,"ops":[
                        {"op":"set-prop","id":1,"property":"enabled","value":false}
                    ]}"""))
                    settle(); key(android.view.KeyEvent.KEYCODE_ESCAPE); clearFocus(); settle()
                    assertTrue("disabling a retained field must neither cancel nor blur-submit", events.isEmpty())
                    checked = true
                }
            } }
            paparazzi.luiFrames(view, name = "text-completion-$kind", end = 2_500, fps = 30)
            assertTrue("native completion scenario reached every assertion: $kind", checked)
        }
    }
}
