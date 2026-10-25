package dev.lui

import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsNode
import androidx.compose.ui.semantics.SemanticsOwner
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import app.cash.paparazzi.Paparazzi
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

class LuiNavigationRoleTest {
    @get:Rule val paparazzi = Paparazzi()

    @Test fun `navigation subscriptions mount canonical controls and preserve native button Enter`() {
        var presses = 0
        val backend = LuiBackend(onEvent = { if (it is LuiEvent.Press) presses++ })
        val kinds = listOf("button", "text-field", "secure-field", "input", "search-field", "textarea")
        val operations = kinds.flatMapIndexed { index, kind ->
            listOf("""{"op":"create-node","id":${index + 1},"kind":"$kind"}""",
                """{"op":"set-prop","id":${index + 1},"property":"navigate-enabled","value":true}""")
        } + listOf("""{"op":"set-prop","id":1,"property":"text","value":"Navigate"}""",
            """{"op":"set-prop","id":1,"property":"press-enabled","value":true}""")
        assertTrue(backend.lastError, backend.applyBatch("""{"generation":1,"ops":[${operations.joinToString(",") }]}"""))
        var checked = false
        val view = ComposeView(paparazzi.context).apply { setContent {
            val native = LocalView.current
            LuiTheme { Box { backend.Content(1) } }
            LaunchedEffect(Unit) {
                repeat(3) { withFrameNanos {} }
                val owner = native.javaClass.methods.first { it.name == "getSemanticsOwner" }.invoke(native) as SemanticsOwner
                fun nodes(node: SemanticsNode): List<SemanticsNode> = listOf(node) + node.children.flatMap(::nodes)
                val button = nodes(owner.unmergedRootSemanticsNode).first {
                    it.config.getOrNull(SemanticsActions.OnClick) != null
                }
                assertTrue(button.config[SemanticsActions.RequestFocus].action!!.invoke())
                repeat(2) { withFrameNanos {} }
                native.dispatchKeyEvent(android.view.KeyEvent(android.view.KeyEvent.ACTION_DOWN, android.view.KeyEvent.KEYCODE_ENTER))
                native.dispatchKeyEvent(android.view.KeyEvent(android.view.KeyEvent.ACTION_UP, android.view.KeyEvent.KEYCODE_ENTER))
                repeat(3) { withFrameNanos {} }
                assertEquals("native keyboard activation remains active", 1, presses)
                checked = true
            }
        } }
        paparazzi.luiFrames(view, name = "native-navigation-subscription", end = 600, fps = 30)
        assertTrue(checked)
        assertFalse(backend.applyBatch("""{"generation":2,"ops":[
            {"op":"set-prop","id":1,"property":"text","value":"must roll back"},
            {"op":"create-node","id":100,"kind":"text"},
            {"op":"set-prop","id":100,"property":"navigate-enabled","value":true}
        ]}"""))
        assertEquals("Navigate", backend.node(1)!!.text())
        assertNull(backend.node(100))
    }

    @Test fun `shared navigation rows use native selected click and accessibility semantics`() {
        lateinit var backend: LuiBackend
        var clicked = false
        backend = LuiBackend(onEvent = {
            if (it is LuiEvent.Press && it.node == 2L) {
                clicked = true
                assertTrue(backend.applyBatch("""{"generation":2,"ops":[
                    {"op":"set-prop","id":2,"property":"selected","value":true}
                ]}"""))
            }
        })
        assertTrue(backend.lastError, backend.applyBatch("""{"generation":1,"ops":[
            {"op":"create-node","id":1,"kind":"column"},
            {"op":"create-node","id":2,"kind":"list-item"},
            {"op":"set-prop","id":2,"property":"role","value":"navigation"},
            {"op":"set-prop","id":2,"property":"accessibility-identifier","value":"nav-row"},
            {"op":"set-prop","id":2,"property":"text","value":"Virtual list"},
            {"op":"set-prop","id":2,"property":"selected","value":false},
            {"op":"set-prop","id":2,"property":"press-enabled","value":true},
            {"op":"insert-child","parent":1,"child":2,"index":0},
            {"op":"create-node","id":3,"kind":"list-item"},
            {"op":"set-prop","id":3,"property":"role","value":"navigation-heading"},
            {"op":"set-prop","id":3,"property":"accessibility-identifier","value":"nav-heading"},
            {"op":"set-prop","id":3,"property":"text","value":"Sections"},
            {"op":"insert-child","parent":1,"child":3,"index":1}
        ]}"""))
        var checked = false
        val view = ComposeView(paparazzi.context).apply { setContent {
            val native = LocalView.current
            LuiTheme { Box { backend.Content(1) } }
            LaunchedEffect(Unit) {
                repeat(3) { withFrameNanos {} }
                val owner = native.javaClass.methods.first { it.name == "getSemanticsOwner" }.invoke(native) as SemanticsOwner
                fun nodes(node: SemanticsNode): List<SemanticsNode> = listOf(node) + node.children.flatMap(::nodes)
                fun named(name: String) = nodes(owner.unmergedRootSemanticsNode).first {
                    it.config.getOrNull(SemanticsProperties.TestTag) == name
                }
                val row = named("nav-row")
                assertEquals(Role.Tab, row.config.getOrNull(SemanticsProperties.Role))
                assertEquals(false, row.config.getOrNull(SemanticsProperties.Selected))
                assertTrue(row.config[SemanticsActions.OnClick].action!!.invoke())
                repeat(3) { withFrameNanos {} }
                assertTrue(clicked)
                assertEquals(true, named("nav-row").config.getOrNull(SemanticsProperties.Selected))
                assertNotNull(named("nav-heading").config.getOrNull(SemanticsProperties.Heading))
                checked = true
            }
        } }
        paparazzi.luiFrames(view, name = "shared-native-navigation", end = 600, fps = 30)
        assertTrue(checked)
        assertFalse("unknown role values remain rejected", backend.applyBatch("""{"generation":3,"ops":[
            {"op":"set-prop","id":2,"property":"role","value":"arbitrary-role"}
        ]}"""))
        assertEquals("navigation", backend.tree.node(2)!!.properties["role"]!!.stringValue)
    }
}
