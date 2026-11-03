package dev.lui

import app.cash.paparazzi.DeviceConfig
import app.cash.paparazzi.Paparazzi
import androidx.compose.material3.Text
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.snapshotFlow
import kotlinx.coroutines.flow.first
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInRoot
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class LuiIdentityTest {
    @get:Rule
    val paparazzi = Paparazzi(deviceConfig = DeviceConfig.PIXEL_5.copy(softButtons = false))

    private fun reorder(kind: String) {
        val registry = LuiExtensionRegistry()
        var allocated = 0
        val drafts = mutableStateMapOf<Long, Int>()
        val positions = mutableStateMapOf<Long, Float>()
        var settled = false
        registry.register("review-row", "review-fingerprint", builder = { context ->
            val draft = remember { ++allocated }
            SideEffect { drafts[context.nodeId] = draft }
            Text("row ${context.nodeId}: $draft", modifier = Modifier.onGloballyPositioned {
                positions[context.nodeId] = it.positionInRoot().y
            })
        })
        val backend = LuiBackend(extensions = registry)
        assertTrue(backend.applyBatch("""{"generation":1,"ops":[
            {"op":"create-node","id":1,"kind":"$kind"},
            {"op":"set-prop","id":1,"property":"height","value":300},
            {"op":"create-extension","id":2,"identifier":"review-row","fingerprint":"review-fingerprint"},
            {"op":"create-extension","id":3,"identifier":"review-row","fingerprint":"review-fingerprint"},
            {"op":"insert-child","parent":1,"child":2,"index":0},
            {"op":"insert-child","parent":1,"child":3,"index":1}
        ]}"""))
        val before = mutableMapOf<Long, Int>()
        val view = ComposeView(paparazzi.context).apply { setContent {
            LuiTheme { backend.Content() }
            LaunchedEffect(Unit) {
                snapshotFlow { positions.toMap() }.first { it.size == 2 && it.getValue(2) < it.getValue(3) }
                before.putAll(drafts)
                assertTrue(backend.applyBatch("""{"generation":2,"ops":[
                    {"op":"move-child","parent":1,"child":3,"index":0}
                ]}"""))
                snapshotFlow { positions.toMap() }.first { it.getValue(3) < it.getValue(2) }
                settled = true
            }
        } }
        paparazzi.luiFrames(view, name = "review-$kind-reorder", end = 200, fps = 30)
        assertEquals("both rows rendered", 2, before.size)
        assertEquals("row drafts survive retained moves", before, drafts)
        assertEquals("reorder does not create replacement row state", 2, allocated)
        assertTrue("rendered order follows the committed child order: $positions", settled)
    }

    @Test
    fun `ordinary column preserves row state across moves`() = reorder("column")

    @Test
    fun `lazy column preserves row state across moves`() = reorder("virtual-list")
}
