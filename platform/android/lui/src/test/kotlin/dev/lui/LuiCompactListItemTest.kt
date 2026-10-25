package dev.lui

import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsNode
import androidx.compose.ui.semantics.SemanticsOwner
import androidx.compose.ui.semantics.getOrNull
import app.cash.paparazzi.Paparazzi
import app.cash.paparazzi.Snapshot
import app.cash.paparazzi.SnapshotHandler
import java.awt.image.BufferedImage
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

class LuiCompactListItemTest {
    private var image: BufferedImage? = null
    @get:Rule val paparazzi = Paparazzi(snapshotHandler = object : SnapshotHandler {
        override fun newFrameHandler(snapshot: Snapshot, frameCount: Int, fps: Int) = object : SnapshotHandler.FrameHandler {
            override fun handle(image: BufferedImage) { this@LuiCompactListItemTest.image = image }
            override fun close() {}
        }
        override fun close() {}
    })

    @Test fun `authored compact row paints readable glyphs and keeps native press behavior`() {
        var pressed = false
        val backend = LuiBackend(onEvent = { if (it == LuiEvent.Press(100)) pressed = true })
        val ops = mutableListOf(
            """{"op":"create-node","id":1,"kind":"virtual-list"}""",
            """{"op":"set-prop","id":1,"property":"height","value":112}""",
            """{"op":"set-prop","id":1,"property":"item-extent","value":28}""",
            """{"op":"set-prop","id":1,"property":"virtual-total-count","value":4}""",
            """{"op":"set-prop","id":1,"property":"virtual-generation","value":1}""",
            """{"op":"set-prop","id":1,"property":"virtual-indices","value":"[0,1,2,3]"}""",
        )
        repeat(4) { index ->
            val id = index + 100
            ops += """{"op":"create-node","id":$id,"kind":"list-item"}"""
            ops += """{"op":"set-prop","id":$id,"property":"height","value":28}"""
            ops += """{"op":"set-prop","id":$id,"property":"text","value":"Visible row $index"}"""
            ops += """{"op":"set-prop","id":$id,"property":"press-enabled","value":true}"""
            ops += """{"op":"insert-child","parent":1,"child":$id,"index":$index}"""
        }
        assertTrue(backend.applyBatch("""{"generation":1,"ops":[${ops.joinToString(",") }]}"""))
        var width = 0
        var rowHeight = 0
        val view = ComposeView(paparazzi.context).apply { setContent {
            val native = LocalView.current
            LuiTheme { Box { Box(Modifier.onSizeChanged { rowHeight = it.height }) { backend.Content(1) } } }
            LaunchedEffect(Unit) {
                repeat(3) { withFrameNanos {} }
                width = native.width
                val owner = native.javaClass.methods.first { it.name == "getSemanticsOwner" }.invoke(native) as SemanticsOwner
                fun nodes(n: SemanticsNode): List<SemanticsNode> = listOf(n) + n.children.flatMap(::nodes)
                val row = nodes(owner.unmergedRootSemanticsNode).first {
                    it.config.getOrNull(SemanticsActions.OnClick) != null
                }
                assertEquals(112f, rowHeight / resources.displayMetrics.density, 0.5f)
                assertTrue(row.config[SemanticsActions.OnClick].action!!.invoke())
            }
        } }
        paparazzi.luiFrames(view, name = "compact-native-list-item", end = 400, fps = 30)
        assertTrue(pressed)
        val rendered = image!!
        val pixelsPerDp = rendered.width.toFloat() / width * paparazzi.resources.displayMetrics.density
        val inkHeights = (0 until 4).map { row ->
            val top = (row * 28 * pixelsPerDp).toInt()
            val bottom = ((row + 1) * 28 * pixelsPerDp).toInt().coerceAtMost(rendered.height)
            (top until bottom).count { y ->
                (0 until (200 * pixelsPerDp).toInt().coerceAtMost(rendered.width)).any { x ->
                    val pixel = rendered.getRGB(x, y)
                    (pixel ushr 24) > 200 && (pixel shr 16 and 255) < 100 &&
                        (pixel shr 8 and 255) < 100 && (pixel and 255) < 100
                }
            } / pixelsPerDp
        }
        assertTrue("every 28dp row must paint complete glyph ink, observed $inkHeights dp", inkHeights.all { it >= 8f })
    }
}
