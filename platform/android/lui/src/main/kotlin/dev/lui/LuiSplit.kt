package dev.lui

import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.VerticalDivider
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp

/**
 * Bonsplit-style tabbed split panes for the Kotlin backend (port of
 * `lui_flutter_split.dart`). The OCaml app owns the tree; this file owns
 * gesture-time visuals (divider drag, tab selection) and reports semantic
 * events back through the extension-event channel.
 *
 * The fingerprint literals are the canonical `lui-extension-v1` strings —
 * test_lui.ml's `split_host_sources` drift check verifies them against
 * src/lui_split.ml, so keep them byte-identical.
 */
object LuiSplit {
    private const val VIEW_FINGERPRINT =
        "lui-extension-v1|10:split-view|profiles:android/kotlin,ios/swiftui,linux/gpui,macos/gpui,macos/swiftui,web/web,windows/gpui|standard-children:0|children:12:split-branch,10:split-pane|properties:17:divider-thickness:float:optional:none,24:accessibility-identifier:string:optional:none,9:animation:bool:optional:none|events:"
    private const val BRANCH_FINGERPRINT =
        "lui-extension-v1|12:split-branch|profiles:android/kotlin,ios/swiftui,linux/gpui,macos/gpui,macos/swiftui,web/web,windows/gpui|standard-children:0|children:12:split-branch,10:split-pane|properties:11:orientation:string:required:none,5:ratio:float:required:none|events:13:ratio-changed[5:ratio:float:required]"
    private const val PANE_FINGERPRINT =
        "lui-extension-v1|10:split-pane|profiles:android/kotlin,ios/swiftui,linux/gpui,macos/gpui,macos/swiftui,web/web,windows/gpui|standard-children:0|children:9:split-tab|properties:24:accessibility-identifier:string:optional:none,7:focused:bool:optional:none,7:pane-id:string:required:none,8:selected:string:optional:none|events:10:split-drop[3:tab:string:required,4:edge:string:required,9:from-pane:string:required],10:tab-closed[3:tab:string:required],11:pane-closed[],12:pane-focused[],12:tab-selected[3:tab:string:required],15:split-requested[11:orientation:string:required],8:navigate[9:direction:string:required],9:tab-moved[3:tab:string:required,5:index:int:required,9:from-pane:string:required]"
    private const val TAB_FINGERPRINT =
        "lui-extension-v1|9:split-tab|profiles:android/kotlin,ios/swiftui,linux/gpui,macos/gpui,macos/swiftui,web/web,windows/gpui|standard-children:1|children:|properties:24:accessibility-identifier:string:optional:none,4:icon:string:optional:none,5:dirty:bool:optional:none,5:title:string:required:none,6:tab-id:string:required:none,8:closable:bool:optional:none|events:"

    private val accessibilityIdentifier =
        LuiExtensionProperty("accessibility-identifier", LuiExtensionValueKind.STRING)

