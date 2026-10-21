package dev.lui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.key
import androidx.compose.runtime.snapshots.Snapshot
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap

/**
 * Public entry point of the Kotlin/LUI backend: owns the retained tree,
 * the extension registry, host-registered images, the icon resolver, and
 * the event handler that forwards user events to the bridge.
 *
 * Typical use:
 * ```
 * val backend = LuiBackend(onEvent = { it.dispatchToBridge() })
 * backend.applyJson(patchJson)
 * setContent { backend.Content(rootId) }
 * ```
 */
class LuiBackend(
    val onEvent: (LuiEvent) -> Unit = {},
    val extensions: LuiExtensionRegistry = LuiExtensionRegistry(),
    val icons: LuiIconResolver = LuiIconResolver.DEFAULT,
) {
    internal var tree = LuiRetainedTree(extensions)
        private set
    /** Structural half of a published node: kind, parent link and child
     * order. A batch that only mutates properties leaves this state
     * untouched, so parent scans of `kind`/`children` are not invalidated
     * by property writes on the child. */
    private data class LuiNodeStructure(
        val kind: LuiNodeKind,
        val parent: Long?,
        val children: List<Long>,
    )

    private data class LuiExtensionStructure(
        val identifier: String,
        val parent: Long?,
        val children: List<Long>,
    )

    /** Per-node snapshot states backing [node]/[extensionNode]. The store
     * copies a record before mutating it, so the published child lists and
     * property maps are effectively immutable once written, and structural
     * equality on the states skips invalidation for value-identical ops. */
    private class NodeObservation {
        val structure = mutableStateOf<LuiNodeStructure?>(null)
        val extension = mutableStateOf<LuiExtensionStructure?>(null)
        val props = mutableStateOf<Map<String, LuiWireValue>>(emptyMap())

        /** Live view handed out by [LuiBackend.node]: getters read the two
         * states lazily so a reader subscribes only to the side it touches. */
        val nodeView = object : LuiNodeLike {
            override val kind: LuiNodeKind get() = structure.value!!.kind
            override val parent: Long? get() = structure.value?.parent
            override val children: List<Long>
                get() = structure.value?.children ?: emptyList()
            override val properties: Map<String, LuiWireValue> get() = props.value
        }
    }

    private val observedNodes = mutableMapOf<Long, NodeObservation>()
    private var roots by mutableStateOf<List<Long>>(emptyList())

    /** Host-registered raster images, keyed by the `image` prop id. */
    internal val images = mutableStateMapOf<Int, ImageBitmap>()

    /** Host-presented media frames, keyed by the `surface` prop id. */
    internal val mediaSurfaces = mutableStateMapOf<Int, ImageBitmap>()

    /** Resolver hook for `file-image` paths (e.g. remap asset paths). */
    var filePathResolver: ((String) -> String)? = null

    var lastError: String? = null
        private set
    internal val scrollPositions = mutableMapOf<String, LuiScrollPosition>()

    private fun observed(id: Long): NodeObservation = observedNodes.getOrPut(id) {
        NodeObservation().also { refresh(it, id) }
    }

    private fun refresh(obs: NodeObservation, id: Long) {
        val node = tree.node(id)
        val extension = tree.extensionNode(id)
        obs.structure.value =
            node?.let { LuiNodeStructure(it.kind, it.parent, it.children) }
        obs.extension.value =
            extension?.let { LuiExtensionStructure(it.identifier, it.parent, it.children) }
        obs.props.value = node?.properties ?: extension?.properties ?: emptyMap()
    }

    fun node(id: Long): LuiNodeLike? {
        val obs = observed(id)
        return if (obs.structure.value != null) obs.nodeView else null
    }

    fun extensionNode(id: Long): LuiExtensionNode? {
        val obs = observed(id)
        // Read both states so callers stay subscribed to structural and
        // property mutations even though the retained record is returned.
        obs.extension.value ?: return null
        obs.props.value
        return tree.extensionNode(id)
    }

    private fun publish(changed: Set<Long>, dropped: Set<Long> = tree.lastDropped) =
        Snapshot.withMutableSnapshot {
            changed.forEach { id -> observedNodes[id]?.let { refresh(it, id) } }
            // Let entries for dropped/detached nodes go so the table shrinks.
            dropped.forEach { observedNodes.remove(it) }
            roots = tree.rootIds
        }

    /** Apply one JSON patch batch. Returns false (state untouched) when the
     * batch fails validation — mirrors the other backends' reject semantics. */
    fun applyJson(source: String?): Boolean {
        if (source.isNullOrEmpty()) return false
        val batch = try {
            LuiPatchBatch.parse(source)
        } catch (error: LuiBackendException) {
            lastError = error.message
            return false
        }
        return applyBatch(batch)
    }

    /** Alias of [applyJson] kept for internal callers. */
    fun applyBatch(source: String): Boolean = applyJson(source)

    /** Apply an already-decoded patch batch (the bridge parses off the main
     * thread and posts the batch for apply+publish here). */
    internal fun applyBatch(batch: LuiPatchBatch): Boolean = try {
        tree.apply(batch)
        publish(tree.lastChanged)
        lastError = null
        true
    } catch (error: LuiBackendException) {
        lastError = error.message
        false
    }

    /** Replace the host mirror with a fully validated authoritative runtime snapshot. */
    fun applySnapshot(source: String): Boolean = try {
        applySnapshot(LuiPatchBatch.parse(source))
    } catch (error: LuiBackendException) {
        lastError = error.message
        false
    }

    internal fun applySnapshot(batch: LuiPatchBatch): Boolean = try {
        val replacement = LuiRetainedTree(extensions)
        replacement.applyInitialSnapshot(batch)
        val observed = observedNodes.keys.toSet()
        tree = replacement
        publish(
            changed = observed,
            dropped = observed.filterNotTo(mutableSetOf()) { replacement.contains(it) },
        )
        lastError = null
        true
    } catch (error: LuiBackendException) {
        lastError = error.message
        false
    }

    fun emit(event: LuiEvent) = onEvent(event)

    internal fun emitExtensionEvent(
        node: Long,
        identifier: String,
        name: String,
        values: Map<String, Any?>,
    ) = emit(LuiEvent.Extension(node, identifier, name, values))

    fun registerImage(id: Int, image: ImageBitmap) {
        require(id > 0) { "registered image id must be positive" }
        images[id] = image
    }

    fun unregisterImage(id: Int) {
        images.remove(id)
    }

    fun presentMediaSurfaceFrame(id: Int, image: ImageBitmap) {
        require(id > 0) { "media surface id must be positive" }
        mediaSurfaces[id] = image
    }

    fun unregisterMediaSurface(id: Int) {
        mediaSurfaces.remove(id)
    }

    /**
     * Renders a node of the retained tree inside the ambient LuiTheme.
     * Pass the id the bridge reports via `rootNode()`; a negative id
     * renders every current root.
     */
    @Composable
    fun Content(rootId: Long = -1L) {
        if (rootId >= 0) {
            LuiNodeView(backend = this, id = rootId)
            return
        }
        for (id in roots) {
            key(id) { LuiNodeView(backend = this, id = id) }
        }
    }
}
