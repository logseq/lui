package dev.lui

import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.InterceptPlatformTextInput
import androidx.compose.ui.platform.PlatformTextInputInterceptor
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsNode
import androidx.compose.ui.semantics.SemanticsOwner
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.unit.dp
import app.cash.paparazzi.DeviceConfig
import app.cash.paparazzi.Paparazzi
import kotlinx.coroutines.awaitCancellation
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

class LuiSparseVirtualRenderTest {
    @get:Rule val paparazzi = Paparazzi(deviceConfig = DeviceConfig.PIXEL_5.copy(softButtons = false))

    private fun nodes(root: SemanticsNode): List<SemanticsNode> = listOf(root) + root.children.flatMap(::nodes)
    private fun owner(view: android.view.View): SemanticsOwner =
        view.javaClass.methods.first { it.name == "getSemanticsOwner" }.invoke(view) as SemanticsOwner

    private fun source(backend: LuiBackend): LuiNode {
        assertTrue(backend.lastError, backend.applyBatch("""{"generation":1,"ops":[
            {"op":"create-node","id":1,"kind":"virtual-list"},
            {"op":"create-node","id":2,"kind":"text-field"},
            {"op":"set-prop","id":2,"property":"text","value":"Row two"},
            {"op":"set-prop","id":2,"property":"change-enabled","value":true},
            {"op":"create-node","id":3,"kind":"text"},
            {"op":"set-prop","id":3,"property":"text","value":"Last row"},
            {"op":"insert-child","parent":1,"child":2,"index":0},
            {"op":"insert-child","parent":1,"child":3,"index":1}
        ]}"""))
        // Isolate real renderer behavior from metadata schema acceptance.
        return backend.tree.node(1)!!.copy().also {
            it.properties["virtual-total-count"] = LuiWireValue.IntValue(100000)
            it.properties["virtual-generation"] = LuiWireValue.IntValue(1)
            it.properties["virtual-indices"] = LuiWireValue.Str("[2,99999]")
            it.properties["item-extent"] = LuiWireValue.DoubleValue(32.0)
            it.properties["overscan"] = LuiWireValue.IntValue(2)
        }
    }

    @Test fun `hundred thousand logical rows have native full scroll geometry with only two retained rows`() {
        val backend = LuiBackend()
        val node = source(backend)
        var maximum = 0f
        var lastTop = Float.MAX_VALUE
        var jumped = false
        var viewport = ""
        val view = ComposeView(paparazzi.context).apply { setContent {
            val native = LocalView.current
            LuiTheme { Box { LuiVirtualList(backend, node, 1, Modifier.width(300.dp).height(240.dp)) } }
            LaunchedEffect(Unit) {
                repeat(3) { withFrameNanos {} }
                maximum = nodes(owner(native).unmergedRootSemanticsNode).firstNotNullOf {
                    it.config.getOrNull(SemanticsProperties.VerticalScrollAxisRange)
                }.maxValue()
                val list = nodes(owner(native).unmergedRootSemanticsNode).first {
                    it.config.getOrNull(SemanticsActions.ScrollToIndex) != null
                }
                jumped = list.config[SemanticsActions.ScrollToIndex].action!!.invoke(99999)
                repeat(4) { withFrameNanos {} }
                lastTop = nodes(owner(native).unmergedRootSemanticsNode).first {
                    it.config.getOrNull(SemanticsProperties.Text)?.any { text -> text.text == "Last row" } == true
                }.boundsInRoot.top / resources.displayMetrics.density
                viewport = "${list.boundsInRoot}, density=${resources.displayMetrics.density}"
            }
        } }
        paparazzi.luiFrames(view, name = "sparse-full-scroll-height", end = 500, fps = 30)
        assertTrue("100000 logical slots must remain natively scrollable", maximum > 0 && jumped)
        assertTrue("last logical row must actually enter the viewport, top=$lastTop viewport=$viewport", lastTop >= 0 && lastTop < 240)
        assertEquals("logical placeholders must not allocate retained models", 3, backend.tree.nodes.size)
    }

