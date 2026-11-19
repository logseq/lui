package dev.lui

import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsNode
import androidx.compose.ui.semantics.SemanticsOwner
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import app.cash.paparazzi.Paparazzi
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

class LuiListLayoutTest {
    @get:Rule val paparazzi = Paparazzi()

    private fun nodes(root: SemanticsNode): List<SemanticsNode> = listOf(root) + root.children.flatMap(::nodes)

    private fun backend(count: Int, bounded: Boolean, events: MutableList<LuiEvent>): LuiBackend {
        val backend = LuiBackend(onEvent = events::add)
        val ops = mutableListOf(
            """{"op":"create-node","id":1,"kind":"scroll"}""",
            """{"op":"set-prop","id":1,"property":"height","value":240}""",
            """{"op":"create-node","id":2,"kind":"list"}""",
            """{"op":"insert-child","parent":1,"child":2,"index":0}""",
        )
        if (bounded) ops += """{"op":"set-prop","id":2,"property":"height","value":120}"""
        repeat(count) { index ->
            val id = index + 3
            ops += """{"op":"create-node","id":$id,"kind":"list-item"}"""
            ops += """{"op":"set-prop","id":$id,"property":"text","value":"Row $index"}"""
            ops += """{"op":"set-prop","id":$id,"property":"height","value":80}"""
            ops += """{"op":"set-prop","id":$id,"property":"press-enabled","value":true}"""
            ops += """{"op":"insert-child","parent":2,"child":$id,"index":$index}"""
        }
        assertTrue(backend.applyBatch("""{"generation":1,"ops":[${ops.joinToString(",") }]}"""))
        return backend
    }

