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

    fun node(id: Long): LuiNode? = tree.nodes[id]
    fun extensionNode(id: Long): LuiExtensionNode? = tree.extensionNodes[id]

    /** Apply one JSON patch batch. Returns false (state untouched) when the
     * batch fails validation — mirrors the other backends' reject semantics. */
    fun applyJson(source: String?): Boolean {
        if (source.isNullOrEmpty()) return false
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

    /** Alias of [applyJson] kept for internal callers. */
    fun applyBatch(source: String): Boolean = applyJson(source)

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
        // Read the revision so this composable recomposes on each batch.
        val applied = revision
        if (applied == 0) return
        if (rootId >= 0) {
            LuiNodeView(backend = this, id = rootId)
            return
        }
        for (id in tree.rootIds) {
            LuiNodeView(backend = this, id = id)
        }
    }
}