    @Test fun `Android accessibility provider scrolls the actual sparse viewport with supported actions`() {
        val source = Source(rowKind = "list-item")
        var checked = false
        val view = ComposeView(paparazzi.context).apply { setContent {
            val native = LocalView.current
            LuiTheme { Box { source.backend.Content(1) } }
            LaunchedEffect(Unit) {
                repeat(5) { withFrameNanos {} }
                val provider = requireNotNull(native.accessibilityNodeProvider)
                val action = android.view.accessibility.AccessibilityNodeInfo.ACTION_SCROLL_FORWARD
                val ids = nodes(owner(native).unmergedRootSemanticsNode).map { it.id } + -1
                val accessible = ids.mapNotNull { id ->
                    provider.createAccessibilityNodeInfo(id)?.let { id to it }
                }.firstOrNull { (_, info) -> info.actionList.any { it.id == action } }
                assertNotNull("the actual Android provider must expose the sparse viewport's native scroll action", accessible)
                val (virtualId, info) = accessible!!
                assertEquals(100000, info.collectionInfo!!.rowCount)
                assertTrue(provider.performAction(virtualId, action, null))
                repeat(8) { withFrameNanos {} }
                assertTrue("platform scroll changes the actual materialization window", source.windows.last().first > 0)
                val visible = nodes(owner(native).unmergedRootSemanticsNode).first {
                    it.config.getOrNull(SemanticsProperties.Text)?.any { text -> text.text.startsWith("Row ") } == true &&
                        it.boundsInRoot.top >= 0 && it.boundsInRoot.bottom <= 240 * resources.displayMetrics.density
                }
                val visibleIndex = visible.config[SemanticsProperties.Text].first().text.removePrefix("Row ").toInt()
                assertTrue("platform action displays a row from the new window",
                    visibleIndex.toLong() in source.windows.last().first until source.windows.last().last)
                assertTrue("platform scrolling retains a bounded source", source.maximumNodes < 40)
                checked = true
            }
        } }
        paparazzi.luiFrames(view, name = "sparse-platform-accessibility-scroll", end = 900, fps = 30)
        assertTrue(checked)
    }

    @Test fun `focused native editor keeps identity and draft across far source reorder`() {
        val windows = mutableListOf<LuiEvent.VirtualWindow>()
        val backend = LuiBackend(onEvent = { if (it is LuiEvent.VirtualWindow) windows.add(it) })
        var model by mutableStateOf(source(backend))
        var focusedBefore = -1
        var focusedAfter = -2
        var draft = ""
        val view = ComposeView(paparazzi.context).apply { setContent {
            val native = LocalView.current
            LuiTheme { Box { LuiVirtualList(backend, model, 1, Modifier.width(300.dp).height(240.dp)) } }
            LaunchedEffect(Unit) {
                repeat(3) { withFrameNanos {} }
                fun editor() = nodes(owner(native).unmergedRootSemanticsNode).first {
                    it.config.getOrNull(SemanticsProperties.EditableText) != null
                }
                val field = editor()
                assertTrue(field.config[SemanticsActions.RequestFocus].action!!.invoke())
                assertTrue(field.config[SemanticsActions.SetText].action!!.invoke(AnnotatedString("Uncommitted draft")))
                repeat(2) { withFrameNanos {} }
                focusedBefore = editor().id
                model = model.copy().also {
                    it.children.reverse()
                    it.properties["virtual-generation"] = LuiWireValue.IntValue(2)
                }
                repeat(4) { withFrameNanos {} }
                val current = nodes(owner(native).unmergedRootSemanticsNode).firstOrNull {
                    it.config.getOrNull(SemanticsProperties.EditableText) != null &&
                        it.config.getOrNull(SemanticsProperties.Focused) == true
                }
                focusedAfter = current?.id ?: -2
                draft = current?.config?.getOrNull(SemanticsProperties.EditableText)?.text.orEmpty()
            }
        } }
        paparazzi.luiFrames(view, name = "sparse-focused-far-reorder", end = 500, fps = 30)
        assertTrue("native editor was focused before source update", focusedBefore >= 0)
        assertEquals("actual native editor must retain focus and semantics identity", focusedBefore, focusedAfter)
        assertEquals("Uncommitted draft", draft)
        val latest = windows.last { it.generation == 2L }
        assertTrue("reordering a focused row must not force the viewport to follow it", latest.first < 20)
        assertTrue("far focused row must be reported separately from the viewport", 2L in latest.pinnedRows)
    }

