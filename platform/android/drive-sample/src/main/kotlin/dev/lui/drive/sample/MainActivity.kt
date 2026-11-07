package dev.lui.drive.sample

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.material3.MaterialTheme
import androidx.compose.ui.Modifier
import dev.lui.LuiBackend
import dev.lui.LuiEvent
import dev.lui.LuiNodeKind
import dev.lui.LuiPatchBatch
import dev.lui.LuiPatchOp
import dev.lui.LuiWireValue

class MainActivity : ComponentActivity() {
    private lateinit var backend: LuiBackend
    private var drive: AutoCloseable? = null
    private var generation = 0
    private var count = 0

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        backend = LuiBackend(onEvent = { event ->
            when (event) {
                is LuiEvent.Press -> if (event.node == 3L) {
                    count++
                    apply(listOf(LuiPatchOp.SetProp(4, "text", LuiWireValue.Str("Count: $count"))))
                }
                is LuiEvent.TextChanged -> apply(listOf(LuiPatchOp.SetProp(event.node, "text", LuiWireValue.Str(event.text))))
                else -> Unit
            }
        })
        val nodes = listOf(1L to LuiNodeKind.root, 2L to LuiNodeKind.column,
            3L to LuiNodeKind.button, 4L to LuiNodeKind.text, 5L to LuiNodeKind.textField,
            6L to LuiNodeKind.button)
        apply(buildList {
            nodes.forEach { (id, kind) -> add(LuiPatchOp.CreateNode(id, kind)) }
            add(LuiPatchOp.InsertChild(1, 2, 0))
            listOf(3L, 4L, 5L, 6L).forEachIndexed { index, id -> add(LuiPatchOp.InsertChild(2, id, index)) }
            add(LuiPatchOp.SetProp(2, "padding", LuiWireValue.IntValue(24)))
            add(LuiPatchOp.SetProp(2, "gap", LuiWireValue.IntValue(16)))
            add(LuiPatchOp.SetProp(3, "text", LuiWireValue.Str("Increment")))
            add(LuiPatchOp.SetProp(3, "accessibility-identifier", LuiWireValue.Str("increment")))
            add(LuiPatchOp.SetProp(4, "text", LuiWireValue.Str("Count: 0")))
            add(LuiPatchOp.SetProp(5, "text", LuiWireValue.Str("initial")))
            add(LuiPatchOp.SetProp(5, "accessibility-identifier", LuiWireValue.Str("editor")))
            add(LuiPatchOp.SetProp(6, "text", LuiWireValue.Str("Disabled")))
            add(LuiPatchOp.SetProp(6, "enabled", LuiWireValue.Bool(false)))
        })
        setContent {
            MaterialTheme {
                Box(Modifier.safeDrawingPadding()) { backend.Content() }
            }
        }
        drive = DriveHook.attach(this, backend)
    }

    private fun apply(ops: List<LuiPatchOp>) {
        check(backend.applyBatch(LuiPatchBatch(++generation, ops))) { backend.lastError ?: "patch failed" }
    }

    override fun onDestroy() {
        drive?.close()
        super.onDestroy()
    }
}