    /** Registers all four split components. */
    fun register(registry: LuiExtensionRegistry) {
        registry.register(
            identifier = "split-view",
            fingerprint = VIEW_FINGERPRINT,
            childIdentifiers = listOf("split-branch", "split-pane"),
            properties = listOf(
                LuiExtensionProperty("divider-thickness", LuiExtensionValueKind.DOUBLE),
                LuiExtensionProperty("animation", LuiExtensionValueKind.BOOLEAN),
                accessibilityIdentifier,
            ),
            builder = { LuiSplitView(this) },
        )
        registry.register(
            identifier = "split-branch",
            fingerprint = BRANCH_FINGERPRINT,
            childIdentifiers = listOf("split-branch", "split-pane"),
            properties = listOf(
                LuiExtensionProperty("orientation", LuiExtensionValueKind.STRING, required = true),
                LuiExtensionProperty("ratio", LuiExtensionValueKind.DOUBLE, required = true),
            ),
            events = listOf(
                LuiExtensionEventSchema(
                    "ratio-changed",
                    listOf(
                        LuiExtensionProperty("ratio", LuiExtensionValueKind.DOUBLE, required = true),
                    ),
                ),
            ),
            builder = { LuiSplitBranch(this) },
        )
        registry.register(
            identifier = "split-pane",
            fingerprint = PANE_FINGERPRINT,
            childIdentifiers = listOf("split-tab"),
            properties = listOf(
                LuiExtensionProperty("pane-id", LuiExtensionValueKind.STRING, required = true),
                LuiExtensionProperty("selected", LuiExtensionValueKind.STRING),
                LuiExtensionProperty("focused", LuiExtensionValueKind.BOOLEAN),
                accessibilityIdentifier,
            ),
            events = listOf(
                stringEvent("tab-selected", "tab"),
                stringEvent("tab-closed", "tab"),
                LuiExtensionEventSchema(
                    "tab-moved",
                    listOf(
                        LuiExtensionProperty("tab", LuiExtensionValueKind.STRING, required = true),
                        LuiExtensionProperty("index", LuiExtensionValueKind.INTEGER, required = true),
                        LuiExtensionProperty("from-pane", LuiExtensionValueKind.STRING, required = true),
                    ),
                ),
                LuiExtensionEventSchema("pane-focused"),
                stringEvent("navigate", "direction"),
                stringEvent("split-requested", "orientation"),
                LuiExtensionEventSchema(
                    "split-drop",
                    listOf(
                        LuiExtensionProperty("tab", LuiExtensionValueKind.STRING, required = true),
                        LuiExtensionProperty("from-pane", LuiExtensionValueKind.STRING, required = true),
                        LuiExtensionProperty("edge", LuiExtensionValueKind.STRING, required = true),
                    ),
                ),
                LuiExtensionEventSchema("pane-closed"),
            ),
            builder = { LuiSplitPane(this) },
        )
        registry.register(
            identifier = "split-tab",
            fingerprint = TAB_FINGERPRINT,
            acceptsStandardChildren = true,
            properties = listOf(
                LuiExtensionProperty("tab-id", LuiExtensionValueKind.STRING, required = true),
                LuiExtensionProperty("title", LuiExtensionValueKind.STRING, required = true),
                LuiExtensionProperty("icon", LuiExtensionValueKind.STRING),
                LuiExtensionProperty("dirty", LuiExtensionValueKind.BOOLEAN),
                LuiExtensionProperty("closable", LuiExtensionValueKind.BOOLEAN),
                accessibilityIdentifier,
            ),
            builder = {
                Column(Modifier.fillMaxSize()) {
                    children.forEach { child(it) }
                }
            },
        )
    }

    private fun stringEvent(name: String, field: String) =
        LuiExtensionEventSchema(
            name,
            listOf(LuiExtensionProperty(field, LuiExtensionValueKind.STRING, required = true)),
        )
}

/** Visual settings broadcast by split-view through the Compose tree. */
private data class LuiSplitSettings(
    val dividerThickness: Double = 9.0,
    val animationEnabled: Boolean = true,
)

private val LocalSplitSettings = compositionLocalOf { LuiSplitSettings() }

@Composable
private fun LuiSplitView(ext: LuiExtensionContext) {
    val settings = LuiSplitSettings(
        dividerThickness = (ext.double("divider-thickness") ?: 9.0).coerceAtLeast(1.0),
        animationEnabled = ext.bool("animation") ?: true,
    )
    CompositionLocalProvider(LocalSplitSettings provides settings) {
        Column(Modifier.fillMaxSize()) {
            ext.children.forEach { ext.child(it) }
        }
    }
}

@Composable
private fun LuiSplitBranch(ext: LuiExtensionContext) {
    val settings = LocalSplitSettings.current
    val horizontal = ext.string("orientation") != "vertical"
    val sourceRatio = (ext.double("ratio") ?: 0.5).coerceIn(0.0, 1.0)
    var ratio by remember { mutableDoubleStateOf(sourceRatio) }
    var dragging by remember { mutableStateOf(false) }
    if (!dragging && kotlin.math.abs(ratio - sourceRatio) > 1e-6) {
        ratio = sourceRatio
    }
    var axisPx by remember { mutableIntStateOf(0) }

    val thickness = settings.dividerThickness.dp
    val divider: @Composable () -> Unit = {
        val handle = Modifier
            .then(if (horizontal) Modifier.width(thickness).fillMaxHeight() else Modifier.height(thickness).fillMaxWidth())
            .pointerInput(horizontal) {
                detectDragGestures(
                    onDragStart = { dragging = true },
                    onDragEnd = { dragging = false },
                    onDragCancel = { dragging = false },
                    onDrag = { change, amount ->
                        change.consume()
                        if (axisPx > 0) {
                            val delta = (if (horizontal) amount.x else amount.y) / axisPx
                            ratio = (ratio + delta).toDouble().coerceIn(0.05, 0.95)
                            ext.emitEvent(
                                "ratio-changed",
                                mapOf("ratio" to LuiWireValue.DoubleValue(ratio)),
                            )
                        }
                    },
                )
            }
        if (horizontal) {
            VerticalDivider(handle)
        } else {
            HorizontalDivider(handle)
        }
    }

    if (horizontal) {
        Row(Modifier.fillMaxSize().onSizeChanged { axisPx = it.width }) {
            ext.children.getOrNull(0)?.let { first ->
                Box(Modifier.weight(ratio.toFloat().coerceAtLeast(0.001f)).fillMaxHeight()) {
                    ext.child(first)
                }
            }
            divider()
            ext.children.getOrNull(1)?.let { second ->
                Box(Modifier.weight((1f - ratio.toFloat()).coerceAtLeast(0.001f)).fillMaxHeight()) {
                    ext.child(second)
                }
            }
        }
    } else {
        Column(Modifier.fillMaxSize().onSizeChanged { axisPx = it.height }) {
            ext.children.getOrNull(0)?.let { first ->
                Box(Modifier.weight(ratio.toFloat().coerceAtLeast(0.001f)).fillMaxWidth()) {
                    ext.child(first)
                }
            }
            divider()
            ext.children.getOrNull(1)?.let { second ->
                Box(Modifier.weight((1f - ratio.toFloat()).coerceAtLeast(0.001f)).fillMaxWidth()) {
                    ext.child(second)
                }
            }
        }
    }
}