    @OptIn(androidx.compose.ui.ExperimentalComposeUiApi::class)
    @Test fun `native composing connection survives far source reorder without restart`() {
        val backend = LuiBackend()
        var model by mutableStateOf(source(backend))
        var connection: android.view.inputmethod.InputConnection? = null
        var sessions = 0
        var cancelled = 0
        var checked = false
        val interceptor = PlatformTextInputInterceptor { request, _ ->
            connection = request.createInputConnection(android.view.inputmethod.EditorInfo())
            sessions++
            try { awaitCancellation() } finally { cancelled++ }
        }
        val view = ComposeView(paparazzi.context).apply { setContent {
            val native = LocalView.current
            InterceptPlatformTextInput(interceptor) {
                LuiTheme { Box { LuiVirtualList(backend, model, 1, Modifier.width(300.dp).height(240.dp)) } }
            }
            LaunchedEffect(Unit) {
                repeat(3) { withFrameNanos {} }
                val field = nodes(owner(native).unmergedRootSemanticsNode).first {
                    it.config.getOrNull(SemanticsProperties.EditableText) != null
                }
                assertTrue(field.config[SemanticsActions.RequestFocus].action!!.invoke())
                repeat(3) { withFrameNanos {} }
                val input = connection
                assertNotNull("real Material editor must establish its input session", input)
                assertTrue(input!!.setComposingText("你", 1))
                repeat(2) { withFrameNanos {} }
                model = model.copy().also { it.children.reverse(); it.properties["virtual-generation"] = LuiWireValue.IntValue(2) }
                repeat(4) { withFrameNanos {} }
                assertSame("the actual input connection must remain active", input, connection)
                assertEquals(1, sessions)
                assertEquals(0, cancelled)
                assertTrue(input.getTextBeforeCursor(100, 0).toString().contains("你"))
                assertTrue(input.finishComposingText())
                assertTrue(input.commitText("好", 1))
                checked = true
            }
        } }
        paparazzi.luiFrames(view, name = "sparse-native-ime-reorder", end = 900, fps = 30)
        assertTrue(checked)
    }

    /** A source driver, not a renderer: only window events allocate row models. */
    private class Source(private val rowKind: String = "text-field", initialCount: Int = 100000,
                         private val rowHeight: Int? = 32) {
        val windows = mutableListOf<LuiEvent.VirtualWindow>()
        val events = mutableListOf<LuiEvent>()
        val backend = LuiBackend(onEvent = { event ->
            events.add(event)
            if (event is LuiEvent.VirtualWindow) {
                windows.add(event)
                if (event.generation == sourceGeneration && !deferMount &&
                    (mountLimit == null || event.last - event.first <= mountLimit!!)) {
                    mount(event.first.toInt(), event.last.toInt(), event.pinnedRows)
                }
            }
        })
        var sourceGeneration = 1L
        var count = initialCount
        var maximumNodes = 0
        var deferMount = false
        var mountLimit: Long? = null
        private var batch = 0
        private var mounted: java.util.SortedSet<Int> = sortedSetOf()
        private fun id(index: Int) = index.toLong() + 100

        init {
            commit(listOf("""{"op":"create-node","id":1,"kind":"virtual-list"}""",
                """{"op":"set-prop","id":1,"property":"height","value":240}""",
                """{"op":"set-prop","id":1,"property":"item-extent","value":32}""",
                """{"op":"set-prop","id":1,"property":"overscan","value":2}""",
                """{"op":"set-prop","id":1,"property":"track-visible-range","value":true}""",
                """{"op":"set-prop","id":1,"property":"scroll-target","value":""}""",
                """{"op":"set-prop","id":1,"property":"scroll-token","value":0}""",
                """{"op":"set-prop","id":1,"property":"virtual-total-count","value":$initialCount}""",
                """{"op":"set-prop","id":1,"property":"virtual-generation","value":1}""",
                """{"op":"set-prop","id":1,"property":"virtual-indices","value":"[]"}"""))
        }

        fun commit(ops: List<String>) {
            assertTrue(backend.lastError, backend.applyBatch("""{"generation":${++batch},"ops":[${ops.joinToString(",")}]}"""))
            maximumNodes = maxOf(maximumNodes, backend.tree.nodes.size)
        }

        fun mount(first: Int, last: Int, pins: List<Long> = emptyList()) {
            val next = ((first.coerceAtLeast(0) until last.coerceAtMost(count)).toSet() +
                pins.map { (it - 100).toInt() }.filter { it in 0 until count }).toSortedSet()
            if (next == mounted) return
            val ops = mutableListOf<String>()
            (mounted - next).forEach { ops.add("""{"op":"detach-subtree","id":${id(it)}}""") }
            (next - mounted).forEach { index ->
                ops.add("""{"op":"create-node","id":${id(index)},"kind":"$rowKind"}""")
                if (rowKind != "column" && rowKind != "stack") ops.add("""{"op":"set-prop","id":${id(index)},"property":"text","value":"Row $index"}""")
                rowHeight?.let { ops.add("""{"op":"set-prop","id":${id(index)},"property":"height","value":$it}""") }
                ops.add("""{"op":"insert-child","parent":1,"child":${id(index)},"index":${next.headSet(index).size}}""")
                if (rowKind == "column" && index == 2) {
                    ops.add("""{"op":"create-node","id":5002,"kind":"popover"}""")
                    ops.add("""{"op":"create-node","id":5003,"kind":"text"}""")
                    ops.add("""{"op":"set-prop","id":5003,"property":"text","value":"Actual portal content"}""")
                    ops.add("""{"op":"insert-child","parent":5002,"child":5003,"index":0}""")
                    ops.add("""{"op":"insert-child","parent":${id(index)},"child":5002,"index":0}""")
                }
            }
            ops.add("""{"op":"set-prop","id":1,"property":"virtual-indices","value":"[${next.joinToString(",")}]"}""")
            commit(ops)
            mounted = next
        }

        fun target(index: Int, token: Long) = commit(listOf(
            """{"op":"set-prop","id":1,"property":"virtual-scroll-index","value":$index}""",
            """{"op":"set-prop","id":1,"property":"scroll-target","value":"row:$index"}""",
            """{"op":"set-prop","id":1,"property":"scroll-token","value":$token}""",
            """{"op":"set-prop","id":1,"property":"scroll-animated","value":false}"""))
    }

