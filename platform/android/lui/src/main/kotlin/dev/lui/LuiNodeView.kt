package dev.lui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Slider
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TooltipBox
import androidx.compose.material3.TooltipDefaults
import androidx.compose.material3.VerticalDivider
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.material3.rememberTooltipState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.DpOffset
import androidx.compose.ui.unit.dp

/**
 * Renders one node of the retained tree plus its subtree. Ported from the
 * Flutter backend's `_buildNode` so event dispatch and visual defaults
 * match the mobile reference behavior.
 */
@Composable
fun LuiNodeView(backend: LuiBackend, id: Long) {
    val node = backend.node(id)
    if (node == null) {
        LuiExtensionView(backend, id)
        return
    }
    LuiThemeScope(node) {
        LuiAppear(backend, node, id)
        when {
            node.kind == LuiNodeKind.root ->
                node.children.firstOrNull()?.let { LuiNodeView(backend, it) }
            LuiKindRules.isModalSurface(node.kind) -> LuiModalSurface(backend, node, id)
            else -> LuiChromeSurface(backend, node, id)
        }
    }
}

/**
 * Applies the shared chrome (sizing/background/border/padding/gestures)
 * around the kind-specific content, and renders an attached context-menu
 * child as a popup anchored to the long-press point.
 */
@Composable
private fun LuiChromeSurface(backend: LuiBackend, node: LuiNode, id: Long) {
    var contextMenuAt by remember(id) { mutableStateOf<Offset?>(null) }
    val contextMenuId =
        node.children.firstOrNull { backend.node(it)?.kind == LuiNodeKind.contextMenu }
    val modifier = Modifier
        .luiChrome(node)
        .luiGestures(backend, node, id) { offset -> contextMenuAt = offset }

    Box {
        LuiNodeContent(backend, node, id, modifier)
        val menuId = contextMenuId
        val anchor = contextMenuAt
        if (anchor != null && menuId != null) {
            val menu = backend.node(menuId)
            if (menu != null) {
                DropdownMenu(
                    expanded = true,
                    onDismissRequest = {
                        contextMenuAt = null
                        backend.emit(LuiEvent.Dismiss(menuId))
                    },
                    offset = with(LocalDensity.current) { DpOffset(anchor.x.toDp(), 0.dp) },
                ) {
                    menu.children.forEach { childId -> LuiMenuEntry(backend, childId) }
                }
            }
        }
    }
}

/**
 * Renders an extension node through its registered Composable builder;
 * tweaks use the same path (their registration wraps the single child).
 */
@Composable
private fun LuiExtensionView(backend: LuiBackend, id: Long) {
    val node = backend.extensionNode(id) ?: return
    val builder = backend.extensions.registration(node.identifier)?.builder ?: return
    val context = LuiExtensionContext(
        backend = backend,
        nodeId = id,
        identifier = node.identifier,
        properties = node.properties,
        children = node.children,
        renderChild = { childId -> LuiNodeView(backend, childId) },
    )
    context.builder()
}

private fun gapOf(node: LuiNode): Int =
    node.prop("gap")?.intValue ?: if (LuiKindRules.isHorizontalGroupKind(node.kind)) {
        LuiKindRules.horizontalGroupDefaultGap(node.kind)
    } else {
        0
    }

private fun emitValueChange(backend: LuiBackend, node: LuiNode, id: Long, value: Double) {
    if (!node.isEnabled()) return
    val emitted = when (node.kind) {
        LuiNodeKind.numberStepper -> {
            val min = node.propDouble("min")
            val max = node.propDouble("max", Double.MAX_VALUE)
            value.coerceIn(min, if (max < min) min else max)
        }
        else -> value.coerceIn(0.0, 1.0)
    }
    backend.emit(LuiEvent.ValueChanged(id, emitted))
}

/** Applies `grow` to a child inside a Row. */
@Composable
private fun RowScope.GrowChildRow(backend: LuiBackend, childId: Long) {
    val grow = backend.node(childId)?.prop("grow")?.numberValue ?: 0.0
    if (grow > 0) {
        Box(Modifier.weight(grow.toFloat().coerceAtLeast(0.001f))) {
            LuiNodeView(backend, childId)
        }
    } else {
        LuiNodeView(backend, childId)
    }
}

/** Applies `grow` to a child inside a Column. */
@Composable
private fun ColumnScope.GrowChildColumn(backend: LuiBackend, childId: Long) {
    val grow = backend.node(childId)?.prop("grow")?.numberValue ?: 0.0
    if (grow > 0) {
        Box(Modifier.weight(grow.toFloat().coerceAtLeast(0.001f))) {
            LuiNodeView(backend, childId)
        }
    } else {
        LuiNodeView(backend, childId)
    }
}

/**
 * The kind-specific rendering of a node. `modifier` carries the shared
 * chrome computed by [LuiChromeSurface].
 */
