package dev.lui

import android.graphics.BitmapFactory
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap

/**
 * Public entry point of the Kotlin/LUI backend: owns the retained tree,
 * the extension registry, host-registered images, and the event sink
 * that forwards user events to the bridge.
 *
 * Typical use:
 * ```
 * val backend = LuiBackend { event -> LuiBridge.dispatch(event) }
 * backend.applyBatch(patchJson)
 * setContent { backend.Content() }
 * ```
 */
class LuiBackend(
    val eventSink: LuiEventSink = LuiEventSink {},
    val extensions: LuiExtensionRegistry = LuiExtensionRegistry(),
) {
    internal val tree = LuiRetainedTree(extensions)

    /** Bump on every applied batch so composables recompose. */
    internal var revision by mutableIntStateOf(0)
        private set

    /** Host-registered raster images, keyed by the `image` prop id. */
    internal val images = mutableStateMapOf<Int, ImageBitmap>()

    /** Host-presented media frames, keyed by the `surface` prop id. */
    internal val mediaSurfaces = mutableStateMapOf<Int, ImageBitmap>()

    /** Resolver hook for `file-image` paths (e.g. remap asset paths). */
    var filePathResolver: ((String) -> String)? = null

    internal var lastError: String? = null
        private set

    fun node(id: Int): LuiNode? = tree.nodes[id]
    fun extensionNode(id: Int): LuiExtensionNode? = tree.extensionNodes[id]

    /** Apply one JSON patch batch. Returns false (state untouched) when the
     * batch fails validation — mirrors the other backends' reject semantics. */
    fun applyBatch(source: String): Boolean {
        return try {
            tree.apply(LuiPatchBatch.parse(source))
            revision++
            lastError = null
            true
        } catch (error: LuiBackendException) {
            lastError = error.message
            false
        }
    }

    fun emit(event: LuiEvent) = eventSink.onEvent(event)

    internal fun emitExtensionEvent(
        node: Int,
        identifier: String,
        name: String,
        values: Map<String, LuiWireValue>,
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

    /** Renders the retained tree's roots inside the ambient LuiTheme. */
    @Composable
    fun Content() {
        // Read the revision so this composable recomposes on each batch.
        val applied = revision
        if (applied == 0) return
        for (rootId in tree.rootIds) {
            LuiNodeView(backend = this, id = rootId)
        }
    }
}