    @Test fun `native far jump mounts bounded rows pins focused editor and releases on blur`() {
        val source = Source()
        var checked = false
        val view = ComposeView(paparazzi.context).apply { setContent {
            val native = LocalView.current
            val focus = LocalFocusManager.current
            LuiTheme { Box { source.backend.Content(1) } }
            LaunchedEffect(Unit) {
                suspend fun frames(n: Int = 5) { repeat(n) { withFrameNanos {} } }
                fun fields() = nodes(owner(native).unmergedRootSemanticsNode).filter {
                    it.config.getOrNull(SemanticsProperties.EditableText) != null
                }
                frames()
                val editor = fields().first { it.config[SemanticsProperties.EditableText].text == "Row 2" }
                assertTrue(editor.config[SemanticsActions.RequestFocus].action!!.invoke())
                assertTrue(editor.config[SemanticsActions.SetText].action!!.invoke(AnnotatedString("Draft retained")))
                frames(2)
                source.target(99999, 1)
                frames(8)
                assertTrue("far target must really enter the native viewport: ${fields().map { it.config[SemanticsProperties.EditableText].text to it.boundsInRoot }} windows=${source.windows.takeLast(3)}", fields().any {
                    it.config[SemanticsProperties.EditableText].text == "Row 99999" &&
                        it.boundsInRoot.top < 240 * resources.displayMetrics.density
                })
                val pinned = fields().first { it.id == editor.id }
                assertEquals(true, pinned.config.getOrNull(SemanticsProperties.Focused))
                assertEquals("Draft retained", pinned.config[SemanticsProperties.EditableText].text)
                assertTrue(source.windows.any { 102L in it.pinnedRows && it.first > 99000 })
                assertTrue("source and Compose must remain bounded", source.backend.tree.nodes.size < 40 && fields().size < 40)
                assertTrue(source.events.filterIsInstance<LuiEvent.ScrollCompleted>().any { it.token == 1L && it.outcome == "succeeded" })
                focus.clearFocus(force = true)
                frames()
                assertNull("released offscreen editor must be retired", source.backend.tree.node(102))
                val emitted = source.windows.size
                frames()
                assertEquals("stable layouts must not cause a feedback loop", emitted, source.windows.size)
                checked = true
            }
        } }
        paparazzi.luiFrames(view, name = "sparse-native-far-focus", end = 1500, fps = 30)
        assertTrue("all native interaction checkpoints must run", checked)
    }