@Composable
private fun LuiNodeContent(
    backend: LuiBackend,
    node: LuiNode,
    id: Long,
    modifier: Modifier,
) {
    val children = node.children.filter { childId ->
        val kind = backend.node(childId)?.kind
        kind != LuiNodeKind.contextMenu && kind != LuiNodeKind.swipeActions
    }
    val enabled = node.isEnabled()

    when (node.kind) {
        LuiNodeKind.root -> children.firstOrNull()?.let { LuiNodeView(backend, it) }

        LuiNodeKind.row -> Row(
            modifier = modifier,
            horizontalArrangement = Arrangement.spacedBy(
                gapOf(node).dp,
                alignment = mainHorizontalAlignment(node.propString("main")),
            ),
            verticalAlignment = when (node.propString("cross")) {
                "start" -> Alignment.Top
                "end" -> Alignment.Bottom
                else -> Alignment.CenterVertically
            },
        ) {
            children.forEach { childId -> GrowChildRow(backend, childId) }
        }

        LuiNodeKind.column,
        LuiNodeKind.list,
        LuiNodeKind.listSection,
        LuiNodeKind.listSectionHeader,
        LuiNodeKind.listSectionFooter,
        LuiNodeKind.swipeActions,
        LuiNodeKind.link,
        LuiNodeKind.popover,
        LuiNodeKind.tree,
        LuiNodeKind.table,
        LuiNodeKind.timeline,
        -> Column(
            modifier = modifier,
            verticalArrangement = Arrangement.spacedBy(gapOf(node).dp),
        ) {
            children.forEach { childId -> GrowChildColumn(backend, childId) }
        }

        LuiNodeKind.virtualList -> LazyColumn(
            modifier = modifier,
            verticalArrangement = Arrangement.spacedBy(gapOf(node).dp),
        ) {
            items(children.size) { index -> LuiNodeView(backend, children[index]) }
        }

        LuiNodeKind.grid -> LuiGrid(backend, node, modifier, children)

        LuiNodeKind.stack,
        LuiNodeKind.bottomTab,
        LuiNodeKind.panel,
        LuiNodeKind.card,
        LuiNodeKind.resizable,
        LuiNodeKind.filePicker,
        -> LuiStackLike(backend, node, modifier, children)

        LuiNodeKind.edgeInset -> LuiEdgeInset(backend, node, modifier, children)

        LuiNodeKind.overlay -> LuiOverlay(backend, node, modifier, children)

        LuiNodeKind.viewThatFits -> Box(modifier) {
            children.firstOrNull()?.let { LuiNodeView(backend, it) }
        }

        LuiNodeKind.alert -> Column(modifier, verticalArrangement = Arrangement.spacedBy(8.dp)) {
            if (node.text().isNotEmpty()) {
                Text(node.text(), style = MaterialTheme.typography.titleSmall)
            }
            Box { children.forEach { LuiNodeView(backend, it) } }
        }

        LuiNodeKind.bubble -> LuiBubble(backend, node, modifier, children)

        LuiNodeKind.box -> Column(modifier.fillMaxWidth()) {
            children.forEach { childId -> GrowChildColumn(backend, childId) }
        }

        LuiNodeKind.text,
        LuiNodeKind.paragraph,
        LuiNodeKind.label,
        -> Text(
            node.text(),
            modifier = modifier,
            color = luiThemeColor(node.propString("foreground"), foreground = true)
                ?: Color.Unspecified,
            textAlign = textAlignment(node.propString("text-alignment")),
            style = LuiTypography.textStyleForSize(node.propString("size")),
        )

        LuiNodeKind.heading -> Text(
            node.text(),
            modifier = modifier,
            color = luiThemeColor(node.propString("foreground"), foreground = true)
                ?: Color.Unspecified,
            style = LuiTypography.headingStyle(node.propInt("heading-level", 1)),
        )

        LuiNodeKind.button -> LuiButton(backend, node, id, modifier, children)

        LuiNodeKind.toggleButton -> LuiToggleButton(backend, node, id, modifier)

        LuiNodeKind.toggle -> FilterChip(
            selected = node.propBool("checked"),
            onClick = {
                backend.emit(LuiEvent.ToggleChanged(id, !node.propBool("checked")))
            },
            label = { Text(node.text()) },
            modifier = modifier,
            enabled = enabled,
        )

        LuiNodeKind.radioGroup -> Row(modifier) {
            children.forEach { LuiNodeView(backend, it) }
        }

        LuiNodeKind.radio -> Row(
            modifier,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            RadioButton(
                selected = node.propBool("checked"),
                onClick = if (enabled) {
                    {
                        if (node.propBool("change-enabled")) {
                            backend.emit(LuiEvent.Change(id))
                        } else if (node.propBool("toggle-enabled")) {
                            backend.emit(LuiEvent.ToggleChanged(id, true))
                        } else {
                            backend.emit(LuiEvent.Press(id))
                        }
                    }
                } else {
                    null
                },
                enabled = enabled,
            )
            Text(node.text())
        }

        LuiNodeKind.slider -> Slider(
            value = node.propDouble("value").toFloat().coerceIn(0f, 1f),
            onValueChange = { value ->
                if (enabled) backend.emit(LuiEvent.ValueChanged(id, value.toDouble()))
            },
            modifier = modifier,
            enabled = enabled,
        )

        LuiNodeKind.numberStepper -> Row(
            modifier,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(node.text())
            val step = node.propDouble("step", 1.0)
            val current = node.propDouble("value")
            IconButton(
                onClick = { emitValueChange(backend, node, id, current - step) },
                enabled = enabled,
            ) { Icon(Icons.Filled.Remove, contentDescription = "Decrease") }
            IconButton(
                onClick = { emitValueChange(backend, node, id, current + step) },
                enabled = enabled,
            ) { Icon(Icons.Filled.Add, contentDescription = "Increase") }
        }

        LuiNodeKind.textField,
        LuiNodeKind.secureField,
        LuiNodeKind.input,
        LuiNodeKind.searchField,
        LuiNodeKind.textarea,
        LuiNodeKind.combobox,
        -> LuiTextControl(backend, node, id, modifier)

        LuiNodeKind.checkbox -> Row(
            modifier,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Checkbox(
                checked = node.propBool("checked"),
                onCheckedChange = { value ->
                    if (enabled) backend.emit(LuiEvent.ToggleChanged(id, value))
                },
                enabled = enabled,
            )
            Text(node.text())
        }

        LuiNodeKind.switchControl -> Row(
            modifier,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (node.text().isNotEmpty()) Text(node.text())
            Switch(
                checked = node.propBool("checked"),
                onCheckedChange = { value ->
                    if (enabled) backend.emit(LuiEvent.ToggleChanged(id, value))
                },
                enabled = enabled,
            )
        }

        LuiNodeKind.progress -> LinearProgressIndicator(
            progress = { node.propDouble("value").toFloat().coerceIn(0f, 1f) },
            modifier = modifier,
        )

        LuiNodeKind.divider -> if (node.propString("orientation") == "vertical") {
            VerticalDivider(modifier.width(1.dp).fillMaxHeight())
        } else {
            HorizontalDivider(modifier)
        }

        LuiNodeKind.scroll -> {
            val horizontal = node.propString("orientation") == "horizontal"
            Box(
                modifier = modifier.then(
                    if (horizontal) {
                        Modifier.horizontalScroll(rememberScrollState())
                    } else {
                        Modifier.verticalScroll(rememberScrollState())
                    },
                ),
            ) {
                children.forEach { LuiNodeView(backend, it) }
            }
        }

        LuiNodeKind.tabs,
        LuiNodeKind.buttonGroup,
        LuiNodeKind.toggleGroup,
        LuiNodeKind.breadcrumb,
        LuiNodeKind.pagination,
        -> Row(
            modifier = modifier,
            horizontalArrangement = Arrangement.spacedBy(
                gapOf(node).dp,
                alignment = mainHorizontalAlignment(node.propString("main")),
            ),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            children.forEach { childId -> GrowChildRow(backend, childId) }
        }

        LuiNodeKind.bottomTabs -> LuiBottomTabs(backend, node, modifier)

        LuiNodeKind.spacer -> Spacer(modifier.size(1.dp))

        LuiNodeKind.spinner -> CircularProgressIndicator(
            modifier = modifier.size(
                when (node.propString("size")) {
                    "sm" -> 16.dp
                    "lg" -> 24.dp
                    else -> 20.dp
                },
            ),
            strokeWidth = 2.dp,
            color = luiThemeColor(node.propString("foreground"), foreground = true)
                ?: MaterialTheme.colorScheme.primary,
        )

        LuiNodeKind.icon -> backend.icons.icon(node.propString("name") ?: "")?.let { vector ->
            Icon(
                vector,
                contentDescription = node.propString("accessibility-label"),
                modifier = modifier.size(
                    when (node.propString("size")) {
                        "sm" -> 16.dp
                        "lg", "icon" -> 24.dp
                        else -> 18.dp
                    },
                ),
                tint = luiThemeColor(node.propString("foreground"), foreground = true)
                    ?: MaterialTheme.colorScheme.onSurface,
            )
        }

        LuiNodeKind.select -> LuiSelect(backend, node, id, modifier)

        LuiNodeKind.dropdownMenu,
        LuiNodeKind.contextMenu,
        -> {
            // Menus render through their anchor (stack child, menuTrigger,
            // or context-menu popup); a detached menu renders inline as a
            // surfaced column so its items stay reachable.
            Surface(
                modifier,
                shape = RoundedCornerShape(8.dp),
                tonalElevation = 2.dp,
                shadowElevation = 8.dp,
            ) {
                Column {
                    children.forEach { childId -> LuiMenuEntry(backend, childId) }
                }
            }
        }

        LuiNodeKind.menuItem -> LuiMenuItem(backend, node, id, modifier)

        LuiNodeKind.menuTrigger -> LuiMenuTrigger(backend, node, id, modifier)

        LuiNodeKind.listItem -> LuiListItem(backend, node, id, modifier, children)

        LuiNodeKind.avatar -> LuiAvatar(backend, node, modifier)

        LuiNodeKind.image -> LuiImage(backend, node, modifier)

        LuiNodeKind.fileImage -> LuiFileImage(backend, node, modifier)

        LuiNodeKind.mediaSurface -> LuiMediaSurface(backend, node, modifier)

        LuiNodeKind.stepper -> Row(modifier.wrapContentSize()) {
            children.forEach { LuiNodeView(backend, it) }
        }

        LuiNodeKind.step -> LuiStep(backend, node, id, modifier)

        LuiNodeKind.timelineItem -> LuiTimelineItem(backend, node, id, modifier)

        LuiNodeKind.inputGroup -> LuiInputGroup(backend, node, modifier, children)

        LuiNodeKind.inputGroupActions -> Row(
            modifier.padding(start = 8.dp, top = 4.dp, end = 8.dp, bottom = 8.dp),
            horizontalArrangement = Arrangement.spacedBy(gapOf(node).dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            children.forEach { childId -> GrowChildRow(backend, childId) }
        }

        LuiNodeKind.accordion -> LuiAccordion(backend, node, id, modifier, children)

        LuiNodeKind.tableRow -> LuiTableRow(backend, node, id, modifier, children)

        LuiNodeKind.tableCell -> LuiTableCell(backend, node, id, modifier)

        LuiNodeKind.drawer -> LuiDrawer(backend, node, id, modifier, children)

        LuiNodeKind.split -> LuiSplit(backend, node, id, modifier, children)

        LuiNodeKind.tooltip -> Text(node.text(), modifier)

        LuiNodeKind.toast -> LuiToast(backend, node, id, modifier, children)

        LuiNodeKind.toolbar -> LuiToolbar(backend, node, modifier, children)

        LuiNodeKind.statusBar -> Text(
            node.text(),
            modifier = modifier,
            textAlign = textAlignment(node.propString("text-alignment")),
            style = MaterialTheme.typography.bodySmall,
            color = luiThemeColor(node.propString("foreground"), foreground = true)
                ?: MaterialTheme.colorScheme.onSurfaceVariant,
        )

        LuiNodeKind.kbd -> Box(
            modifier
                .clip(RoundedCornerShape(4.dp))
                .background(MaterialTheme.colorScheme.onSurface.copy(alpha = 0.08f))
                .border(
                    BorderStroke(0.5.dp, MaterialTheme.colorScheme.onSurface.copy(alpha = 0.2f)),
                    RoundedCornerShape(4.dp),
                )
                .padding(horizontal = 6.dp, vertical = 2.dp),
        ) {
            Text(
                node.text(),
                style = MaterialTheme.typography.labelSmall.copy(
                    fontFamily = FontFamily.Monospace,
                ),
            )
        }

        LuiNodeKind.filePreview,
        LuiNodeKind.br,
        -> Unit

        LuiNodeKind.dialog, LuiNodeKind.sheet -> Unit // modal surfaces handled above

        else -> Column(modifier) {
            children.forEach { LuiNodeView(backend, it) }
        }
    }
}

private fun mainHorizontalAlignment(name: String?): Alignment.Horizontal = when (name) {
    "center" -> Alignment.CenterHorizontally
    "end" -> Alignment.End
    else -> Alignment.Start
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun LuiGrid(
    backend: LuiBackend,
    node: LuiNode,
    modifier: Modifier,
    children: List<Long>,
) {
    val requested = node.propInt("columns")
    val columns = if (requested > 0) requested else maxOf(children.size, 1)
    val gap = gapOf(node)
    FlowRow(
        modifier = modifier,
        horizontalArrangement = Arrangement.spacedBy(gap.dp),
        verticalArrangement = Arrangement.spacedBy(gap.dp),
        maxItemsInEachRow = columns,
    ) {
        children.forEach { childId ->
            Box(Modifier.weight(1f)) { LuiNodeView(backend, childId) }
        }
    }
}

/**
 * Stack-family renderer: children overlay each other; a dropdown-menu
 * child renders as an anchored popup and a tooltip child (with `anchor`)
 * wraps the stack in a tooltip.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun LuiStackLike(
    backend: LuiBackend,
    node: LuiNode,
    modifier: Modifier,
    children: List<Long>,
) {
    val menuId = children.firstOrNull { backend.node(it)?.kind == LuiNodeKind.dropdownMenu }
    val tooltipId = children.firstOrNull {
        val child = backend.node(it)
        child?.kind == LuiNodeKind.tooltip && child.prop("anchor") != null
    }
    val visible = children.filter { it != menuId && it != tooltipId }

    val stackContent: @Composable () -> Unit = {
        Box(modifier) {
            visible.forEach { childId ->
                val child = backend.node(childId)
                val fill = (child?.prop("grow")?.numberValue ?: 0.0) > 0
                Box(
                    if (fill) Modifier.fillMaxSize() else Modifier,
                    contentAlignment = child?.propString("alignment")?.let(::overlayAlignment)
                        ?: Alignment.TopStart,
                ) {
                    LuiNodeView(backend, childId)
                }
            }
        }
    }

    val withTooltip: @Composable () -> Unit = if (tooltipId != null) {
        {
            val tooltip = backend.node(tooltipId)!!
            TooltipBox(
                positionProvider = TooltipDefaults.rememberPlainTooltipPositionProvider(
                    spacingBetweenTooltipAndAnchor = (
                        tooltip.prop("anchor-offset")?.numberValue ?: 4.0
                        ).dp,
                ),
                tooltip = { Text(tooltip.propString("text") ?: "") },
                state = rememberTooltipState(),
            ) {
                stackContent()
            }
        }
    } else {
        stackContent
    }

    if (menuId == null) {
        withTooltip()
    } else {
        val menu = backend.node(menuId)
        Box {
            withTooltip()
            if (menu != null) {
                DropdownMenu(
                    expanded = true,
                    onDismissRequest = { backend.emit(LuiEvent.Dismiss(menuId)) },
                ) {
                    menu.children.forEach { childId -> LuiMenuEntry(backend, childId) }
                }
            }
        }
    }
}

/** edge-inset: first child fills; the rest pin to `edge` in a row/column group. */
@Composable
private fun LuiEdgeInset(
    backend: LuiBackend,
    node: LuiNode,
    modifier: Modifier,
    children: List<Long>,
) {
    val visible = node.propBool("visible", true)
    val edge = node.propString("edge") ?: "top"
    val gap = gapOf(node)
    Box(modifier) {
        children.firstOrNull()?.let { LuiNodeView(backend, it) }
        if (visible && children.size > 1) {
            val pinned = children.drop(1)
            val alignment = when (edge) {
                "bottom" -> Alignment.BottomCenter
                "leading" -> Alignment.CenterStart
                "trailing" -> Alignment.CenterEnd
                else -> Alignment.TopCenter
            }
            Box(
                Modifier.fillMaxSize().padding(
                    top = if (edge == "top") gap.dp else 0.dp,
                    bottom = if (edge == "bottom") gap.dp else 0.dp,
                    start = if (edge == "leading") gap.dp else 0.dp,
                    end = if (edge == "trailing") gap.dp else 0.dp,
                ),
            ) {
                if (edge == "leading" || edge == "trailing") {
                    Row(Modifier.align(alignment)) {
                        pinned.forEach { LuiNodeView(backend, it) }
                    }
                } else {
                    Column(Modifier.align(alignment)) {
                        pinned.forEach { LuiNodeView(backend, it) }
                    }
                }
            }
        }
    }
}

/** overlay: children after the first float over it, aligned per-child. */
@Composable
private fun LuiOverlay(
    backend: LuiBackend,
    node: LuiNode,
    modifier: Modifier,
    children: List<Long>,
) {
    val fallback = overlayAlignment(node.propString("alignment"))
    Box(modifier) {
        children.forEachIndexed { index, childId ->
            if (index == 0) {
                LuiNodeView(backend, childId)
            } else {
                val child = backend.node(childId)
                Box(
                    Modifier.fillMaxSize(),
                    contentAlignment = child?.propString("alignment")
                        ?.let(::overlayAlignment) ?: fallback,
                ) {
                    LuiNodeView(backend, childId)
                }
            }
        }
    }
}

@Composable
private fun LuiBubble(
    backend: LuiBackend,
    node: LuiNode,
    modifier: Modifier,
    children: List<Long>,
) {
    Column(modifier.width(IntrinsicSize.Max)) {
        Box { children.forEach { LuiNodeView(backend, it) } }
        if (node.text().isNotEmpty()) {
            val alignment = when (node.propString("text-alignment")) {
                "start" -> Alignment.Start
                "center" -> Alignment.CenterHorizontally
                else -> Alignment.End
            }
            Surface(
                modifier = Modifier.align(alignment).padding(top = 4.dp),
                shape = RoundedCornerShape(8.dp),
                color = MaterialTheme.colorScheme.secondaryContainer,
            ) {
                Text(
                    node.text(),
                    modifier = Modifier.padding(horizontal = 8.dp, vertical = 2.dp),
                    style = MaterialTheme.typography.labelSmall,
                )
            }
        }
    }
}

/**
 * button / tab-trigger: variant and size mapping ported from the Flutter
 * backend; tab triggers render as compact surface chips inside `tabs`.
 */
@Composable
private fun LuiButton(
    backend: LuiBackend,
    node: LuiNode,
    id: Long,
    modifier: Modifier,
    children: List<Long>,
) {
    val enabled = node.isEnabled()
    val variant = node.propString("variant") ?: "default"
    val isTabTrigger = node.parent?.let { backend.node(it)?.kind } == LuiNodeKind.tabs
    val selected = node.propBool("selected")
    val foreground = luiThemeColor(node.propString("foreground"), foreground = true)

    val icon = node.propString("icon")?.let { backend.icons.icon(it) }
    val iconSize = when (node.propString("size")) {
        "sm" -> 16.dp
        "lg", "icon" -> 24.dp
        else -> 18.dp
    }

    val label: @Composable () -> Unit = {
        if (children.isNotEmpty()) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                children.forEach { LuiNodeView(backend, it) }
            }
        } else {
            when {
                node.text().isEmpty() && icon != null -> Icon(
                    icon,
                    contentDescription = node.propString("accessibility-label"),
                    modifier = Modifier.size(iconSize),
                )
                icon == null -> Text(
                    node.text(),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                else -> Row(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    if (node.propString("icon-placement") == "trailing") {
                        Text(node.text(), maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Icon(icon, contentDescription = null, modifier = Modifier.size(iconSize))
                    } else {
                        Icon(icon, contentDescription = null, modifier = Modifier.size(iconSize))
                        Text(node.text(), maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
            }
        }
    }

    val onClick = { backend.emit(LuiEvent.Press(id)) }

    if (isTabTrigger) {
        TextButton(
            onClick = onClick,
            modifier = modifier.height(32.dp),
            enabled = enabled,
            shape = RoundedCornerShape(6.dp),
            colors = androidx.compose.material3.ButtonDefaults.textButtonColors(
                containerColor = if (selected) {
                    MaterialTheme.colorScheme.surface
                } else {
                    Color.Transparent
                },
                contentColor = foreground ?: MaterialTheme.colorScheme.onSurface,
            ),
        ) { label() }
        return
    }

    when (variant) {
        "primary" -> androidx.compose.material3.Button(
            onClick = onClick,
            modifier = modifier,
            enabled = enabled,
        ) { label() }
        "secondary" -> androidx.compose.material3.FilledTonalButton(
            onClick = onClick,
            modifier = modifier,
            enabled = enabled,
        ) { label() }
        "outline" -> androidx.compose.material3.OutlinedButton(
            onClick = onClick,
            modifier = modifier,
            enabled = enabled,
        ) { label() }
        "destructive" -> androidx.compose.material3.Button(
            onClick = onClick,
            modifier = modifier,
            enabled = enabled,
            colors = androidx.compose.material3.ButtonDefaults.buttonColors(
                containerColor = MaterialTheme.colorScheme.error,
                contentColor = MaterialTheme.colorScheme.onError,
            ),
        ) { label() }
        else -> TextButton(
            onClick = onClick,
            modifier = modifier,
            enabled = enabled,
        ) { label() }
    }
}

/** Toggle buttons keep a local selection so taps feel instant; the model
 * `selected` prop re-syncs on the next patch. */
@Composable
private fun LuiToggleButton(backend: LuiBackend, node: LuiNode, id: Long, modifier: Modifier) {
    val enabled = node.isEnabled()
    var selected by remember(id) { mutableStateOf(node.propBool("selected")) }
    val modelSelected = node.propBool("selected")
    LaunchedEffect(modelSelected) { selected = modelSelected }
    FilterChip(
        selected = selected,
        onClick = {
            if (enabled) {
                selected = !selected
                backend.emit(LuiEvent.ToggleChanged(id, selected))
            }
        },
        label = { Text(node.text()) },
        modifier = modifier,
        enabled = enabled,
    )
}

/** Text-entry kinds: text-field, secure-field, input, search-field, textarea, combobox. */
@Composable
private fun LuiTextControl(
    backend: LuiBackend,
    node: LuiNode,
    id: Long,
    modifier: Modifier,
) {
    val multiline = node.kind == LuiNodeKind.textarea
    val secure = node.kind == LuiNodeKind.secureField
    val search = node.kind == LuiNodeKind.searchField
    val combobox = node.kind == LuiNodeKind.combobox
    val enabled = node.isEnabled()
    val grouped = node.parent?.let { backend.node(it)?.kind } == LuiNodeKind.inputGroup

    // Local text keeps typing responsive; the model's `text` prop re-syncs
    // when a patch changes it.
    var localText by remember(id) { mutableStateOf(node.text()) }
    val modelText = node.text()
    LaunchedEffect(modelText) { if (modelText != localText) localText = modelText }

    OutlinedTextField(
        value = localText,
        onValueChange = { value ->
            localText = value
            backend.emit(LuiEvent.TextChanged(id, value))
        },
        modifier = modifier.then(
            if (grouped) Modifier.fillMaxWidth() else Modifier.width(240.dp),
        ),
        enabled = enabled,
        placeholder = node.propString("placeholder")?.let { p -> { Text(p) } },
        singleLine = !multiline,
        minLines = if (multiline) 3 else 1,
        visualTransformation = if (secure) {
            androidx.compose.ui.text.input.PasswordVisualTransformation()
        } else {
            androidx.compose.ui.text.input.VisualTransformation.None
        },
        trailingIcon = if (combobox || search) {
            {
                Icon(
                    if (combobox) Icons.Filled.KeyboardArrowDown else backend.icons.icon("search") ?: Icons.Filled.Search,
                    contentDescription = null,
                    modifier = if (combobox && enabled) {
                        Modifier.pointerInput(id) {
                            detectTapGestures { backend.emit(LuiEvent.Press(id)) }
                        }
                    } else {
                        Modifier
                    },
                )
            }
        } else {
            null
        },
        textStyle = MaterialTheme.typography.bodyMedium.copy(
            color = luiThemeColor(node.propString("foreground"), foreground = true)
                ?: MaterialTheme.colorScheme.onSurface,
        ),
    )
}

@Composable
private fun LuiSelect(backend: LuiBackend, node: LuiNode, id: Long, modifier: Modifier) {
    val enabled = node.isEnabled()
    val title = node.propString("accessibility-label") ?: node.propString("placeholder") ?: ""
    val value = node.text().ifEmpty { node.propString("placeholder") ?: "" }
    ListItem(
        headlineContent = { Text(if (title.isNotEmpty()) title else value) },
        supportingContent = if (title.isNotEmpty() && value != title && value.isNotEmpty()) {
            { Text(value) }
        } else {
            null
        },
        trailingContent = {
            Icon(
                Icons.Filled.KeyboardArrowDown,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        },
        modifier = modifier.clickable(enabled = enabled) {
            backend.emit(LuiEvent.Press(id))
        },
    )
}

/** A menu entry (used both inside dropdown menus and context menus). */
@Composable
internal fun LuiMenuEntry(backend: LuiBackend, childId: Long) {
    val child = backend.node(childId) ?: return
    when (child.kind) {
        LuiNodeKind.divider -> HorizontalDivider()
        LuiNodeKind.menuItem -> LuiMenuItem(backend, child, childId, Modifier)
        LuiNodeKind.menuTrigger -> LuiMenuTrigger(backend, child, childId, Modifier)
        else -> LuiNodeView(backend, childId)
    }
}

@Composable
private fun LuiMenuItem(backend: LuiBackend, node: LuiNode, id: Long, modifier: Modifier) {
    val submenuId =
        node.children.firstOrNull { backend.node(it)?.kind == LuiNodeKind.dropdownMenu }
    val enabled = node.isEnabled()
    val icon = node.propString("icon")?.let { backend.icons.icon(it) }
    val selected = node.propBool("selected")
    val destructive = node.propString("variant") == "destructive"

    if (submenuId != null) {
        var submenuOpen by remember(id) { mutableStateOf(false) }
        Box {
            DropdownMenuItem(
                text = { Text(node.text()) },
                onClick = { submenuOpen = true },
                enabled = enabled,
                leadingIcon = icon?.let { { Icon(it, null, Modifier.size(16.dp)) } },
                trailingIcon = {
                    Icon(Icons.Filled.KeyboardArrowRight, null, Modifier.size(16.dp))
                },
            )
            val submenu = backend.node(submenuId)
            if (submenu != null) {
                DropdownMenu(
                    expanded = submenuOpen,
                    onDismissRequest = { submenuOpen = false },
                ) {
                    submenu.children.forEach { LuiMenuEntry(backend, it) }
                }
            }
        }
        return
    }

    DropdownMenuItem(
        text = {
            Text(
                node.text(),
                color = if (destructive) MaterialTheme.colorScheme.error else Color.Unspecified,
            )
        },
        onClick = { if (enabled) backend.emit(LuiEvent.Press(id)) },
        enabled = enabled,
        modifier = modifier,
        leadingIcon = icon?.let { { Icon(it, null, Modifier.size(16.dp)) } },
        trailingIcon = if (selected) {
            { Icon(Icons.Filled.Check, null, Modifier.size(16.dp)) }
        } else {
            null
        },
    )
}

@Composable
private fun LuiMenuTrigger(backend: LuiBackend, node: LuiNode, id: Long, modifier: Modifier) {
    val menuId = node.children.firstOrNull { backend.node(it)?.kind == LuiNodeKind.dropdownMenu }
    val enabled = node.isEnabled()
    val icon = node.propString("icon")?.let { backend.icons.icon(it) }
    val iconSize = if (node.text().isEmpty()) 24.dp else 16.dp
    var open by remember(id) { mutableStateOf(false) }

    Box {
        TextButton(
            onClick = { open = !open },
            enabled = enabled,
            modifier = modifier,
        ) {
            if (icon != null && node.text().isEmpty()) {
                Icon(
                    icon,
                    contentDescription = node.propString("accessibility-label"),
                    modifier = Modifier.size(iconSize),
                )
            } else if (icon != null) {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(icon, null, Modifier.size(iconSize))
                    if (node.text().isNotEmpty()) Text(node.text())
                }
            } else {
                Text(node.text())
            }
        }
        val menu = menuId?.let { backend.node(it) }
        if (menu != null && menuId != null) {
            DropdownMenu(
                expanded = open,
                onDismissRequest = {
                    open = false
                    backend.emit(LuiEvent.Dismiss(menuId))
                },
            ) {
                menu.children.forEach { LuiMenuEntry(backend, it) }
            }
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun LuiListItem(
    backend: LuiBackend,
    node: LuiNode,
    id: Long,
    modifier: Modifier,
    children: List<Long>,
) {
    val enabled = node.isEnabled()
    val icon = node.propString("icon")?.let { backend.icons.icon(it) }
    ListItem(
        headlineContent = {
            if (children.isEmpty()) {
                Text(node.text())
            } else {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    if (node.text().isNotEmpty()) Text(node.text())
                    children.forEach { LuiNodeView(backend, it) }
                }
            }
        },
        leadingContent = icon?.let { { Icon(it, null, Modifier.size(16.dp)) } },
        modifier = modifier.combinedClickable(
            enabled = enabled,
            onClick = {
                if (node.propString("role") == "treeitem") {
                    if (node.propBool("press-enabled")) {
                        backend.emit(LuiEvent.Press(id))
                    } else if (node.propBool("change-enabled")) {
                        backend.emit(LuiEvent.Change(id))
                    }
                    if (node.propBool("toggle-enabled")) {
                        backend.emit(LuiEvent.ToggleChanged(id, !node.propBool("expanded")))
                    }
                } else if (node.propBool("press-enabled")) {
                    backend.emit(LuiEvent.Press(id))
                }
            },
            onLongClick = if (node.propBool("long-press-enabled")) {
                { backend.emit(LuiEvent.LongPress(id)) }
            } else {
                null
            },
            onDoubleClick = if (node.propBool("double-press-enabled")) {
                { backend.emit(LuiEvent.DoublePress(id)) }
            } else {
                null
            },
        ),
    )
}

@Composable
private fun LuiAvatar(backend: LuiBackend, node: LuiNode, modifier: Modifier) {
    val image = backend.images[node.propInt("image")]
    Box(
        modifier.size(40.dp).clip(CircleShape)
            .background(MaterialTheme.colorScheme.secondaryContainer),
        contentAlignment = Alignment.Center,
    ) {
        if (image != null) {
            Image(
                bitmap = image,
                contentDescription = node.propString("accessibility-label") ?: node.text(),
                modifier = Modifier.fillMaxSize(),
                contentScale = ContentScale.Crop,
            )
        } else if (node.text().isNotEmpty()) {
            Text(node.text(), style = MaterialTheme.typography.labelLarge)
        } else {
            Icon(
                backend.icons.icon("person") ?: Icons.Filled.Person,
                contentDescription = node.propString("accessibility-label"),
                tint = MaterialTheme.colorScheme.onSecondaryContainer,
            )
        }
    }
}

@Composable
private fun LuiImage(backend: LuiBackend, node: LuiNode, modifier: Modifier) {
    val bitmap = backend.images[node.propInt("image")]
    val alt = node.propString("alt") ?: node.propString("accessibility-label")
    if (bitmap != null) {
        Image(
            bitmap = bitmap,
            contentDescription = alt,
            modifier = modifier,
            contentScale = ContentScale.Crop,
        )
    } else {
        // URL loading is intentionally not built in: register pixels via
        // LuiBackend.registerImage, or resolve paths through
        // filePathResolver + file-image. Keeps the module network-free.
        Box(modifier.fillMaxSize())
    }
}

@Composable
private fun LuiFileImage(backend: LuiBackend, node: LuiNode, modifier: Modifier) {
    val path = backend.filePathResolver?.invoke(node.propString("path") ?: "")
        ?: node.propString("path") ?: ""
    val maxPixel = node.propInt("max-pixel-size", 1024)
    var bitmap by remember(path) { mutableStateOf<ImageBitmap?>(null) }
    LaunchedEffect(path) {
        if (path.isNotEmpty()) {
            bitmap = runCatching { decodeSampled(path, maxPixel) }.getOrNull()
        }
    }
    val radius = node.propInt("corner-radius")
    val clip = if (radius > 0) Modifier.clip(RoundedCornerShape(radius.dp)) else Modifier
    val image = bitmap
    if (image != null) {
        Image(
            bitmap = image,
            contentDescription = node.propString("accessibility-label"),
            modifier = modifier.then(clip),
            contentScale = if (node.propString("image-fit") == "fill") {
                ContentScale.Crop
            } else {
                ContentScale.Fit
            },
        )
    } else {
        Box(modifier.then(clip), contentAlignment = Alignment.Center) {
            Icon(
                backend.icons.icon("image") ?: Icons.Filled.Star,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

private fun decodeSampled(path: String, maxPixel: Int): ImageBitmap? {
    val bounds = android.graphics.BitmapFactory.Options().apply { inJustDecodeBounds = true }
    android.graphics.BitmapFactory.decodeFile(path, bounds)
    if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
    var sample = 1
    val longest = maxOf(bounds.outWidth, bounds.outHeight)
    while (longest / (sample * 2) > maxPixel) sample *= 2
    val options = android.graphics.BitmapFactory.Options().apply { inSampleSize = sample }
    return android.graphics.BitmapFactory.decodeFile(path, options)?.asImageBitmap()
}

@Composable
private fun LuiMediaSurface(backend: LuiBackend, node: LuiNode, modifier: Modifier) {
    val frame = backend.mediaSurfaces[node.propInt("surface")]
    if (frame != null) {
        Image(
            bitmap = frame,
            contentDescription = node.propString("accessibility-label"),
            modifier = modifier,
            contentScale = ContentScale.Crop,
        )
    } else {
        Box(modifier.fillMaxSize().background(MaterialTheme.colorScheme.surfaceContainerHigh))
    }
}

@Composable
private fun LuiStep(backend: LuiBackend, node: LuiNode, id: Long, modifier: Modifier) {
    val parent = node.parent?.let { backend.node(it) }
    val index = parent?.children?.indexOf(id) ?: 0
    val count = parent?.children?.size ?: 1
    val active = parent?.propInt("active") ?: 0
    val state = when {
        index < active -> "completed"
        index == active -> "active"
        else -> "pending"
    }
    val activeColor = MaterialTheme.colorScheme.primary
    Row(modifier.wrapContentSize(), verticalAlignment = Alignment.CenterVertically) {
        Box(
            Modifier.size(24.dp).clip(CircleShape)
                .background(if (state == "pending") Color.Transparent else activeColor)
                .border(
                    BorderStroke(
                        1.dp,
                        if (state == "pending") {
                            MaterialTheme.colorScheme.outline
                        } else {
                            activeColor
                        },
                    ),
                    CircleShape,
                ),
            contentAlignment = Alignment.Center,
        ) {
            if (state == "completed") {
                Icon(
                    Icons.Filled.Check,
                    contentDescription = null,
                    modifier = Modifier.size(14.dp),
                    tint = MaterialTheme.colorScheme.onPrimary,
                )
            } else {
                Text(
                    "${index + 1}",
                    style = MaterialTheme.typography.labelSmall.copy(
                        fontWeight = FontWeight.SemiBold,
                        color = if (state == "active") {
                            MaterialTheme.colorScheme.onPrimary
                        } else {
                            MaterialTheme.colorScheme.onSurfaceVariant
                        },
                    ),
                )
            }
        }
        Spacer(Modifier.width(6.dp))
        Text(
            node.text(),
            style = MaterialTheme.typography.bodyMedium.copy(
                fontWeight = if (state == "active") FontWeight.SemiBold else FontWeight.Normal,
                color = if (state == "pending") {
                    MaterialTheme.colorScheme.onSurfaceVariant
                } else {
                    Color.Unspecified
                },
            ),
        )
        if (index + 1 < count) {
            Spacer(Modifier.width(8.dp))
            Box(Modifier.width(24.dp).height(1.dp).background(MaterialTheme.colorScheme.outlineVariant))
            Spacer(Modifier.width(8.dp))
        }
    }
}

@Composable
private fun LuiTimelineItem(backend: LuiBackend, node: LuiNode, id: Long, modifier: Modifier) {
    val variantColor = when (node.propString("variant")) {
        "primary" -> MaterialTheme.colorScheme.primary
        "destructive" -> MaterialTheme.colorScheme.error
        else -> MaterialTheme.colorScheme.outline
    }
    val connector = node.propBool("connector", true)
    val pressable = node.propBool("press-enabled")
    val enabled = node.isEnabled()

    Surface(
        modifier = modifier,
        shape = RoundedCornerShape(8.dp),
        color = if (node.propBool("selected")) {
            MaterialTheme.colorScheme.secondaryContainer
        } else {
            Color.Transparent
        },
    ) {
        Row(
            Modifier.padding(8.dp).then(
                if (pressable && enabled) {
                    Modifier.pointerInput(id) {
                        detectTapGestures { backend.emit(LuiEvent.Press(id)) }
                    }
                } else {
                    Modifier
                },
            ),
            verticalAlignment = Alignment.Top,
        ) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Box(Modifier.size(24.dp), contentAlignment = Alignment.Center) {
                    val iconName = node.propString("icon") ?: ""
                    val indicator = node.propString("indicator") ?: ""
                    when {
                        iconName.isNotEmpty() -> Icon(
                            backend.icons.icon(iconName) ?: Icons.Filled.Star,
                            contentDescription = null,
                            modifier = Modifier.size(16.dp),
                            tint = variantColor,
                        )
                        indicator.isNotEmpty() -> Text(
                            indicator,
                            style = MaterialTheme.typography.labelSmall.copy(
                                color = variantColor,
                                fontWeight = FontWeight.SemiBold,
                            ),
                        )
                        else -> Box(Modifier.size(10.dp).clip(CircleShape).background(variantColor))
                    }
                }
                if (connector) {
                    Box(
                        Modifier.width(1.dp).height(28.dp)
                            .background(MaterialTheme.colorScheme.outlineVariant),
                    )
                }
            }
            Spacer(Modifier.width(10.dp))
            Column(Modifier.weight(1f)) {
                val title = node.propString("title") ?: ""
                if (title.isNotEmpty()) {
                    Text(
                        title,
                        style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.SemiBold),
                    )
                }
                val description = node.propString("description") ?: ""
                if (description.isNotEmpty()) {
                    Text(
                        description,
                        style = MaterialTheme.typography.bodyMedium.copy(
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        ),
                    )
                }
                val meta = node.propString("meta") ?: ""
                if (meta.isNotEmpty()) {
                    Text(
                        meta,
                        style = MaterialTheme.typography.bodySmall.copy(
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        ),
                    )
                }
            }
            if (pressable) {
                Icon(
                    Icons.Filled.KeyboardArrowRight,
                    contentDescription = null,
                    modifier = Modifier.size(18.dp),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
private fun LuiInputGroup(
    backend: LuiBackend,
    node: LuiNode,
    modifier: Modifier,
    children: List<Long>,
) {
    Surface(
        modifier = modifier,
        shape = RoundedCornerShape(8.dp),
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant),
        color = MaterialTheme.colorScheme.surface,
    ) {
        Column(Modifier.fillMaxWidth()) {
            children.forEach { LuiNodeView(backend, it) }
        }
    }
}

@Composable
private fun LuiBottomTabs(backend: LuiBackend, node: LuiNode, modifier: Modifier) {
    val destinationIds = node.children
    val selectedIndex = destinationIds.indexOfFirst {
        backend.node(it)?.propBool("selected") == true
    }.let { if (it < 0) 0 else it }
    Column(modifier.fillMaxSize()) {
        Box(Modifier.weight(1f)) {
            destinationIds.getOrNull(selectedIndex)?.let { LuiNodeView(backend, it) }
        }
        NavigationBar {
            destinationIds.forEachIndexed { index, destId ->
                val dest = backend.node(destId) ?: return@forEachIndexed
                NavigationBarItem(
                    selected = index == selectedIndex,
                    onClick = {
                        if (dest.isEnabled() && dest.propBool("press-enabled")) {
                            backend.emit(LuiEvent.Press(destId))
                        }
                    },
                    icon = {
                        backend.icons.icon(dest.propString("icon") ?: "")?.let { Icon(it, contentDescription = null) }
                    },
                    label = { Text(dest.propString("title") ?: "") },
                    enabled = dest.isEnabled(),
                )
            }
        }
    }
}

@Composable
private fun LuiAccordion(
    backend: LuiBackend,
    node: LuiNode,
    id: Long,
    modifier: Modifier,
    children: List<Long>,
) {
    val expanded = node.propBool("selected") || node.propBool("expanded")
    Column(modifier) {
        Row(
            Modifier.fillMaxWidth()
                .clickable(enabled = node.propBool("toggle-enabled")) {
                    backend.emit(LuiEvent.ToggleChanged(id, !expanded))
                }
                .padding(vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(node.text(), Modifier.weight(1f), style = MaterialTheme.typography.titleSmall)
            Icon(
                if (expanded) Icons.Filled.KeyboardArrowDown else Icons.Filled.KeyboardArrowRight,
                contentDescription = null,
            )
        }
        if (expanded) {
            Column {
                children.forEach { LuiNodeView(backend, it) }
            }
        }
    }
}

@Composable
private fun LuiTableRow(
    backend: LuiBackend,
    node: LuiNode,
    id: Long,
    modifier: Modifier,
    children: List<Long>,
) {
    val parent = node.parent?.let { backend.node(it) }
    val isLast = parent == null || parent.children.lastOrNull() == id
    val gap = gapOf(node)
    Column(modifier) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            children.forEach { childId ->
                val grow = backend.node(childId)?.prop("grow")?.numberValue ?: 0.0
                val cellModifier = Modifier.padding(horizontal = (gap / 2).dp).let {
                    if (grow > 0) it.weight(grow.toFloat().coerceAtLeast(0.001f)) else it
                }
                Box(cellModifier) { LuiNodeView(backend, childId) }
            }
        }
        if (!isLast) {
            HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
        }
    }
}

@Composable
private fun LuiTableCell(backend: LuiBackend, node: LuiNode, id: Long, modifier: Modifier) {
    val enabled = node.isEnabled()
    Text(
        node.text(),
        modifier = modifier.fillMaxWidth().then(
            if (node.propBool("press-enabled") && enabled) {
                Modifier
                    .pointerInput(id) {
                        detectTapGestures { backend.emit(LuiEvent.Press(id)) }
                    }
                    .padding(vertical = 12.dp)
            } else {
                Modifier
            },
        ),
        textAlign = textAlignment(node.propString("text-alignment")),
        style = LuiTypography.textStyleForSize(node.propString("size")).copy(
            color = luiThemeColor(node.propString("foreground"), foreground = true)
                ?: Color.Unspecified,
        ),
    )
}

/**
 * drawer: modal side panel over the main content; `selected` controls
 * presentation, scrim tap emits ToggleChanged(false).
 */
@Composable
private fun LuiDrawer(
    backend: LuiBackend,
    node: LuiNode,
    id: Long,
    modifier: Modifier,
    children: List<Long>,
) {
    val presented = node.propBool("selected")
    val width = node.propInt("width", 320)
    val enabled = node.isEnabled()
    Box(modifier.fillMaxSize()) {
        children.firstOrNull()?.let { LuiNodeView(backend, it) }
        if (presented) {
            Box(
                Modifier.fillMaxSize()
                    .background(Color.Black.copy(alpha = 0.32f))
                    .pointerInput(id) {
                        detectTapGestures {
                            if (enabled && node.propBool("toggle-enabled")) {
                                backend.emit(LuiEvent.ToggleChanged(id, false))
                            }
                        }
                    },
            )
            Surface(
                modifier = Modifier.fillMaxHeight()
                    .width(width.dp.coerceAtMost(360.dp))
                    .align(Alignment.CenterStart),
                color = MaterialTheme.colorScheme.surface,
                shadowElevation = 8.dp,
            ) {
                Column {
                    children.drop(1).forEach { LuiNodeView(backend, it) }
                }
            }
        }
    }
}

/**
 * split: two panes separated by a draggable divider; `value` is the first
 * pane's fraction. Dragging emits ValueChanged continuously (the model may
 * echo the prop back).
 */
@Composable
private fun LuiSplit(
    backend: LuiBackend,
    node: LuiNode,
    id: Long,
    modifier: Modifier,
    children: List<Long>,
) {
    val fraction = node.propDouble("value").coerceIn(0.05, 0.95)
    val enabled = node.isEnabled()
    BoxWithConstraints(modifier.fillMaxSize()) {
        val total = constraints.maxWidth.toFloat()
        Row(Modifier.fillMaxSize()) {
            Box(Modifier.weight(fraction.toFloat().coerceAtLeast(0.01f))) {
                children.getOrNull(0)?.let { LuiNodeView(backend, it) }
            }
            Box(
                Modifier.width(9.dp).fillMaxHeight().pointerInput(id, total) {
                    detectHorizontalDragGestures { _, dragAmount ->
                        if (enabled && total > 0) {
                            val next = fraction + dragAmount / total
                            backend.emit(LuiEvent.ValueChanged(id, next.toDouble()))
                        }
                    }
                },
                contentAlignment = Alignment.Center,
            ) {
                Box(
                    Modifier.width(1.dp).fillMaxHeight()
                        .background(MaterialTheme.colorScheme.outlineVariant),
                )
            }
            Box(Modifier.weight((1f - fraction).toFloat().coerceAtLeast(0.01f))) {
                children.getOrNull(1)?.let { LuiNodeView(backend, it) }
            }
        }
    }
}

/** toast: card with a timed auto-dismiss; duration 0 stays until dropped. */
@Composable
private fun LuiToast(
    backend: LuiBackend,
    node: LuiNode,
    id: Long,
    modifier: Modifier,
    children: List<Long>,
) {
    val duration = node.propInt("duration")
    if (duration > 0) {
        LaunchedEffect(id, duration) {
            kotlinx.coroutines.delay(duration.toLong())
            backend.emit(LuiEvent.Dismiss(id))
        }
    }
    Card(modifier) {
        Row(
            Modifier.padding(16.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            children.forEach { LuiNodeView(backend, it) }
        }
    }
}

/**
 * toolbar: horizontal scroll row (or vertical column); `scroll-leading`
 * pins the last child at the trailing edge.
 */
@Composable
private fun LuiToolbar(
    backend: LuiBackend,
    node: LuiNode,
    modifier: Modifier,
    children: List<Long>,
) {
    val gap = gapOf(node)
    if (node.propString("orientation") == "vertical") {
        Column(modifier, verticalArrangement = Arrangement.spacedBy(gap.dp)) {
            children.forEach { LuiNodeView(backend, it) }
        }
        return
    }
    val pinTrailing = (node.propString("style-class") ?: "")
        .split(" ").contains("scroll-leading") && children.size >= 2
    if (!pinTrailing) {
        Row(
            modifier.horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(gap.dp),
        ) {
            children.forEach { LuiNodeView(backend, it) }
        }
    } else {
        Row(modifier, horizontalArrangement = Arrangement.spacedBy(gap.dp)) {
            Row(
                Modifier.weight(1f).horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(gap.dp),
            ) {
                children.dropLast(1).forEach { LuiNodeView(backend, it) }
            }
            LuiNodeView(backend, children.last())
        }
    }
}

/**
 * Modal surfaces (dialog, sheet): shown while the node exists; dismissal
 * emits Dismiss so the model drops the node.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun LuiModalSurface(backend: LuiBackend, node: LuiNode, id: Long) {
    val onDismiss = { backend.emit(LuiEvent.Dismiss(id)) }
    when (node.kind) {
        LuiNodeKind.dialog -> AlertDialog(
            onDismissRequest = onDismiss,
            confirmButton = {},
            text = {
                Column {
                    node.children.forEach { LuiNodeView(backend, it) }
                }
            },
        )
        LuiNodeKind.sheet -> ModalBottomSheet(
            onDismissRequest = onDismiss,
            sheetState = rememberModalBottomSheetState(),
        ) {
            Column {
                node.children.forEach { LuiNodeView(backend, it) }
            }
        }
        else -> Unit
    }
}