@Composable
private fun LuiSplitPane(ext: LuiExtensionContext) {
    val tabs = ext.children.mapNotNull { id ->
        ext.extensionChild(id)?.let { id to it }
    }
    val selected = ext.string("selected") ?: tabs.firstOrNull()?.let {
        it.second.properties["tab-id"]?.stringValue
    }
    val selectedPair = tabs.firstOrNull {
        it.second.properties["tab-id"]?.stringValue == selected
    } ?: tabs.firstOrNull()

    Column(Modifier.fillMaxSize()) {
        Surface(tonalElevation = 1.dp) {
            Row(
                Modifier
                    .fillMaxWidth()
                    .horizontalScroll(rememberScrollState()),
            ) {
                tabs.forEach { (id, tab) ->
                    val tabId = tab.properties["tab-id"]?.stringValue ?: return@forEach
                    val isSelected = id == selectedPair?.first
                    SplitTabChip(
                        node = tab,
                        icons = ext.backend.icons,
                        selected = isSelected,
                        onSelect = {
                            ext.emitEvent("pane-focused")
                            ext.emitEvent("tab-selected", mapOf("tab" to LuiWireValue.Str(tabId)))
                        },
                        onClose = {
                            ext.emitEvent("tab-closed", mapOf("tab" to LuiWireValue.Str(tabId)))
                        },
                    )
                }
            }
        }
        HorizontalDivider()
        Box(Modifier.weight(1f).fillMaxWidth()) {
            selectedPair?.let { (id, _) ->
                // Mount only the selected tab; the OCaml side re-issues
                // patches when it is evicted, matching the web backend.
                ext.child(id)
            }
        }
    }
}

@Composable
private fun SplitTabChip(
    node: LuiExtensionNode,
    icons: LuiIconResolver,
    selected: Boolean,
    onSelect: () -> Unit,
    onClose: () -> Unit,
) {
    val title = node.properties["title"]?.stringValue ?: ""
    val icon = node.properties["icon"]?.stringValue?.let { icons.icon(it) }
    val dirty = node.properties["dirty"]?.boolValue == true
    val closable = node.properties["closable"]?.boolValue == true

    Surface(
        color = if (selected) {
            MaterialTheme.colorScheme.surface
        } else {
            MaterialTheme.colorScheme.surfaceContainerLow
        },
        onClick = onSelect,
    ) {
        Row(
            Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (icon != null) {
                Icon(
                    icon,
                    contentDescription = null,
                    modifier = Modifier.size(16.dp).padding(end = 2.dp),
                    tint = if (selected) {
                        MaterialTheme.colorScheme.primary
                    } else {
                        MaterialTheme.colorScheme.onSurfaceVariant
                    },
                )
            }
            Text(
                if (dirty) "$title •" else title,
                style = MaterialTheme.typography.labelLarge,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                color = if (selected) {
                    MaterialTheme.colorScheme.onSurface
                } else {
                    MaterialTheme.colorScheme.onSurfaceVariant
                },
            )
            if (closable) {
                IconButton(onClick = onClose, modifier = Modifier.size(20.dp)) {
                    Icon(
                        icons.icon("x") ?: Icons.Filled.Close,
                        contentDescription = "Close",
                        modifier = Modifier.size(12.dp),
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }
}
