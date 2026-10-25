package dev.lui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.flow.distinctUntilChanged

/** Native scroll state survives destinations being removed from composition. */
internal data class LuiScrollPosition(val index: Int = 0, val offset: Int = 0)
val LocalLuiSectionTitle = compositionLocalOf<String?> { null }
val LocalLuiSectionTitleChanged = compositionLocalOf<(String) -> Unit> { {} }
val LocalLuiScrollingEnabled = compositionLocalOf { true }

internal fun LuiNodeLike.dataAttributes(): Map<String, String> =
    propString("data-attrs").orEmpty().split('\u001e').mapNotNull { entry ->
        val split = entry.indexOf('\u001f')
        if (split < 0) null else entry.substring(0, split) to entry.substring(split + 1)
    }.toMap()

private data class WindowedChildren(
    val before: List<Long>, val window: Long?, val after: List<Long>,
)

private fun windowedChildren(backend: LuiBackend, children: List<Long>): WindowedChildren {
    val before = mutableListOf<Long>()
    val after = mutableListOf<Long>()
    var window: Long? = null
    fun hasWindow(id: Long): Boolean {
        val child = backend.node(id) ?: return false
        return child.dataAttributes().containsKey("data-virtual-count") || child.children.any(::hasWindow)
    }
    fun visit(ids: List<Long>) {
        ids.forEach { id ->
            val child = backend.node(id)
            when {
                child?.dataAttributes()?.containsKey("data-virtual-count") == true -> window = id
                child != null && hasWindow(id) -> visit(child.children)
                window == null -> before.add(id)
                else -> after.add(id)
            }
        }
    }
    visit(children)
    return WindowedChildren(before, window, after)
}

/** One native lazy list owns headers, virtual rows and pagination sentinels. */
@Composable
internal fun LuiVirtualList(backend: LuiBackend, node: LuiNodeLike, id: Long, modifier: Modifier) {
    val identity = node.dataAttributes()["data-scroll-identity"] ?: "node:$id"
    val content = windowedChildren(backend, node.children)
    val window = content.window?.let { backend.node(it) }
    val attributes = window?.dataAttributes().orEmpty()
    val count = attributes["data-virtual-count"]?.toIntOrNull() ?: 0
    val start = attributes["data-virtual-start"]?.toIntOrNull() ?: 0
    val pinned = attributes["data-pinned-index"]?.toIntOrNull() ?: -1
    val extent = node.prop("item-extent")?.numberValue
        ?: node.dataAttributes()["data-item-extent"]?.toDoubleOrNull()?.takeIf { it.isFinite() && it > 0 }
        ?: attributes["data-item-extent"]?.toDoubleOrNull()?.takeIf { it.isFinite() && it > 0 }
        ?: 32.0
    val rows = window?.children.orEmpty()
    val length = attributes["data-virtual-length"]?.toIntOrNull() ?: rows.size
    val initial = remember(identity) { backend.scrollPositions[identity] ?: LuiScrollPosition() }
    val state = remember(identity) { LazyListState(initial.index, initial.offset) }
    val heights = remember(identity) { mutableMapOf<Int, Int>() }
    val density = LocalDensity.current
    val titleChanged = LocalLuiSectionTitleChanged.current
    val visible = node.prop("selected")?.boolValue != false
    val sectionTitles = attributes.entries.mapNotNull { (key, value) ->
        key.removePrefix("data-section-title-").toIntOrNull()?.let { it to value }
    }.sortedBy { it.first }
    val currentContent by rememberUpdatedState(content)
    val currentCount by rememberUpdatedState(count)
    val currentWindow by rememberUpdatedState(content.window)
    val currentTitles by rememberUpdatedState(sectionTitles)
    val currentTitleChanged by rememberUpdatedState(titleChanged)
    val currentVisible by rememberUpdatedState(visible)
    val target = attributes["data-scroll-key"]
    val targetIndex = attributes["data-scroll-index"]?.toIntOrNull()

    DisposableEffect(identity) {
        onDispose { backend.scrollPositions[identity] = LuiScrollPosition(state.firstVisibleItemIndex, state.firstVisibleItemScrollOffset) }
    }
    LaunchedEffect(identity, target, targetIndex) {
        if (target != null && targetIndex != null && count > 0) {
            state.scrollToItem(content.before.size + targetIndex.coerceIn(0, count - 1))
        }
    }
    LaunchedEffect(identity, pinned) {
        if (pinned in 0 until count) {
            val index = content.before.size + pinned
            val layout = state.layoutInfo
            val item = layout.visibleItemsInfo.firstOrNull { it.index == index }
            if (item == null || item.offset < layout.viewportStartOffset ||
                item.offset + item.size > layout.viewportEndOffset) {
                state.scrollToItem(index)
            }
        }
    }
    LaunchedEffect(identity, state) {
        var previousRange: Pair<Int, Int>? = null
        snapshotFlow {
            val visible = state.layoutInfo.visibleItemsInfo
            Triple(state.firstVisibleItemIndex, state.firstVisibleItemScrollOffset, visible.lastOrNull()?.index ?: 0)
        }.distinctUntilChanged().collect { (firstItem, offset, lastItem) ->
            backend.scrollPositions[identity] = LuiScrollPosition(firstItem, offset)
            val first = (firstItem - currentContent.before.size).coerceAtLeast(0)
            val last = (lastItem - currentContent.before.size).coerceAtMost(currentCount - 1)
            val id = currentWindow
            val range = first to last
            if (id != null && last >= first && range != previousRange) {
                previousRange = range
                backend.emit(LuiEvent.VisibleRange(id, first.toLong(), last.toLong()))
            }
            if (currentVisible) currentTitles.lastOrNull { it.first <= first }?.second?.let { currentTitleChanged(it) }
        }
    }
    LaunchedEffect(sectionTitles, visible) {
        if (visible) sectionTitles.lastOrNull { it.first <= (state.firstVisibleItemIndex - content.before.size).coerceAtLeast(0) }
            ?.second?.let(titleChanged)
    }
    LazyColumn(modifier = modifier, state = state, userScrollEnabled = visible && LocalLuiScrollingEnabled.current) {
        content.before.forEach { id -> item(key = "fixed:$id") { LuiNodeView(backend, id) } }
        // Preserve the active editor and its input connection when a split moves it.
        items(count, key = { if (it == pinned) "editor:${content.window}" else "row:$it" }) { index ->
            val slot = if (index == pinned && index !in start until start + length) length else index - start
            val id = rows.getOrNull(slot)
            if (id != null) {
                Box(Modifier.fillMaxWidth().onSizeChanged { heights[index] = it.height }) {
                    LuiNodeView(backend, id)
                }
            } else {
                val height = heights[index]?.let { with(density) { it.toDp() } } ?: extent.toFloat().dp
                Spacer(Modifier.fillMaxWidth().height(height))
            }
        }
        content.after.forEach { id -> item(key = "fixed:$id") { LuiNodeView(backend, id) } }
    }
}