    @Test fun `card and panel flow vertically and honor zero overrides`() {
        val cases = listOf("card" to 16, "panel" to 12, "card" to 0, "panel" to 0)
        val backend = LuiBackend(onEvent = {})
        val ops = mutableListOf("""{"op":"create-node","id":1,"kind":"column"}""")
        cases.forEachIndexed { index, (kind, padding) ->
            val id = (index + 1) * 10
            ops += """{"op":"create-node","id":$id,"kind":"$kind"}"""
            ops += """{"op":"insert-child","parent":1,"child":$id,"index":$index}"""
            ops += """{"op":"set-prop","id":$id,"property":"width","value":200}"""
            if (padding == 0) {
                ops += """{"op":"set-prop","id":$id,"property":"padding","value":0}"""
                ops += """{"op":"set-prop","id":$id,"property":"gap","value":0}"""
            }
            listOf("First", "Second").forEachIndexed { childIndex, text ->
                val child = id + childIndex + 1
                ops += """{"op":"create-node","id":$child,"kind":"text"}"""
                ops += """{"op":"set-prop","id":$child,"property":"text","value":"$text-$index"}"""
                ops += """{"op":"set-prop","id":$child,"property":"height","value":24}"""
                if (childIndex == 1) ops += """{"op":"set-prop","id":$child,"property":"width","value":40}"""
                ops += """{"op":"insert-child","parent":$id,"child":$child,"index":$childIndex}"""
            }
        }
        assertTrue(backend.applyBatch("""{"generation":1,"ops":[${ops.joinToString(",")}]}"""))
        var checked = false
        val view = ComposeView(paparazzi.context).apply { setContent {
            val native = LocalView.current
            val density = androidx.compose.ui.platform.LocalDensity.current.density
            LuiTheme { Box { backend.Content(1) } }
            LaunchedEffect(Unit) {
                repeat(3) { withFrameNanos {} }
                val owner = native.javaClass.methods.first { it.name == "getSemanticsOwner" }.invoke(native) as SemanticsOwner
                val all = nodes(owner.unmergedRootSemanticsNode)
                fun bounds(text: String) = all.first {
                    it.config.getOrNull(SemanticsProperties.Text)?.any { value -> value.text == text } == true
                }.boundsInRoot
                cases.forEachIndexed { index, (kind, padding) ->
                    val first = bounds("First-$index")
                    val second = bounds("Second-$index")
                    val gap = if (padding == 0) 0 else 12
                    assertEquals("$kind padding", padding * density, first.left, 1f)
                    assertEquals("$kind flow gap", (24 + gap) * density, second.top - first.top, 1f)
                    assertEquals("$kind stretches unspecified widths", (200 - 2 * padding) * density, first.width, 1f)
                    assertEquals("$kind preserves explicit child widths", 40 * density, second.width, 1f)
                }
                checked = true
            }
        } }
        paparazzi.luiFrames(view, name = "surface-flow", end = 500, fps = 30)
        assertTrue("surface geometry checked", checked)
    }
    @Test fun `ordinary list inside native scroll has intrinsic height and retains row interaction`() {
        val events = mutableListOf<LuiEvent>()
        val backend = backend(4, false, events)
        var checked = false
        val view = ComposeView(paparazzi.context).apply { setContent {
            val native = LocalView.current
            LuiTheme { Box { backend.Content(1) } }
            LaunchedEffect(Unit) {
                repeat(3) { withFrameNanos {} }
                val owner = native.javaClass.methods.first { it.name == "getSemanticsOwner" }.invoke(native) as SemanticsOwner
                val all = nodes(owner.unmergedRootSemanticsNode)
                assertEquals("the outer scroll owns vertical scrolling", 1,
                    all.count { it.config.getOrNull(SemanticsProperties.VerticalScrollAxisRange) != null })
                assertTrue("intrinsic rows contribute their complete scroll height", all.firstNotNullOf {
                    it.config.getOrNull(SemanticsProperties.VerticalScrollAxisRange)
                }.maxValue() > 0)
                assertEquals("all intrinsic rows are composed", 4,
                    all.count { it.config.getOrNull(SemanticsActions.OnClick) != null })
                assertTrue("intrinsic list retains native collection accessibility", all.any {
                    it.config.getOrNull(SemanticsProperties.CollectionInfo)?.rowCount == 4
                })
                assertTrue(all.last { it.config.getOrNull(SemanticsActions.OnClick) != null }
                    .config[SemanticsActions.OnClick].action!!.invoke())
                assertEquals(listOf(LuiEvent.Press(6)), events.filterIsInstance<LuiEvent.Press>())
                checked = true
            }
        } }
        paparazzi.luiFrames(view, name = "intrinsic-list-under-scroll", end = 500, fps = 30)
        assertTrue(checked)
    }

    @Test fun `explicitly bounded ordinary list retains native lazy scroll geometry`() {
        val backend = backend(40, true, mutableListOf())
        var checked = false
        val view = ComposeView(paparazzi.context).apply { setContent {
            val native = LocalView.current
            LuiTheme { Box { backend.Content(2) } }
            LaunchedEffect(Unit) {
                repeat(3) { withFrameNanos {} }
                val owner = native.javaClass.methods.first { it.name == "getSemanticsOwner" }.invoke(native) as SemanticsOwner
                fun all() = nodes(owner.unmergedRootSemanticsNode)
                val list = all().first { it.config.getOrNull(SemanticsActions.ScrollToIndex) != null }
                assertTrue(list.config[SemanticsActions.ScrollToIndex].action!!.invoke(39))
                repeat(5) { withFrameNanos {} }
                val last = all().first {
                    it.config.getOrNull(SemanticsProperties.Text)?.any { t -> t.text == "Row 39" } == true
                }
                assertTrue("last row actually enters native viewport", last.boundsInRoot.top >= list.boundsInRoot.top &&
                    last.boundsInRoot.top < list.boundsInRoot.bottom)
                checked = true
            }
        } }
        paparazzi.luiFrames(view, name = "bounded-list-native-scroll", end = 600, fps = 30)
        assertTrue(checked)
    }
}