    @Test fun `missing replacement scroll token cancels pending target exactly once`() {
        val source = Source()
        var checked = false
        val view = ComposeView(paparazzi.context).apply { setContent {
            LuiTheme { Box { source.backend.Content(1) } }
            LaunchedEffect(Unit) {
                repeat(4) { withFrameNanos {} }
                source.deferMount = true
                source.target(99999, 10)
                repeat(2) { withFrameNanos {} }
                source.target(-1, 11)
                repeat(6) { withFrameNanos {} }
                val outcomes = source.events.filterIsInstance<LuiEvent.ScrollCompleted>()
                assertEquals(listOf("cancelled"), outcomes.filter { it.token == 10L }.map { it.outcome })
                assertEquals(listOf("missing-target"), outcomes.filter { it.token == 11L }.map { it.outcome })
                checked = true
            }
        } }
        paparazzi.luiFrames(view, name = "sparse-native-scroll-tokens", end = 800, fps = 30)
        assertTrue(checked)
    }

    @Test fun `held native pointer pins a nonfocusable row until actual up event`() {
        val source = Source("text")
        var checked = false
        lateinit var view: ComposeView
        view = ComposeView(paparazzi.context).apply { setContent {
            val native = LocalView.current
            LuiTheme { Box { source.backend.Content(1) } }
            LaunchedEffect(Unit) {
                repeat(5) { withFrameNanos {} }
                val row = nodes(owner(native).unmergedRootSemanticsNode).first {
                    it.config.getOrNull(SemanticsProperties.Text)?.any { text -> text.text == "Row 2" } == true
                }
                val x = row.boundsInRoot.center.x
                val y = row.boundsInRoot.center.y
                val time = android.os.SystemClock.uptimeMillis()
                fun pointer(action: Int) {
                    val event = android.view.MotionEvent.obtain(time, time + 1, action, x, y, 0)
                    try { view.dispatchTouchEvent(event) } finally { event.recycle() }
                }
                pointer(android.view.MotionEvent.ACTION_DOWN)
                repeat(2) { withFrameNanos {} }
                source.target(99999, 5)
                repeat(7) { withFrameNanos {} }
                assertNotNull("pressed row must survive scrolling before up", source.backend.tree.node(102))
                assertTrue(source.windows.any { it.first > 99000 && 102L in it.pinnedRows })
                pointer(android.view.MotionEvent.ACTION_UP)
                repeat(5) { withFrameNanos {} }
                assertNull("pointer up must release the offscreen row", source.backend.tree.node(102))
                checked = true
            }
        } }
        paparazzi.luiFrames(view, name = "sparse-native-pointer-retention", end = 1300, fps = 30)
        assertTrue(checked)
    }

    @Test fun `authoritative identical snapshot reissues window and clear reports empty half open range`() {
        val source = Source()
        var checked = false
        val view = ComposeView(paparazzi.context).apply { setContent {
            LuiTheme { Box { source.backend.Content(1) } }
            LaunchedEffect(Unit) {
                repeat(5) { withFrameNanos {} }
                val previous = source.windows.size
                val ops = mutableListOf<LuiPatchOp>()
                source.backend.tree.nodes.forEach { (id, node) ->
                    ops.add(LuiPatchOp.CreateNode(id, node.kind))
                    node.properties.forEach { (name, value) -> ops.add(LuiPatchOp.SetProp(id, name, value)) }
                }
                source.backend.tree.nodes.forEach { (id, node) ->
                    node.children.forEachIndexed { index, child -> ops.add(LuiPatchOp.InsertChild(id, child, index)) }
                }
                assertTrue(source.backend.applySnapshot(LuiPatchBatch(source.backend.tree.generation, ops)))
                repeat(5) { withFrameNanos {} }
                assertTrue("snapshot must resynchronize the runtime window despite identical props", source.windows.size > previous)
                source.count = 0
                source.sourceGeneration = 2
                source.mount(0, 0)
                source.commit(listOf(
                    """{"op":"set-prop","id":1,"property":"virtual-total-count","value":0}""",
                    """{"op":"set-prop","id":1,"property":"virtual-generation","value":2}"""))
                repeat(5) { withFrameNanos {} }
                val empty = source.windows.last()
                assertEquals(2L, empty.generation)
                assertEquals(0L, empty.first)
                assertEquals(0L, empty.last)
                assertTrue(empty.pinnedRows.isEmpty())
                assertEquals(1, source.backend.tree.nodes.size)
                checked = true
            }
        } }
        paparazzi.luiFrames(view, name = "sparse-native-snapshot-clear", end = 1200, fps = 30)
        assertTrue(checked)
    }

