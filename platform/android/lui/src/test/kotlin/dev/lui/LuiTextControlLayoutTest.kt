package dev.lui

import androidx.compose.foundation.layout.Box
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.SemanticsNode
import androidx.compose.ui.semantics.SemanticsOwner
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import app.cash.paparazzi.DeviceConfig
import app.cash.paparazzi.Paparazzi
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class LuiTextControlLayoutTest {
    @get:Rule val paparazzi = Paparazzi(deviceConfig = DeviceConfig.PIXEL_5.copy(softButtons = false))

    private fun nodes(root: SemanticsNode): List<SemanticsNode> =
        listOf(root) + root.children.flatMap(::nodes)

    @Test fun growingEditorRespectsColumnConstraints() {
        for (bounded in listOf(false, true)) {
            for (explicitHeight in listOf(false, true)) {
                val backend = LuiBackend()
                val ops = mutableListOf(
                    """{"op":"create-node","id":1,"kind":"scroll"}""",
                    """{"op":"set-prop","id":1,"property":"height","value":360}""",
                    """{"op":"create-node","id":2,"kind":"column"}""",
                    """{"op":"insert-child","parent":1,"child":2,"index":0}""",
                    """{"op":"create-node","id":3,"kind":"textarea"}""",
                    """{"op":"set-prop","id":3,"property":"grow","value":1}""",
                    """{"op":"set-prop","id":3,"property":"text","value":"Editable document"}""",
                    """{"op":"insert-child","parent":2,"child":3,"index":0}""",
                    """{"op":"create-node","id":4,"kind":"text"}""",
                    """{"op":"set-prop","id":4,"property":"text","value":"Following content"}""",
                    """{"op":"insert-child","parent":2,"child":4,"index":1}""",
                )
                if (bounded) ops += """{"op":"set-prop","id":2,"property":"height","value":320}"""
                if (explicitHeight) ops += """{"op":"set-prop","id":3,"property":"height","value":160}"""
                assertTrue(backend.applyBatch("""{"generation":1,"ops":[${ops.joinToString(",") }]}"""))
                var editor: Rect? = null
                var following: Rect? = null
                val view = ComposeView(paparazzi.context).apply { setContent {
                    val native = LocalView.current
                    LuiTheme {
                        Box(Modifier.onGloballyPositioned {
                            val owner = native.javaClass.methods.first { it.name == "getSemanticsOwner" }
                                .invoke(native) as SemanticsOwner
                            val all = nodes(owner.unmergedRootSemanticsNode)
                            editor = all.single { it.config.getOrNull(SemanticsProperties.EditableText) != null }.boundsInRoot
                            following = all.single {
                                it.config.getOrNull(SemanticsProperties.Text)?.any { text ->
                                    text.text == "Following content"
                                } == true
                            }.boundsInRoot
                        }) { backend.Content(1) }
                    }
                } }
                try {
                    paparazzi.snapshot(view, name = "growing-editor-$bounded-$explicitHeight")
                    val editorBounds = checkNotNull(editor)
                    val followingBounds = checkNotNull(following)
                    assertTrue("editor has visible height (bounded=$bounded, explicit=$explicitHeight)",
                        editorBounds.height > 0)
                    assertTrue("editor does not overlap following content (bounded=$bounded, explicit=$explicitHeight)",
                        followingBounds.top >= editorBounds.bottom)
                    if (bounded) {
                        assertEquals("growing editor fills the remaining bounded height",
                            320 * view.resources.displayMetrics.density,
                            followingBounds.bottom - editorBounds.top, 1f)
                    }
                } finally {
                    view.disposeComposition()
                }
            }
        }
    }

    @Test fun narrowPlaceholderRespectsTextControlLinePolicy() {
        for (kind in listOf("text-field", "secure-field", "input", "search-field", "combobox", "textarea")) {
            val backend = LuiBackend()
            val ops = mutableListOf("""{"op":"create-node","id":1,"kind":"column"}""")
            for (id in 2..3) {
                ops.add("""{"op":"create-node","id":$id,"kind":"$kind"}""")
                ops.add("""{"op":"set-prop","id":$id,"property":"width","value":80}""")
                ops.add("""{"op":"insert-child","parent":1,"child":$id,"index":${id - 2}}""")
            }
            ops.add("""{"op":"set-prop","id":3,"property":"placeholder","value":"A long placeholder that cannot fit in one narrow line"}""")
            assertTrue(backend.applyBatch("""{"generation":1,"ops":[${ops.joinToString(",")}]}"""))
            var heights = emptyList<Int>()
            val view = ComposeView(paparazzi.context).apply { setContent {
                val native = LocalView.current
                LuiTheme {
                    Box(Modifier.onGloballyPositioned {
                        val owner = native.javaClass.methods.first { it.name == "getSemanticsOwner" }
                            .invoke(native) as SemanticsOwner
                        heights = nodes(owner.unmergedRootSemanticsNode)
                            .filter { it.config.getOrNull(SemanticsProperties.EditableText) != null }
                            .map { it.size.height }
                    }) { backend.Content(1) }
                }
            } }
            try {
                paparazzi.snapshot(view, name = "narrow-$kind-placeholder")
                assertEquals("both $kind controls were measured", 2, heights.size)
                assertTrue("empty $kind has an intrinsic height", heights[0] > 0)
                if (kind == "textarea") {
                    assertTrue("textarea placeholder still wraps: $heights", heights[1] > heights[0])
                } else {
                    assertEquals("single-line $kind placeholder must not inflate height", heights[0], heights[1])
                }
            } finally {
                view.disposeComposition()
            }
        }
    }
}
