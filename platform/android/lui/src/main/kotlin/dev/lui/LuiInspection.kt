package dev.lui

import android.graphics.RectF
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.semantics.testTagsAsResourceId

/** Optional, read-only native-host inspection. All access must be on the UI thread. */
class LuiInspection internal constructor(private val backend: LuiBackend) : AutoCloseable {
    data class Node(
        val id: Long,
        val incarnation: Long,
        val kind: String,
        val properties: Map<String, LuiWireValue>,
        val children: List<Long>,
    )

    private var nextIncarnation = 0L
    private val incarnations = mutableMapOf<Long, Long>()
    internal val frames = mutableMapOf<Long, RectF>()

    internal fun changed(created: List<Long>, dropped: Set<Long>) {
        dropped.forEach { incarnations.remove(it); frames.remove(it) }
        created.forEach { incarnations[it] = ++nextIncarnation; frames.remove(it) }
    }

    fun snapshot(): List<Node> {
        val tree = backend.tree
        return (tree.nodes.map { (id, node) ->
            Node(id, incarnation(id), node.kind.wireName, node.properties.toMap(), node.children.toList())
        } + tree.extensionNodes.map { (id, node) ->
            Node(id, incarnation(id), "extension:${node.identifier}", node.properties.toMap(), node.children.toList())
        }).sortedBy { it.id }
    }

    private fun incarnation(id: Long): Long = incarnations.getOrPut(id) { ++nextIncarnation }

    /** Clipped bounds in physical screen pixels; wire hosts convert to viewport units. */
    fun screenFrames(): Map<Long, RectF> {
        val nodes = snapshot().associateBy { it.id }
        val parents = nodes.values.flatMap { node -> node.children.map { it to node.id } }.toMap()
        val visible = mutableMapOf<Long, Boolean>()
        fun isVisible(id: Long): Boolean = visible.getOrPut(id) {
            val node = nodes[id]
            node != null && node.properties["display"]?.stringValue != "none" &&
                node.properties["visibility"]?.stringValue != "hidden" &&
                (node.properties["opacity"]?.numberValue ?: 1.0) > 0.0 &&
                !(node.kind == "virtual-list" && node.properties["selected"]?.boolValue == false) &&
                (parents[id]?.let { isVisible(it) } ?: true)
        }
        return frames.filterKeys { isVisible(it) }.mapValues { RectF(it.value) }
    }

    override fun close() {
        if (backend.inspection === this) backend.inspection = null
        frames.clear()
        incarnations.clear()
    }
}

@Composable
internal fun Modifier.luiInspection(backend: LuiBackend, id: Long): Modifier {
    val inspection = backend.inspection ?: return this
    val view = LocalView.current
    DisposableEffect(inspection, id) {
        onDispose { inspection.frames.remove(id) }
    }
    return semantics {
        testTag = "lui-drive-$id"
        testTagsAsResourceId = true
    }.onGloballyPositioned { coordinates ->
        val screen = IntArray(2)
        val window = IntArray(2)
        view.getLocationOnScreen(screen)
        view.getLocationInWindow(window)
        val bounds = coordinates.boundsInWindow()
        inspection.frames[id] = RectF(
            bounds.left + screen[0] - window[0], bounds.top + screen[1] - window[1],
            bounds.right + screen[0] - window[0], bounds.bottom + screen[1] - window[1],
        )
    }
}