    @Test fun `native mounted portal keeps its offscreen owner until dismissal`() {
        val source = Source("column")
        var checked = false
        val view = ComposeView(paparazzi.context).apply { setContent {
            LuiTheme { Box { source.backend.Content(1) } }
            LaunchedEffect(Unit) {
                repeat(5) { withFrameNanos {} }
                assertNotNull(source.backend.tree.node(5002))
                source.target(99999, 20)
                repeat(8) { withFrameNanos {} }
                assertNotNull("actual open popup must retain its logical owner", source.backend.tree.node(102))
                assertTrue(source.windows.any { it.first > 99000 && 102L in it.pinnedRows })
                source.commit(listOf("""{"op":"detach-subtree","id":5002}"""))
                repeat(6) { withFrameNanos {} }
                assertNull("dismissing the last owned popup must release its offscreen owner", source.backend.tree.node(102))
                checked = true
            }
        } }
        paparazzi.luiFrames(view, name = "sparse-native-portal-retention", end = 1300, fps = 30)
        assertTrue(checked)
    }

    @Test fun `empty target has no intent and completed token does not replay on source refresh`() {
        val source = Source()
        var checked = false
        val view = ComposeView(paparazzi.context).apply { setContent {
            LuiTheme { Box { source.backend.Content(1) } }
            LaunchedEffect(Unit) {
                repeat(5) { withFrameNanos {} }
                assertTrue("empty initial target must not report missing token zero", source.events.none { it is LuiEvent.ScrollCompleted })
                source.target(50000, 30)
                repeat(7) { withFrameNanos {} }
                source.sourceGeneration = 2
                source.commit(listOf("""{"op":"set-prop","id":1,"property":"virtual-generation","value":2}"""))
                repeat(7) { withFrameNanos {} }
                assertEquals(listOf("succeeded"), source.events.filterIsInstance<LuiEvent.ScrollCompleted>().filter { it.token == 30L }.map { it.outcome })
                checked = true
            }
        } }
        paparazzi.luiFrames(view, name = "sparse-native-intent-once", end = 1100, fps = 30)
        assertTrue(checked)
    }

    @Test fun `portable anchors align the actual far row at top center and bottom`() {
        val source = Source()
        var checked = false
        val positions = mutableListOf<Float>()
        val view = ComposeView(paparazzi.context).apply { setContent {
            val native = LocalView.current
            val density = androidx.compose.ui.platform.LocalDensity.current.density
            LuiTheme { Box { source.backend.Content(1) } }
            LaunchedEffect(Unit) {
                repeat(5) { withFrameNanos {} }
                for ((index, anchor) in listOf("top", "center", "bottom").withIndex()) {
                    source.commit(listOf("""{"op":"set-prop","id":1,"property":"scroll-anchor","value":"$anchor"}"""))
                    source.target(50000, 40L + index)
                    repeat(8) { withFrameNanos {} }
                    val field = nodes(owner(native).unmergedRootSemanticsNode).first {
                        it.config.getOrNull(SemanticsProperties.EditableText)?.text == "Row 50000"
                    }
                    positions.add(field.boundsInRoot.top / density)
                }
                checked = true
            }
        } }
        paparazzi.luiFrames(view, name = "sparse-native-anchor-alignment", end = 1600, fps = 30)
        assertTrue(checked)
        assertEquals(0f, positions[0], 1f)
        assertEquals(104f, positions[1], 1f)
        assertEquals(208f, positions[2], 1f)
    }

