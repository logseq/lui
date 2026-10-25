package dev.lui

import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.scrollable
import androidx.compose.foundation.gestures.scrollBy
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.LocalPinnableContainer
import androidx.compose.ui.layout.PinnableContainer
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.CollectionInfo
import androidx.compose.ui.semantics.CollectionItemInfo
import androidx.compose.ui.semantics.ScrollAxisRange
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.collectionInfo
import androidx.compose.ui.semantics.collectionItemInfo
import androidx.compose.ui.semantics.isTraversalGroup
import androidx.compose.ui.semantics.scrollBy
import androidx.compose.ui.semantics.scrollToIndex
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.verticalScrollAxisRange
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.launch

/** Portal content inherits the same committed row lifetime as its anchor. */
internal val LocalLuiVirtualRowPin = compositionLocalOf<PinnableContainer?> { null }

@Composable
internal fun LuiVirtualPortalLifetime() {
    val owner = LocalLuiVirtualRowPin.current
    DisposableEffect(owner) {
        val handle = owner?.pin()
        onDispose { handle?.release() }
    }
}

private class VirtualPins {
    val counts = mutableStateMapOf<Long, Int>()
    fun acquire(id: Long, native: PinnableContainer?): PinnableContainer.PinnedHandle {
        val delegated = native?.pin()
        counts[id] = (counts[id] ?: 0) + 1
        return object : PinnableContainer.PinnedHandle {
            private var active = true
            override fun release() {
                if (!active) return
                active = false
                delegated?.release()
                val remaining = (counts[id] ?: 1) - 1
                if (remaining == 0) counts.remove(id) else counts[id] = remaining
            }
        }
    }
}

private data class VirtualFeedback(val generation: Long, val first: Int, val last: Int,
    val visibleFirst: Int, val visibleLast: Int, val pins: List<Long>, val epoch: Long, val ready: Boolean)

