package dev.lui

import android.view.View
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalContext
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInWindow
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.unit.DpOffset
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp

internal data class LuiContextMenuPopup(
    val ownerId: Long,
    val menuId: Long,
    val position: Offset,
    val locals: CompositionLocalContext,
)

@Stable
internal class LuiContextMenus(val view: View) {
    var popup by mutableStateOf<LuiContextMenuPopup?>(null)
}

internal val LocalLuiContextMenus = compositionLocalOf<LuiContextMenus?> { null }

/** One stable root layout anchors popups without wrapping every protocol node. */
@Composable
internal fun LuiContextMenuRoot(backend: LuiBackend, rootId: Long, content: @Composable () -> Unit) {
    val view = LocalView.current
    val menus = remember(backend, rootId, view) { LuiContextMenus(view) }
    var origin by remember { mutableStateOf(Offset.Zero) }
    Box(Modifier.onGloballyPositioned { origin = it.positionInWindow() }, propagateMinConstraints = true) {
        CompositionLocalProvider(LocalLuiContextMenus provides menus) { content() }
        LuiContextMenuOverlay(backend, rootId, menus, origin, Modifier.matchParentSize())
    }
}

private fun menuOwnerIsAttached(backend: LuiBackend, rootId: Long, ownerId: Long): Boolean {
    var child = ownerId
    val seen = mutableSetOf<Long>()
    while (seen.add(child)) {
        val node = backend.node(child)
        val extension = if (node == null) backend.extensionNode(child) else null
        if (node == null && extension == null) return false
        if (child == rootId) return true
        val parent = node?.parent ?: extension?.parent ?: return false
        val siblings = backend.node(parent)?.children ?: backend.extensionNode(parent)?.children
        if (siblings?.contains(child) != true) return false
        child = parent
    }
    return false
}

@Composable
private fun LuiContextMenuOverlay(
    backend: LuiBackend,
    rootId: Long,
    menus: LuiContextMenus,
    origin: Offset,
    modifier: Modifier,
) {
    val popup = menus.popup ?: return
    val menu = backend.node(popup.menuId)
    val attached = menuOwnerIsAttached(backend, rootId, popup.ownerId) &&
        backend.node(popup.ownerId)?.children?.contains(popup.menuId) == true && menu != null
    if (!attached) {
        LaunchedEffect(popup) { if (menus.popup == popup) menus.popup = null }
        return
    }
    // The zero-size anchor is a child of an overlay, so it neither changes
    // row spacing nor loses the owner's input/focus state when menus change.
    CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr) {
        Box(modifier) {
            Box(Modifier.size(0.dp)) {
                CompositionLocalProvider(popup.locals) {
                    val scheme = MaterialTheme.colorScheme
                    val dark = LocalLuiThemeDark.current
                    val menuScheme = if (dark != null && dark != (scheme.surface.luminance() < .5f)) {
                        if (dark) LuiThemeDefaults.darkScheme() else LuiThemeDefaults.lightScheme()
                    } else scheme
                    val offset = popup.position - origin
                    val x = if (LocalLayoutDirection.current == LayoutDirection.Rtl) -offset.x else offset.x
                    MaterialTheme(colorScheme = menuScheme) {
                        DropdownMenu(
                            expanded = true,
                            onDismissRequest = {
                                menus.popup = null
                                backend.emit(LuiEvent.Dismiss(popup.menuId))
                            },
                            offset = with(LocalDensity.current) { DpOffset(x.toDp(), offset.y.toDp()) },
                        ) {
                            menu?.children?.forEach { LuiMenuEntry(backend, it) }
                        }
                    }
                }
            }
        }
    }
}