    @Test fun `successful request token is consumed across later source generation`() {
        val source = Source()
        source.target(50000, 31)
        var checked = false
        val view = ComposeView(paparazzi.context).apply { setContent {
            LuiTheme { Box { source.backend.Content(1) } }
            LaunchedEffect(Unit) {
                repeat(8) { withFrameNanos {} }
                assertEquals(1, source.events.filterIsInstance<LuiEvent.ScrollCompleted>().count { it.token == 31L })
                source.sourceGeneration = 2
                source.commit(listOf("""{"op":"set-prop","id":1,"property":"virtual-generation","value":2}"""))
                repeat(8) { withFrameNanos {} }
                assertEquals("source refresh must not replay a consumed scroll intent", 1,
                    source.events.filterIsInstance<LuiEvent.ScrollCompleted>().count { it.token == 31L })
                checked = true
            }
        } }
        paparazzi.luiFrames(view, name = "sparse-native-consumed-token", end = 1000, fps = 30)
        assertTrue(checked)
    }

    @Test fun `positive fractional estimates still yield bounded native compositions`() {
        val source = Source("text", 2000)
        source.commit(listOf("""{"op":"set-prop","id":1,"property":"item-extent","value":0.01}"""))
        val view = ComposeView(paparazzi.context).apply { setContent { LuiTheme { Box { source.backend.Content(1) } } } }
        paparazzi.luiFrames(view, name = "sparse-native-fractional-estimate", end = 500, fps = 30)
        assertTrue("positive estimate cannot create every native zero-height slot, peak=${source.maximumNodes}", source.maximumNodes < 1000)
    }

    @Test fun `authored gaps affect actual row placement and overscan stays clipped to viewport`() {
        val source = Source()
        source.commit(listOf("""{"op":"set-prop","id":1,"property":"gap","value":7}"""))
        var spacing = 0f
        var clipped = false
        var checked = false
        val view = ComposeView(paparazzi.context).apply { setContent {
            val native = LocalView.current
            val density = androidx.compose.ui.platform.LocalDensity.current.density
            LuiTheme { Box { source.backend.Content(1) } }
            LaunchedEffect(Unit) {
                repeat(5) { withFrameNanos {} }
                fun fields() = nodes(owner(native).unmergedRootSemanticsNode).filter {
                    it.config.getOrNull(SemanticsProperties.EditableText) != null
                }
                val first = fields().first { it.config[SemanticsProperties.EditableText].text == "Row 0" }
                val second = fields().first { it.config[SemanticsProperties.EditableText].text == "Row 1" }
                spacing = (second.boundsInRoot.top - first.boundsInRoot.top) / density
                source.target(50000, 50)
                repeat(8) { withFrameNanos {} }
                clipped = fields().all {
                    val bounds = it.boundsInRoot
                    bounds.isEmpty || (bounds.top >= 0 && bounds.bottom <= 240 * density)
                }
                checked = true
            }
        } }
        paparazzi.luiFrames(view, name = "sparse-native-gap-clip", end = 1000, fps = 30)
        assertTrue(checked)
        assertEquals(39f, spacing, 1f)
        assertTrue("overscan and pinned controls must not draw or receive input outside the scroll viewport", clipped)
    }

    @Test fun `largest accepted overscan clamps the real window without integer overflow`() {
        val source = Source("text", 1000)
        source.deferMount = true
        source.commit(listOf("""{"op":"set-prop","id":1,"property":"overscan","value":2147483647}"""))
        val view = ComposeView(paparazzi.context).apply { setContent { LuiTheme { Box { source.backend.Content(1) } } } }
        paparazzi.luiFrames(view, name = "sparse-native-max-overscan", end = 300, fps = 30)
        assertTrue(source.windows.isNotEmpty())
        assertTrue("every layout must clamp the half-open window before narrowing", source.windows.all { it.first == 0L && it.last == 1000L })
    }

    @Test fun `large logical offsets cannot place far pinned editor over the viewport`() {
        val source = Source()
        source.commit(listOf("""{"op":"set-prop","id":1,"property":"item-extent","value":32000}"""))
        source.target(90000, 60)
        var checked = false
        val view = ComposeView(paparazzi.context).apply { setContent {
            val native = LocalView.current
            LuiTheme { Box { source.backend.Content(1) } }
            LaunchedEffect(Unit) {
                repeat(8) { withFrameNanos {} }
                fun fields() = nodes(owner(native).unmergedRootSemanticsNode).filter {
                    it.config.getOrNull(SemanticsProperties.EditableText) != null
                }
                val editor = fields().first { it.config[SemanticsProperties.EditableText].text == "Row 90000" }
                assertTrue(editor.config[SemanticsActions.RequestFocus].action!!.invoke())
                repeat(2) { withFrameNanos {} }
                source.target(95000, 61)
                repeat(8) { withFrameNanos {} }
                val retained = fields().first { it.id == editor.id }
                assertEquals(true, retained.config.getOrNull(SemanticsProperties.Focused))
                assertTrue("offscreen pin must not collapse to y0 after absolute offsets exceed Int", retained.boundsInRoot.isEmpty)
                checked = true
            }
        } }
        paparazzi.luiFrames(view, name = "sparse-native-long-offset-pin", end = 1300, fps = 30)
        assertTrue(checked)
    }