/** Logical slots remain native lazy items; only committed roots own UI state. */
@Composable
internal fun LuiSparseVirtualList(backend: LuiBackend, node: LuiNodeLike, id: Long, modifier: Modifier) {
    val count = node.prop("virtual-total-count")!!.intValue!!
    val generation = (node.prop("virtual-generation") as LuiWireValue.IntValue).value
    val indices = luiVirtualIndices(node.propString("virtual-indices")!!)!!
    // The retained view is live. Capture structure once so a window batch
    // arriving between measurement and placement cannot mix two revisions.
    val children = node.children
    val rows = indices.zip(children).toMap()
    val rowIndices = rows.entries.associate { (index, row) -> row to index }
    val extent = node.prop("item-extent")?.numberValue ?: 32.0
    val overscan = node.prop("overscan")?.intValue ?: 5
    val identity = node.dataAttributes()["data-scroll-identity"] ?: "node:$id"
    val initial = remember(identity) { backend.scrollPositions[identity] ?: LuiScrollPosition() }
    val state = remember(identity) { LazyListState(initial.index, initial.offset) }
    DisposableEffect(identity, state) {
        onDispose {
            backend.scrollPositions[identity] = LuiScrollPosition(state.firstVisibleItemIndex, state.firstVisibleItemScrollOffset)
        }
    }
    val pins = remember(id) { VirtualPins() }
    val nativeContainers = remember(id) { mutableMapOf<Int, PinnableContainer?>() }
    val measured = remember(id) { mutableMapOf<Long, Int>() }
    val density = LocalDensity.current
    val estimate = with(density) { extent.toFloat().dp.roundToPx() }.coerceAtLeast(1)
    val gap = node.prop("gap")?.intValue ?: 0
    val gapPixels = with(density) { gap.dp.roundToPx() }
    val heights = remember(id, generation, count, estimate, gapPixels) { SparseRowHeights(count, estimate, gapPixels) }
    SideEffect {
        measured.keys.retainAll(rowIndices.keys)
        rowIndices.forEach { (row, index) -> measured[row]?.let { heights.update(index, it) } }
    }
    val currentRows by rememberUpdatedState(rows)
    val currentCount by rememberUpdatedState(count)
    val currentGeneration by rememberUpdatedState(generation)
    val currentOverscan by rememberUpdatedState(overscan)
    val currentEpoch by rememberUpdatedState(backend.snapshotEpoch)
    val currentTrack by rememberUpdatedState(node.prop("track-visible-range")?.boolValue == true)
    val currentRowIndices by rememberUpdatedState(rowIndices)
    var anchor by remember(id) { mutableStateOf<Pair<Long, Int>?>(null) }
    var previousGeneration by remember(id) { mutableLongStateOf(generation) }
    SideEffect {
        // A materialized root may replace an equal-sized placeholder without
        // changing the native visible range, so capture its identity here too.
        if (previousGeneration == generation) {
            rows[state.firstVisibleItemIndex]?.let { anchor = it to state.firstVisibleItemScrollOffset }
        }
    }
    LaunchedEffect(generation) {
        if (generation != previousGeneration) {
            anchor?.let { (row, offset) -> rowIndices[row]?.let { state.scrollToItem(it, offset) } }
            previousGeneration = generation
        }
    }
    LaunchedEffect(id, state) {
        var previousVisible: Pair<Int, Int>? = null
        snapshotFlow {
            val layout = state.layoutInfo
            val visible = layout.visibleItemsInfo.filter {
                it.offset < layout.viewportEndOffset && it.offset + it.size > layout.viewportStartOffset
            }
            val first = visible.firstOrNull()?.index?.coerceAtMost(currentCount) ?: 0
            val last = visible.lastOrNull()?.index?.plus(1)?.coerceAtMost(currentCount) ?: 0
            val windowFirst = (first.toLong() - currentOverscan).coerceAtLeast(0).toInt()
            val windowLast = (last.toLong() + currentOverscan).coerceAtMost(currentCount.toLong()).toInt()
            VirtualFeedback(currentGeneration, windowFirst, windowLast, first, last,
                pins.counts.keys.filter { row -> currentRowIndices[row]?.let { it !in windowFirst until windowLast } == true }.sorted(),
                currentEpoch, previousGeneration == currentGeneration)
        }.distinctUntilChanged().collect { feedback ->
            // Never acknowledge a new source using the old source's viewport.
            // First commit its identity-preserving anchor to native geometry.
            if (!feedback.ready) return@collect
            backend.scrollPositions[identity] = LuiScrollPosition(state.firstVisibleItemIndex, state.firstVisibleItemScrollOffset)
            currentRows[feedback.visibleFirst]?.let { anchor = it to state.firstVisibleItemScrollOffset }
            backend.emit(LuiEvent.VirtualWindow(id, feedback.generation, feedback.first.toLong(), feedback.last.toLong(), feedback.pins))
            val visible = feedback.visibleFirst to feedback.visibleLast
            if (currentTrack && visible != previousVisible) {
                previousVisible = visible
                backend.emit(LuiEvent.VisibleRange(id, feedback.visibleFirst.toLong(), (feedback.visibleLast - 1).toLong()))
            }
        }
    }
    val target = node.prop("virtual-scroll-index")?.intValue
    val token = (node.prop("scroll-token") as? LuiWireValue.IntValue)?.value ?: 0
    val request = node.propString("scroll-target")
    val alignment = node.propString("scroll-anchor") ?: "top"
    var lastIntent by remember(id) { mutableStateOf<Pair<String, Long>?>(null) }
    var pending by remember(id) { mutableStateOf<Pair<String, Long>?>(null) }
    fun alignedOffset(index: Int): Int {
        val viewport = state.layoutInfo.viewportSize.height
        val available = (viewport - heights.height(index)).coerceAtLeast(0)
        val desired = when (alignment) { "center" -> available / 2; "bottom" -> available; else -> 0 }
        val maximum = (heights.offset(count) - gapPixels - viewport).coerceAtLeast(0)
        val origin = (heights.offset(index) - desired).coerceIn(0, maximum)
        return (heights.offset(index) - origin).toInt()
    }
    suspend fun alignTarget(index: Int, animated: Boolean) {
        val offset = alignedOffset(index)
        if (animated) state.animateScrollToItem(index, -offset) else state.scrollToItem(index, -offset)
    }
    LaunchedEffect(request, target, token, generation, alignment) {
        val intent = request?.takeIf { it.isNotEmpty() }?.let { it to token }
        if (intent != lastIntent) {
            pending?.let { previous -> backend.emit(LuiEvent.ScrollCompleted(id, previous.second, "cancelled")) }
            lastIntent = intent
            pending = intent
        }
        if (pending == null) return@LaunchedEffect
        if (target == null || target < 0 || target >= count) {
            backend.emit(LuiEvent.ScrollCompleted(id, token, "missing-target"))
            pending = null
        } else alignTarget(target, node.prop("scroll-animated")?.boolValue == true)
    }
    LaunchedEffect(rows, state.layoutInfo, pending) {
        val active = pending
        val item = state.layoutInfo.visibleItemsInfo.firstOrNull { it.index == target }
        if (active != null && target != null && target in rows && item != null) {
            // Materialization can correct the estimated row height before completion.
            if (kotlin.math.abs(item.offset - alignedOffset(target)) > 1) alignTarget(target, false)
            else if (pending == active) {
                backend.emit(LuiEvent.ScrollCompleted(id, active.second, "succeeded"))
                pending = null
            }
        }
    }
    // Row composition belongs to this bounded owner from its first mount. Moving
    // a focused key beyond LazyColumn's nearest-key map only changes placement.
    val scope = rememberCoroutineScope()
    val scrollingEnabled = LocalLuiScrollingEnabled.current
    Box(modifier.clipToBounds().scrollable(state, Orientation.Vertical, enabled = scrollingEnabled).semantics {
        // The real accessible rows belong to this owner. The geometry-only
        // sibling underneath is occluded in Android's platform accessibility tree.
        isTraversalGroup = true
        collectionInfo = CollectionInfo(count, 1)
        fun position() = state.firstVisibleItemIndex +
            state.firstVisibleItemScrollOffset.toFloat() / (heights.height(state.firstVisibleItemIndex).toLong() + gapPixels).coerceAtLeast(1).toFloat()
        verticalScrollAxisRange = ScrollAxisRange(
            value = { position() },
            maxValue = { if (state.canScrollForward) count.toFloat() else position() },
        )
        if (scrollingEnabled) scrollBy { _, y -> scope.launch { state.scrollBy(y) }; true }
        scrollToIndex { index ->
            if (index !in 0 until count) false
            else { scope.launch { state.scrollToItem(index) }; true }
        }
    }) {
        LazyColumn(Modifier.fillMaxSize().clearAndSetSemantics {}, state = state, userScrollEnabled = scrollingEnabled,
            verticalArrangement = Arrangement.spacedBy(gap.dp)) {
            items(count, key = { "slot:$it" }) { index ->
                val native = LocalPinnableContainer.current
                DisposableEffect(index, native) {
                    nativeContainers[index] = native
                    onDispose { if (nativeContainers[index] === native) nativeContainers.remove(index) }
                }
                val height = with(density) { heights.height(index).toDp() }
                Spacer(Modifier.fillMaxWidth().height(height))
            }
        }
        Layout(modifier = Modifier.fillMaxSize(), content = {
            children.forEach { row ->
                key(row) {
                    val container = remember(row) { object : PinnableContainer {
                        override fun pin() = pins.acquire(row, nativeContainers[currentRowIndices[row]])
                    } }
                    CompositionLocalProvider(LocalPinnableContainer provides container, LocalLuiVirtualRowPin provides container) {
                        Box(Modifier.fillMaxWidth().semantics {
                            currentRowIndices[row]?.let { index -> collectionItemInfo = CollectionItemInfo(index, 1, 0, 1) }
                        }.onSizeChanged {
                            if (it.height > 0) {
                                measured[row] = it.height
                                currentRowIndices[row]?.let { index -> heights.update(index, it.height) }
                            }
                        }.pointerInput(container) {
                            awaitEachGesture {
                                awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Initial)
                                val handle = container.pin()
                                try { do { val event = awaitPointerEvent(PointerEventPass.Initial) } while (event.changes.any { it.pressed }) }
                                finally { handle.release() }
                            }
                        }) { LuiNodeView(backend, row) }
                    }
                }
            }
        }) { measurables, constraints ->
            val placeables = measurables.map { it.measure(Constraints(maxWidth = constraints.maxWidth)) }
            layout(constraints.maxWidth, constraints.maxHeight) {
                val layout = state.layoutInfo
                val visibleOffsets = layout.visibleItemsInfo.associate { it.index to it.offset }
                val origin = heights.offset(state.firstVisibleItemIndex) + state.firstVisibleItemScrollOffset
                children.forEachIndexed { slot, row ->
                    val index = rowIndices.getValue(row)
                    val y = visibleOffsets[index] ?: (heights.offset(index) - origin).coerceIn(Int.MIN_VALUE.toLong(), Int.MAX_VALUE.toLong()).toInt()
                    // Placement, rather than conditional composition, preserves native input identity.
                    placeables[slot].placeRelative(0, y)
                }
            }
        }
    }
}

/** Sparse Fenwick corrections keep geometry work logarithmic in logical count. */
private class SparseRowHeights(private val count: Int, private val estimate: Int, private val gap: Int) {
    private val values = mutableMapOf<Int, Int>()
    private val tree = mutableMapOf<Int, Long>()
    private var revision by mutableIntStateOf(0)
    fun height(index: Int): Int { revision; return values[index] ?: estimate }
    fun update(index: Int, height: Int) {
        if (height <= 0) return
        val previous = values[index] ?: estimate
        if (previous == height) return
        values[index] = height
        var cursor = index + 1
        while (cursor <= count && cursor > 0) {
            tree[cursor] = (tree[cursor] ?: 0) + height.toLong() - previous
            cursor += cursor and -cursor
        }
        revision++
    }
    fun offset(index: Int): Long {
        revision
        var correction = 0L
        var cursor = index
        while (cursor > 0) { correction += tree[cursor] ?: 0; cursor -= cursor and -cursor }
        return index.toLong() * (estimate.toLong() + gap) + correction
    }
}
