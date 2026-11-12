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
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.TextRange
import app.cash.paparazzi.Paparazzi
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

class LuiTextCompletionRenderTest {
    @get:Rule val paparazzi = Paparazzi()

    // These non-text control events have no Unicode output. Layoutlib has no
    // physical device keymap; dispatch still traverses the native Compose view.
    private fun controlKey(action: Int, code: Int) = object : android.view.KeyEvent(action, code) {
        override fun getUnicodeChar(): Int = 0
        override fun getUnicodeChar(metaState: Int): Int = 0
    }

    @Test fun `text field owns native cancellation and completion`() = nativeAlias("text-field")
    @Test fun `secure field owns native cancellation and completion`() = nativeAlias("secure-field")
    @Test fun `input owns native cancellation and completion`() = nativeAlias("input")
    @Test fun `search field owns native cancellation and completion`() = nativeAlias("search-field")
    @Test fun `textarea owns native cancellation and completion`() = nativeAlias("textarea")

    private fun nativeAlias(kind: String) {
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
                    native.dispatchKeyEvent(controlKey(android.view.KeyEvent.ACTION_DOWN, code))
                    native.dispatchKeyEvent(controlKey(android.view.KeyEvent.ACTION_UP, code))
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
                // Original-text traversal selects a real range without
                // requesting the separate smart-selection toolbar service.
                assertTrue(field().config[SemanticsActions.SetSelection].action!!.invoke(1, 3, true))
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

    @Test fun `canceled native draft survives model patches and removal until genuine editing or fresh focus`() {
        val events = mutableListOf<LuiEvent>()
        var clearFocus: () -> Unit = {}
        var blurOnDismiss = false
        val backend = LuiBackend(onEvent = {
            events += it
            if (blurOnDismiss && it is LuiEvent.Dismiss) clearFocus()
        })
        assertTrue(backend.applyBatch("""{"generation":1,"ops":[
            {"op":"create-node","id":1,"kind":"text-field"},
            {"op":"set-prop","id":1,"property":"text","value":"draft"},
            {"op":"set-prop","id":1,"property":"dismiss-enabled","value":true},
            {"op":"set-prop","id":1,"property":"submit-enabled","value":true},
            {"op":"set-prop","id":1,"property":"submit-on-blur","value":true}
        ]}"""))
        var checked = false
        val view = ComposeView(paparazzi.context).apply { setContent {
            val native = LocalView.current
            val manager = LocalFocusManager.current
            clearFocus = { manager.clearFocus(force = true) }
            LuiTheme { Box { backend.Content(1) } }
            LaunchedEffect(Unit) {
                suspend fun settle() { repeat(3) { withFrameNanos {} } }
                fun nodes(node: SemanticsNode): List<SemanticsNode> = listOf(node) + node.children.flatMap(::nodes)
                fun field(): SemanticsNode {
                    val owner = native.javaClass.methods.first { it.name == "getSemanticsOwner" }.invoke(native) as SemanticsOwner
                    return nodes(owner.unmergedRootSemanticsNode).first {
                        it.config.getOrNull(SemanticsProperties.EditableText) != null
                    }
                }
                fun key(code: Int) {
                    native.dispatchKeyEvent(controlKey(android.view.KeyEvent.ACTION_DOWN, code))
                    native.dispatchKeyEvent(controlKey(android.view.KeyEvent.ACTION_UP, code))
                }
                settle()
                assertTrue(field().config[SemanticsActions.RequestFocus].action!!.invoke())
                settle(); events.clear()
                key(android.view.KeyEvent.KEYCODE_ESCAPE); settle()
                assertEquals(listOf(LuiEvent.Dismiss(1)), events)
                events.clear()
                key(android.view.KeyEvent.KEYCODE_ESCAPE)
                key(android.view.KeyEvent.KEYCODE_ENTER); settle()
                assertTrue("duplicate cancellation and late native Enter cannot complete the draft", events.isEmpty())
                assertTrue(backend.applyBatch("""{"generation":2,"ops":[
                    {"op":"set-prop","id":1,"property":"text","value":"authoritative"}
                ]}"""))
                settle()
                assertEquals("authoritative", field().config[SemanticsProperties.EditableText].text)
                key(android.view.KeyEvent.KEYCODE_ESCAPE)
                key(android.view.KeyEvent.KEYCODE_ENTER); settle()
                assertTrue("model patches must not rearm a canceled field", events.isEmpty())
                assertTrue(backend.applyBatch("""{"generation":3,"ops":[
                    {"op":"remove-prop","id":1,"property":"dismiss-enabled"}
                ]}"""))
                settle(); key(android.view.KeyEvent.KEYCODE_ESCAPE); key(android.view.KeyEvent.KEYCODE_ENTER); settle()
                assertTrue("handler removal must not revive the canceled draft", events.isEmpty())
                assertTrue(backend.applyBatch("""{"generation":4,"ops":[
                    {"op":"set-prop","id":1,"property":"dismiss-enabled","value":true}
                ]}"""))
                settle()
                assertTrue(field().config[SemanticsActions.SetText].action!!.invoke(AnnotatedString("edited")))
                settle()
                assertEquals(listOf(LuiEvent.TextChanged(1, "edited")), events)
                events.clear(); blurOnDismiss = true
                key(android.view.KeyEvent.KEYCODE_ESCAPE); settle()
                assertEquals("a genuine edit rearms cancellation before its synchronous blur", listOf(LuiEvent.Dismiss(1)), events)
                assertEquals("cancellation really loses native focus", false,
                    field().config[SemanticsProperties.Focused])
                events.clear()
                assertTrue(field().config[SemanticsActions.OnImeAction].action!!.invoke())
                settle()
                assertTrue("late IME acceptance after canceled blur cannot save: events=$events, " +
                    "focused=${field().config[SemanticsProperties.Focused]}, " +
                    "text=${field().config[SemanticsProperties.EditableText].text}", events.isEmpty())
                assertTrue(field().config[SemanticsActions.RequestFocus].action!!.invoke())
                settle(); clearFocus(); settle()
                assertEquals("fresh focus starts a new submittable interval", listOf(LuiEvent.Submit(1)), events)
                checked = true
            }
        } }
        paparazzi.luiFrames(view, name = "native-canceled-text-interval", end = 2_500, fps = 30)
        assertTrue(checked)
    }
}
