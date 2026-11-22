package dev.lui

import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.SemanticsNode
import androidx.compose.ui.semantics.SemanticsOwner
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import app.cash.paparazzi.DeviceConfig
import app.cash.paparazzi.Paparazzi
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class LuiRowStretchTest {
    @get:Rule val paparazzi = Paparazzi(deviceConfig = DeviceConfig.PIXEL_5.copy(softButtons = false))

    @Test fun tableDividersAndGrowingCellsMatchRowHeight() {
        val backend = LuiBackend()
        check(backend.applyBatch("""{"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"root"},
          {"op":"create-node","id":2,"kind":"row"},
          {"op":"insert-child","parent":1,"child":2,"index":0},
          {"op":"set-prop","id":2,"property":"cross","value":"stretch"},
          {"op":"create-node","id":3,"kind":"text"},
          {"op":"insert-child","parent":2,"child":3,"index":0},
          {"op":"set-prop","id":3,"property":"grow","value":1},
          {"op":"set-prop","id":3,"property":"min-height","value":48},
          {"op":"set-prop","id":3,"property":"text","value":"Name"},
          {"op":"set-prop","id":3,"property":"background","value":"secondary"},
          {"op":"create-node","id":4,"kind":"divider"},
          {"op":"insert-child","parent":2,"child":4,"index":1},
          {"op":"set-prop","id":4,"property":"orientation","value":"vertical"},
          {"op":"create-node","id":5,"kind":"text"},
          {"op":"insert-child","parent":2,"child":5,"index":2},
          {"op":"set-prop","id":5,"property":"width","value":170},
          {"op":"set-prop","id":5,"property":"height","value":96},
          {"op":"set-prop","id":5,"property":"text","value":"A taller value cell"},
          {"op":"set-prop","id":5,"property":"background","value":"secondary"}
        ]}""")) { backend.lastError.orEmpty() }
        paparazzi.snapshot(name = "stretched-table-row") { LuiTheme { backend.Content() } }
    }

    @Test fun columnsInStretchedRowSupportIntrinsicHeight() {
        val backend = LuiBackend()
        check(backend.applyBatch("""{"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"row"},
          {"op":"set-prop","id":1,"property":"cross","value":"stretch"},
          {"op":"create-node","id":2,"kind":"column"},
          {"op":"insert-child","parent":1,"child":2,"index":0},
          {"op":"set-prop","id":2,"property":"grow","value":1},
          {"op":"create-node","id":3,"kind":"text"},
          {"op":"insert-child","parent":2,"child":3,"index":0},
          {"op":"set-prop","id":3,"property":"text","value":"Natural"},
          {"op":"create-node","id":4,"kind":"column"},
          {"op":"insert-child","parent":1,"child":4,"index":1},
          {"op":"set-prop","id":4,"property":"grow","value":1},
          {"op":"create-node","id":5,"kind":"text"},
          {"op":"insert-child","parent":4,"child":5,"index":0},
          {"op":"set-prop","id":5,"property":"grow","value":1},
          {"op":"set-prop","id":5,"property":"height","value":96},
          {"op":"set-prop","id":5,"property":"text","value":"Tall"},
          {"op":"create-node","id":6,"kind":"text"},
          {"op":"insert-child","parent":4,"child":6,"index":1},
          {"op":"set-prop","id":6,"property":"grow","value":1},
          {"op":"set-prop","id":6,"property":"height","value":24},
          {"op":"set-prop","id":6,"property":"text","value":"Short"}
        ]}""")) { backend.lastError.orEmpty() }
        var tallHeight = 0f
        var density = 0f
        val view = ComposeView(paparazzi.context).apply { setContent {
            val native = LocalView.current
            density = LocalDensity.current.density
            LuiTheme { Box { backend.Content(1) } }
            LaunchedEffect(Unit) {
                repeat(3) { withFrameNanos {} }
                val owner = native.javaClass.methods.first { it.name == "getSemanticsOwner" }.invoke(native) as SemanticsOwner
                fun nodes(root: SemanticsNode): List<SemanticsNode> = listOf(root) + root.children.flatMap(::nodes)
                tallHeight = nodes(owner.unmergedRootSemanticsNode).first {
                    it.config.getOrNull(SemanticsProperties.Text)?.any { value -> value.text == "Tall" } == true
                }.boundsInRoot.height
            }
        } }
        paparazzi.luiFrames(view, name = "stretched-row-columns", end = 100, fps = 30)
        assertTrue("tall growing child height $tallHeight", density > 0f && tallHeight >= 96 * density - 1)
    }
}
