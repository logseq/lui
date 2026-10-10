package dev.lui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.RectangleShape
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlin.math.roundToInt

internal fun LuiNode.prop(name: String): LuiWireValue? = properties[name]

internal fun LuiNode.propString(name: String): String? = properties[name]?.stringValue

internal fun LuiNode.propBool(name: String, default: Boolean = false): Boolean =
    properties[name]?.boolValue ?: default

internal fun LuiNode.propInt(name: String, default: Int = 0): Int =
    properties[name]?.intValue ?: default

internal fun LuiNode.propDouble(name: String, default: Double = 0.0): Double =
    properties[name]?.doubleValue ?: default

internal fun LuiNode.text(): String = propString("text") ?: ""

internal fun LuiNode.isEnabled(): Boolean = propBool("enabled", true)

internal fun overlayAlignment(name: String?): Alignment = when (name) {
    "top-leading" -> Alignment.TopStart
    "top" -> Alignment.TopCenter
    "top-trailing" -> Alignment.TopEnd
    "leading" -> Alignment.CenterStart
    "trailing" -> Alignment.CenterEnd
    "bottom-leading" -> Alignment.BottomStart
    "bottom" -> Alignment.BottomCenter
    "bottom-trailing" -> Alignment.BottomEnd
    else -> Alignment.Center
}

internal fun textAlignment(name: String?): TextAlign = when (name) {
    "center" -> TextAlign.Center
    "end" -> TextAlign.End
    else -> TextAlign.Start
}

/** Default inner padding by kind, mirroring the Flutter backend. */
private fun defaultPadding(kind: LuiNodeKind): Int = when (kind) {
    LuiNodeKind.card -> 24
    LuiNodeKind.alert -> 16
    LuiNodeKind.bubble -> 12
    LuiNodeKind.tabs -> 4
    else -> 0
}

/**
 * Shared visual chrome for a node: sizing, padding, background, border,
 * corner radius, opacity. Ordering mirrors Flutter's Container: the
 * decoration paints under the padding.
 */
@Composable
internal fun Modifier.luiChrome(node: LuiNode): Modifier {
    // On `drawer` the `width` prop is the side panel's width (LuiDrawer reads
    // it for the Surface), not the element's own size — the drawer container
    // always fills its parent. Mirrors the SwiftUI backend where width only
    // reaches the panel.
    val width = if (node.kind == LuiNodeKind.drawer) null else node.prop("width")?.intValue
    val height = node.prop("height")?.intValue
    val minWidth = node.prop("min-width")?.intValue ?: 0
    val maxWidth = node.prop("max-width")?.intValue ?: Int.MAX_VALUE
    val minHeight = node.prop("min-height")?.intValue ?: 0
    val maxHeight = node.prop("max-height")?.intValue ?: Int.MAX_VALUE
    var modifier: Modifier = this
    // Margin = space outside the visual box: applied first so background,
    // border and clip stay inside it. Compose PaddingValues can't go
    // negative — negative margins are clamped to 0 (nearest supported form;
    // collapsing space is unexpressible on this backend). start/end stand in
    // for left/right — identical in LTR and mirrored in RTL.
    val marginBase = node.prop("margin")?.intValue ?: 0
    val marginH = node.prop("margin-horizontal")?.intValue ?: marginBase
    val marginV = node.prop("margin-vertical")?.intValue ?: marginBase
    val marginTop = maxOf(0, node.prop("margin-top")?.intValue ?: marginV)
    val marginBottom = maxOf(0, node.prop("margin-bottom")?.intValue ?: marginV)
    val marginStart = maxOf(0, node.prop("margin-left")?.intValue ?: marginH)
    val marginEnd = maxOf(0, node.prop("margin-right")?.intValue ?: marginH)
    if (marginTop > 0 || marginBottom > 0 || marginStart > 0 || marginEnd > 0) {
        modifier = modifier.padding(
            start = marginStart.dp,
            top = marginTop.dp,
            end = marginEnd.dp,
            bottom = marginBottom.dp,
        )
    }
    if (width != null) modifier = modifier.width(width.dp)
    if (height != null) modifier = modifier.height(height.dp)
    if (minWidth > 0 || maxWidth != Int.MAX_VALUE || minHeight > 0 || maxHeight != Int.MAX_VALUE) {
        modifier = modifier.sizeIn(
            minWidth = minWidth.dp,
            minHeight = minHeight.dp,
            maxWidth = if (maxWidth == Int.MAX_VALUE) Dp.Infinity else maxWidth.dp,
            maxHeight = if (maxHeight == Int.MAX_VALUE) Dp.Infinity else maxHeight.dp,
        )
    }
    val isSurface = LuiKindRules.isOverlaySurface(node.kind)
    val padding = node.prop("padding")?.intValue ?: defaultPadding(node.kind)
    val paddingH = node.prop("padding-horizontal")?.intValue ?: padding
    val paddingV = node.prop("padding-vertical")?.intValue ?: padding
    val radius = node.prop("corner-radius")?.intValue
        ?: if (isSurface) 12 else if (node.kind == LuiNodeKind.tabs) 8 else 0
    val borderWidth = node.prop("border-width")?.intValue ?: if (isSurface) 1 else 0
    val background = luiThemeColor(node.propString("background"))
    val borderColor = luiThemeColor(node.propString("border-color"))
    val shape: Shape = if (radius > 0) {
        androidx.compose.foundation.shape.RoundedCornerShape(radius.dp)
    } else {
        RectangleShape
    }
    val effectiveBackground = background ?: when {
        node.kind == LuiNodeKind.box && node.propBool("selected") ->
            MaterialTheme.colorScheme.secondaryContainer
        node.kind == LuiNodeKind.tabs -> MaterialTheme.colorScheme.secondaryContainer
        node.kind == LuiNodeKind.bubble && node.propString("variant") == "primary" ->
            MaterialTheme.colorScheme.primary
        isSurface -> MaterialTheme.colorScheme.surface
        else -> null
    }
    if (effectiveBackground != null) {
        modifier = modifier.background(effectiveBackground, shape)
    }
    if (borderWidth > 0) {
        modifier = modifier.border(
            BorderStroke(borderWidth.dp, borderColor ?: MaterialTheme.colorScheme.outlineVariant),
            shape,
        )
    }
    if (radius > 0) modifier = modifier.clip(shape)
    if (paddingH > 0 || paddingV > 0) {
        modifier = modifier.padding(horizontal = paddingH.dp, vertical = paddingV.dp)
    }
    node.prop("opacity")?.numberValue?.let { opacity ->
        if (opacity < 1) modifier = modifier.alpha(opacity.toFloat())
    }
    node.propString("accessibility-identifier")?.let { identifier ->
        modifier = modifier.semantics { testTag = identifier }.semantics {
            contentDescription = identifier
        }
    }
    node.propString("accessibility-label")?.let { label ->
        modifier = modifier.semantics { contentDescription = label }
    }
    return modifier
}

