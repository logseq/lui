package dev.lui

import androidx.compose.foundation.layout.Box
import androidx.compose.ui.Modifier
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