    @Test fun `native scroll position survives destination leaving and reentering composition`() {
        val source = Source()
        var shown by mutableStateOf(true)
        var checked = false
        val view = ComposeView(paparazzi.context).apply { setContent {
            LuiTheme { Box { if (shown) source.backend.Content(1) } }
            LaunchedEffect(Unit) {
                repeat(5) { withFrameNanos {} }
                source.target(50000, 70)
                repeat(7) { withFrameNanos {} }
                source.commit(listOf("""{"op":"set-prop","id":1,"property":"scroll-target","value":""}"""))
                repeat(2) { withFrameNanos {} }
                shown = false
                repeat(3) { withFrameNanos {} }
                shown = true
                repeat(7) { withFrameNanos {} }
                assertTrue("returning to a retained destination must keep its native viewport", source.windows.last().first > 49000)
                checked = true
            }
        } }
        paparazzi.luiFrames(view, name = "sparse-native-navigation-scroll", end = 1500, fps = 30)
        assertTrue(checked)
    }

    @Test fun `source insertion preserves the actual visible row and pixel offset`() {
        val source = Source()
        var checked = false
        var before = Float.NaN
        var after = Float.NaN
        val view = ComposeView(paparazzi.context).apply { setContent {
            val native = LocalView.current
            val density = androidx.compose.ui.platform.LocalDensity.current.density
            LuiTheme { Box { source.backend.Content(1) } }
            LaunchedEffect(Unit) {
                repeat(5) { withFrameNanos {} }
                source.target(50000, 80)
                repeat(8) { withFrameNanos {} }
                fun marker() = nodes(owner(native).unmergedRootSemanticsNode).first {
                    it.config.getOrNull(SemanticsProperties.EditableText)?.text == "Row 50000"
                }
                before = marker().boundsInRoot.top / density
                source.deferMount = true
                source.sourceGeneration = 2
                val previous = luiVirtualIndices(source.backend.tree.node(1)!!.properties["virtual-indices"]!!.stringValue!!)!!
                source.commit(listOf(
                    """{"op":"set-prop","id":1,"property":"virtual-total-count","value":100001}""",
                    """{"op":"set-prop","id":1,"property":"virtual-generation","value":2}""",
                    """{"op":"set-prop","id":1,"property":"virtual-indices","value":"[${previous.joinToString(",") { (it + 1).toString() }}]"}""",
                    """{"op":"set-prop","id":1,"property":"virtual-scroll-index","value":50001}"""))
                repeat(8) { withFrameNanos {} }
                after = marker().boundsInRoot.top / density
                checked = true
            }
        } }
        paparazzi.luiFrames(view, name = "sparse-native-visible-anchor-insertion", end = 1300, fps = 30)
        assertTrue(checked)
        assertEquals("source changes preserve the viewport anchor by row identity", before, after, 1f)
    }

    @Test fun `hundred thousand blank row roots keep positive estimated geometry and bounded materialization`() {
        val source = Source("stack", 100000, rowHeight = null)
        // Refuse an invalid oversized request so a regression cannot exhaust the
        // test JVM; the unmodified requested window remains the assertion oracle.
        source.mountLimit = 100
        val view = ComposeView(paparazzi.context).apply { setContent { LuiTheme { Box { source.backend.Content(1) } } } }
        paparazzi.luiFrames(view, name = "sparse-native-blank-roots", end = 700, fps = 30)
        assertTrue(source.windows.isNotEmpty())
        assertTrue("unmeasured blank roots must not expand the window to the complete source: ${source.windows.last()}",
            source.windows.all { it.last - it.first <= 100 })
        assertTrue("idle blank content must not continuously scan forward through the source: ${source.windows.last()}",
            source.windows.last().first == 0L && source.windows.last().last <= 20)
        assertTrue(source.maximumNodes < 110)
    }
}