/**
 * Interaction chrome: press/long-press/double-press on kinds that render
 * gestures (column, text, tableCell, fileImage, tree rows, etc.), pointer
 * detail when `pointer-enabled`, and an attached context-menu child shown
 * on long-press.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
internal fun Modifier.luiGestures(
    backend: LuiBackend,
    node: LuiNode,
    id: Long,
    onContextMenu: (Offset) -> Unit = {},
): Modifier {
    var modifier: Modifier = this
    val enabled = node.isEnabled()

    val contextMenuId = node.children.firstOrNull { backend.node(it)?.kind == LuiNodeKind.contextMenu }
    if (contextMenuId != null && enabled) {
        modifier = modifier.pointerInput(id, contextMenuId) {
            detectTapGestures(
                onLongPress = { offset ->
                    onContextMenu(offset)
                    backend.emit(
                        LuiEvent.ContextMenuPress(
                            id,
                            LuiPointerDetail(x = offset.x.toDouble(), y = offset.y.toDouble()),
                        ),
                    )
                },
            )
        }
    }

    val pressable = enabled &&
        (node.propBool("press-enabled") ||
            (node.propBool("change-enabled") && LuiKindRules.isTreeRowKind(node.kind)) ||
            (node.propBool("toggle-enabled") && LuiKindRules.isTreeRowKind(node.kind)))
    val longPressable = enabled && node.propBool("long-press-enabled")
    val doublePressable = enabled && node.propBool("double-press-enabled")
    if (pressable || longPressable || doublePressable) {
        modifier = modifier.combinedClickable(
            onClick = {
                if (node.propBool("press-enabled")) {
                    backend.emit(LuiEvent.Press(id))
                } else if (node.propBool("change-enabled")) {
                    backend.emit(LuiEvent.Change(id))
                }
                if (node.propBool("toggle-enabled") && LuiKindRules.isTreeRowKind(node.kind)) {
                    backend.emit(LuiEvent.ToggleChanged(id, !node.propBool("expanded")))
                }
            },
            onLongClick = if (longPressable) {
                { backend.emit(LuiEvent.LongPress(id)) }
            } else {
                null
            },
            onDoubleClick = if (doublePressable) {
                { backend.emit(LuiEvent.DoublePress(id)) }
            } else {
                null
            },
        )
    }
    if (enabled && node.propBool("pointer-enabled")) {
        modifier = modifier.pointerInput(id) {
            detectTapGestures(
                onPress = { offset ->
                    val detail = LuiPointerDetail(
                        x = offset.x.toDouble(),
                        y = offset.y.toDouble(),
                    )
                    backend.emit(LuiEvent.PointerDown(id, detail))
                    tryAwaitRelease()
                    backend.emit(LuiEvent.PointerUp(id, detail))
                },
            )
        }
    }
    return modifier
}

/** Emits `Appear` once when an `appear-enabled` node first composes. */
@Composable
internal fun LuiAppear(backend: LuiBackend, node: LuiNode, id: Long) {
    if (node.propBool("appear-enabled")) {
        LaunchedEffect(id) { backend.emit(LuiEvent.Appear(id)) }
    }
}

/**
 * Applies a node's `theme`/`theme-mode` props: merges decoded tokens over
 * the inherited semantic colors and optionally overrides the subtree
 * appearance — a port of `LUIThemeScopeModifier`.
 */
@Composable
internal fun LuiThemeScope(node: LuiNode, content: @Composable () -> Unit) {
    val inherited = LocalLuiSemanticColors.current
    val ambientDark = LocalLuiThemeDark.current
    val schemeOverride = LuiThemeTokenDecoder.colorScheme(node.propString("theme-mode"))
    val dark = schemeOverride ?: (ambientDark ?: isSystemInDarkTheme())
    val own = LuiThemeTokenDecoder.colors(node.propString("theme"), dark)
    if (own.isEmpty() && schemeOverride == null) {
        content()
    } else {
        CompositionLocalProvider(
            LocalLuiSemanticColors provides inherited + own,
            LocalLuiThemeDark provides dark,
        ) {
            content()
        }
    }
}
