package dev.lui.drive

import android.app.Activity
import android.app.Instrumentation
import android.content.ComponentName
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.graphics.Bitmap
import android.graphics.Rect
import android.graphics.RectF
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import android.util.Base64
import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.ViewConfiguration
import android.view.accessibility.AccessibilityNodeInfo
import android.view.accessibility.AccessibilityWindowInfo
import dev.lui.LuiInspection
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.longOrNull
import kotlinx.serialization.json.put
import java.io.ByteArrayOutputStream
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.net.SocketTimeoutException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/** Self-instrumenting debug runner. Starts only with the explicit drive=true argument. */
class DriveInstrumentation : Instrumentation() {
    private lateinit var arguments: Bundle
    private val main = Handler(Looper.getMainLooper())
    private var deadline = Long.MAX_VALUE
    private var lastRequest = 0L
    private var published = emptyMap<Long, Long>()
    private var lastSnapshot = ""
    private var generation = 0
    private lateinit var target: DriveTarget
    private lateinit var socket: Socket
    private val transportWatchdog = Executors.newSingleThreadScheduledExecutor()

    override fun onCreate(arguments: Bundle?) {
        this.arguments = arguments ?: Bundle()
        start()
    }

    override fun onStart() {
        var activity: Activity? = null
        var server: ServerSocket? = null
        var failure: String? = null
        try {
            check(arguments.getString("drive") == "true") { "explicit -e drive true is required" }
            check(Build.VERSION.SDK_INT >= 30) { "Drive native host requires Android API 30+" }
            check(targetContext.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0) { "Drive requires a debug application" }
            val port = arguments.getString("port", "49377").toInt()
            require(port in 1024..65535) { "invalid loopback port" }
            val component = ComponentName.unflattenFromString(checkNotNull(arguments.getString("activity")) { "-e activity package/.Activity is required" })
            check(component?.packageName == targetContext.packageName) { "activity must belong to instrumentation target" }
            activity = startActivitySync(Intent().setComponent(component)
                .putExtra("luiDrive", true)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK))
            target = ui { checkNotNull(DriveTarget.current) { "Activity did not register DriveTarget" } }
            uiAutomation.serviceInfo = uiAutomation.serviceInfo.apply {
                flags = flags or android.accessibilityservice.AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS or
                    android.accessibilityservice.AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS
            }
            server = ServerSocket(port, 1, InetAddress.getByName("127.0.0.1")).apply { soTimeout = 120_000 }
            sendStatus(0, Bundle().apply { putString("drive", "listening on 127.0.0.1:$port") })
            socket = server.accept().apply { soTimeout = 100; tcpNoDelay = true }
            server.close()
            deadline = SystemClock.uptimeMillis() + 3_000
            settle()
            check(ui { target.inspection.screenFrames().values.any { it.width() > 0 && it.height() > 0 } }) { "attach has no node geometry" }
            val capabilities = DriveAction.capabilities.filter { it != "type" || selectedIme() }
            send(buildJsonObject {
                put("drive", "hello"); put("version", 1)
                put("capabilities", JsonArray(capabilities.map { JsonPrimitive(it) }))
            })
            publish(force = true, initial = true)
            deadline = Long.MAX_VALUE
            serve()
        } catch (error: Exception) {
            failure = error.message ?: error.javaClass.simpleName
        } finally {
            if (::socket.isInitialized) socket.close()
            transportWatchdog.shutdownNow()
            server?.close()
            deadline = SystemClock.uptimeMillis() + 1_000
            runCatching { ui { DriveTarget.current?.close(); activity?.finish() } }
            finish(if (failure == null) Activity.RESULT_OK else Activity.RESULT_CANCELED,
                Bundle().apply { putString("drive", failure ?: "closed") })
        }
    }

    private fun selectedIme(): Boolean = ComponentName.unflattenFromString(
        Settings.Secure.getString(targetContext.contentResolver, Settings.Secure.DEFAULT_INPUT_METHOD) ?: ""
    ) == ComponentName(targetContext, DriveInputMethod::class.java)

    private fun serve() {
        val pending = ByteArrayOutputStream()
        val input = socket.getInputStream()
        var activityAt = SystemClock.uptimeMillis()
        while (true) {
            val byte = try { input.read() } catch (_: SocketTimeoutException) {
                check(SystemClock.uptimeMillis() - activityAt < 120_000) { "Drive connection idle timeout" }
                publish(force = false)
                continue
            }
            if (byte == -1) {
                check(pending.size() == 0) { "Drive disconnected with an incomplete action line" }
                return
            }
            activityAt = SystemClock.uptimeMillis()
            if (byte == 10) {
                val line = pending.toString(Charsets.UTF_8.name())
                pending.reset()
                handle(line)
            } else {
                check(pending.size() < 1_048_576) { "Drive action line exceeds 1 MiB" }
                pending.write(byte)
            }
        }
    }

    private fun handle(line: String) {
        val request = runCatching { (Json.parseToJsonElement(line) as JsonObject)["request"] as? JsonPrimitive }
            .getOrNull()?.takeUnless { it.isString }?.longOrNull
        if (request == null || request <= 0) error("missing positive Drive request; closing")
        deadline = SystemClock.uptimeMillis() + 3_000
        var png: String? = null
        var failure: String? = null
        try {
            val action = DriveAction.parse(line)
            require(action.request > lastRequest) { "Drive request is stale or duplicated" }
            lastRequest = action.request
            execute(action)
            settle()
            if (action.name == "screenshot") png = screenshot()
        } catch (error: Exception) {
            failure = if (error is java.util.concurrent.TimeoutException) "native action timeout waiting for accessibility idle"
                else error.message ?: error.javaClass.simpleName
        }
        // A failed action still publishes the authoritative post-input state before its result.
        deadline = SystemClock.uptimeMillis() + 500
        try { publish(force = true) } catch (error: Exception) {
            failure = failure ?: error.message ?: "snapshot publication failed"
        }
        send(buildJsonObject {
            put("drive", "result"); put("version", 1); put("request", request)
            put("ok", failure == null)
            if (failure != null) put("error", failure)
            if (failure == null && png != null) put("png", png)
        })
        if (failure?.contains("timeout") == true) error("native request timeout; closing")
        deadline = Long.MAX_VALUE
    }

    private fun execute(action: DriveAction) {
        when (action.name) {
            "settle", "screenshot" -> Unit
            "key" -> key(action.string("combo"))
            "tap" -> {
                val viewport = ui { viewport() }
                val density = targetContext.resources.displayMetrics.density
                val x = viewport.left + action.number("x") * density
                val y = viewport.top + action.number("y") * density
                check(viewport.contains(x, y)) { "tap is outside the viewport" }
                val id = hit(x, y)
                validate(id, x, y)
                gesture(x, y, x, y, 60)
            }
            else -> {
                if (action.name == "type") {
                    check(selectedIme()) { "type requires the explicitly selected Drive test IME" }
                    ui {
                        val node = checkNotNull(target.inspection.snapshot().firstOrNull { it.id == action.id() }) { "stale text target" }
                        check(node.kind in setOf("text-field", "secure-field", "input", "search-field", "textarea", "combobox")) {
                            "type requires a supported native text editor"
                        }
                        check(node.properties["read-only"]?.boolValue != true) { "target editor is read-only" }
                    }
                }
                val frame = validate(action.id())
                val x = frame.centerX(); val y = frame.centerY()
                when (action.name) {
                    "click" -> gesture(x, y, x, y, 60)
                    "double-click" -> {
                        gesture(x, y, x, y, 40)
                        pause(50)
                        validate(action.id(), x, y)
                        gesture(x, y, x, y, 40)
                    }
                    "long-click" -> gesture(x, y, x, y, ViewConfiguration.getLongPressTimeout().toLong() + 100)
                    "drag" -> {
                        val end = validate(action.id("target"))
                        gesture(x, y, end.centerX(), end.centerY(), 400)
                    }
                    "scroll" -> {
                        val scale = targetContext.resources.displayMetrics.density
                        val dx = action.number("dx") * scale; val dy = action.number("dy") * scale
                        check(dx != 0f || dy != 0f) { "scroll delta must be nonzero" }
                        val startX = x + dx / 2; val startY = y + dy / 2
                        val endX = x - dx / 2; val endY = y - dy / 2
                        check(frame.contains(startX, startY) && frame.contains(endX, endY)) { "scroll gesture exceeds visible target; use smaller deltas" }
                        validate(action.id(), startX, startY)
                        gesture(startX, startY, endX, endY, 300)
                    }
                    "type" -> type(action.id(), action.string("text"), x, y)
                }
            }
        }
    }

    private fun type(id: Long, text: String, x: Float, y: Float) {
        val before = ui { DriveInputMethod.active?.session }
        val wasFocused = focusedId() == id
        gesture(x, y, x, y, 60)
        while (true) {
            checkTime()
            val ready = ui {
                DriveInputMethod.active?.let { ime ->
                    ime.editor?.packageName == targetContext.packageName && (wasFocused || ime.session != before)
                } == true
            }
            if (focusedId() == id && ready) break
            pause(20)
        }
        validate(id)
        val (ime, session, connection) = ui {
            val ime = checkNotNull(DriveInputMethod.active) { "test IME is not running" }
            Triple(ime, ime.session, ime.connection(targetContext.packageName))
        }
        DriveInputMethod.replace(connection, text) {
            checkTime()
            check(focusedId() == id && selectedIme()) { "native editor focus changed before replacement" }
            ui { check(DriveInputMethod.active === ime && ime.session == session) { "native InputConnection was replaced" } }
        }
    }

    private fun focusedId(): Long? {
        val root = uiAutomation.rootInActiveWindow ?: return null
        val focused = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT) ?: return null
        if (!focused.isEditable) return null
        var node: AccessibilityNodeInfo? = focused
        while (node != null) {
            tagId(node)?.let { return it }
            node = node.parent
        }
        return null
    }

    private fun validate(id: Long, atX: Float? = null, atY: Float? = null): RectF {
        val frame = ui {
            check(DriveTarget.current === target && !target.activity.isFinishing && target.viewport.isShown) { "target was detached" }
            val nodes = target.inspection.snapshot().associateBy { it.id }
            val node = checkNotNull(nodes[id]) { "stale node $id" }
            check(published[id] == node.incarnation) { "stale incarnation for node $id" }
            val parents = nodes.values.flatMap { n -> n.children.map { it to n.id } }.toMap()
            var current: LuiInspection.Node? = node
            while (current != null) {
                check(current.properties["enabled"]?.boolValue != false) { "disabled target $id" }
                check(current.properties["display"]?.stringValue != "none" &&
                    current.properties["visibility"]?.stringValue != "hidden" &&
                    (current.properties["opacity"]?.numberValue ?: 1.0) > 0.0) { "hidden target $id" }
                current = parents[current.id]?.let { nodes[it] }
            }
            val bounds = checkNotNull(target.inspection.screenFrames()[id]) { "node $id has no attached geometry" }
            check(bounds.intersect(viewport()) && bounds.width() > 0 && bounds.height() > 0) { "node $id is hidden or outside viewport" }
            bounds
        }
        val x = atX ?: frame.centerX(); val y = atY ?: frame.centerY()
        check(frame.contains(x, y)) { "point is outside node $id" }
        val hitId = hit(x, y)
        val descendant = ui {
            val nodes = target.inspection.snapshot().associateBy { it.id }
            val parents = nodes.values.flatMap { n -> n.children.map { it to n.id } }.toMap()
            var candidate: Long? = hitId
            while (candidate != null && candidate != id) candidate = parents[candidate]
            candidate == id
        }
        check(descendant) { "node $id is occluded or has no native accessibility hit target" }
        return frame
    }

    private fun tagId(node: AccessibilityNodeInfo): Long? = node.viewIdResourceName?.removePrefix("lui-drive-")?.toLongOrNull()

    /** Read-only platform window/hit inspection. No accessibility action is ever invoked. */
    private fun hit(x: Float, y: Float): Long {
        val windows = uiAutomation.windows.sortedByDescending { it.layer }
        for (window in windows) {
            val bounds = Rect(); window.getBoundsInScreen(bounds)
            if (!bounds.contains(x.toInt(), y.toInt())) continue
            val root = window.root ?: error("occluding window has no readable native root")
            check(root.packageName?.toString() == targetContext.packageName && window.type == AccessibilityWindowInfo.TYPE_APPLICATION) { "target is occluded by another native window" }
            fun descend(node: AccessibilityNodeInfo, inherited: Long?): Long? {
                val rect = Rect(); node.getBoundsInScreen(rect)
                if (!node.isVisibleToUser || !rect.contains(x.toInt(), y.toInt())) return null
                check(node.isEnabled) { "native hit target is disabled" }
                val own = tagId(node) ?: inherited
                val children = (0 until node.childCount).mapNotNull { index -> node.getChild(index)?.let { index to it } }
                    .sortedWith(compareByDescending<Pair<Int, AccessibilityNodeInfo>> { it.second.drawingOrder }.thenByDescending { it.first })
                for ((_, child) in children) {
                    val childBounds = Rect(); child.getBoundsInScreen(childBounds)
                    if (child.isVisibleToUser && childBounds.contains(x.toInt(), y.toInt())) return descend(child, own)
                }
                return own
            }
            return checkNotNull(descend(root, null)) { "native hit is untagged or occluded" }
        }
        error("no native application window at input point")
    }

    private fun gesture(x: Float, y: Float, endX: Float, endY: Float, duration: Long) {
        val downTime = SystemClock.uptimeMillis()
        var down = false
        fun inject(action: Int, atX: Float, atY: Float) {
            val event = MotionEvent.obtain(downTime, SystemClock.uptimeMillis(), action, atX, atY, 0)
            event.source = InputDevice.SOURCE_TOUCHSCREEN
            try { check(uiAutomation.injectInputEvent(event, true)) { "native MotionEvent injection was rejected" } }
            finally { event.recycle() }
        }
        try {
            down = true
            inject(MotionEvent.ACTION_DOWN, x, y)
            val steps = (duration / 16).toInt().coerceAtLeast(1)
            for (step in 1..steps) {
                pause(duration / steps)
                val t = step.toFloat() / steps
                if (x != endX || y != endY) inject(MotionEvent.ACTION_MOVE, x + (endX - x) * t, y + (endY - y) * t)
            }
            inject(MotionEvent.ACTION_UP, endX, endY)
            down = false
        } finally {
            if (down) runCatching { inject(MotionEvent.ACTION_CANCEL, endX, endY) }
        }
    }

    private fun key(combo: String) {
        check(uiAutomation.rootInActiveWindow?.packageName?.toString() == targetContext.packageName) { "target window is not active" }
        val tokens = combo.lowercase().split('+')
        require(tokens.none { it.isEmpty() } && tokens.distinct().size == tokens.size) { "invalid key combo" }
        val modifierCodes = mapOf("ctrl" to KeyEvent.KEYCODE_CTRL_LEFT, "mod" to KeyEvent.KEYCODE_CTRL_LEFT,
            "shift" to KeyEvent.KEYCODE_SHIFT_LEFT, "alt" to KeyEvent.KEYCODE_ALT_LEFT, "meta" to KeyEvent.KEYCODE_META_LEFT,
            "cmd" to KeyEvent.KEYCODE_META_LEFT)
        val metaFlags = mapOf(KeyEvent.KEYCODE_CTRL_LEFT to KeyEvent.META_CTRL_ON, KeyEvent.KEYCODE_SHIFT_LEFT to KeyEvent.META_SHIFT_ON,
            KeyEvent.KEYCODE_ALT_LEFT to KeyEvent.META_ALT_ON, KeyEvent.KEYCODE_META_LEFT to KeyEvent.META_META_ON)
        val modifiers = tokens.dropLast(1).map { checkNotNull(modifierCodes[it]) { "unsupported key modifier: $it" } }
        require(modifiers.distinct().size == modifiers.size) { "duplicate native key modifier" }
        val name = tokens.last()
        val code = when {
            name.length == 1 && name[0] in 'a'..'z' -> KeyEvent.KEYCODE_A + (name[0] - 'a')
            name.length == 1 && name[0] in '0'..'9' -> KeyEvent.KEYCODE_0 + (name[0] - '0')
            else -> mapOf("enter" to KeyEvent.KEYCODE_ENTER, "tab" to KeyEvent.KEYCODE_TAB, "escape" to KeyEvent.KEYCODE_ESCAPE,
                "backspace" to KeyEvent.KEYCODE_DEL, "delete" to KeyEvent.KEYCODE_FORWARD_DEL, "space" to KeyEvent.KEYCODE_SPACE,
                "arrowleft" to KeyEvent.KEYCODE_DPAD_LEFT, "arrowright" to KeyEvent.KEYCODE_DPAD_RIGHT,
                "arrowup" to KeyEvent.KEYCODE_DPAD_UP, "arrowdown" to KeyEvent.KEYCODE_DPAD_DOWN,
                "home" to KeyEvent.KEYCODE_MOVE_HOME, "end" to KeyEvent.KEYCODE_MOVE_END,
                "pageup" to KeyEvent.KEYCODE_PAGE_UP, "pagedown" to KeyEvent.KEYCODE_PAGE_DOWN)[name]
                ?: error("unsupported native key: $name; use type for Unicode")
        }
        val held = mutableListOf<Int>()
        var meta = 0
        val time = SystemClock.uptimeMillis()
        fun inject(key: Int, action: Int) {
            check(uiAutomation.injectInputEvent(KeyEvent(time, SystemClock.uptimeMillis(), action, key, 0, meta,
                -1, 0, 0, InputDevice.SOURCE_KEYBOARD), true)) { "native KeyEvent injection rejected" }
        }
        try {
            modifiers.forEach { modifier -> meta = meta or metaFlags.getValue(modifier); held += modifier; inject(modifier, KeyEvent.ACTION_DOWN) }
            held += code
            inject(code, KeyEvent.ACTION_DOWN)
        } finally {
            held.asReversed().forEach { key -> runCatching { inject(key, KeyEvent.ACTION_UP) }; meta = meta and (metaFlags[key] ?: 0).inv() }
        }
    }

    private fun settle() {
        var previous = ""
        var quietSince = SystemClock.uptimeMillis()
        while (true) {
            checkTime()
            val state = ui { target.inspection.snapshot().toString() + target.inspection.screenFrames().toString() + target.draws }
            val now = SystemClock.uptimeMillis()
            if (state != previous) { previous = state; quietSince = now }
            if (now - quietSince >= 100) {
                uiAutomation.waitForIdle(100, (deadline - now).coerceAtMost(300).coerceAtLeast(1))
                if (ui { target.inspection.snapshot().toString() + target.inspection.screenFrames().toString() + target.draws } == state) return
                quietSince = SystemClock.uptimeMillis()
            }
            pause(16)
        }
    }

    private fun viewport(): RectF {
        val origin = IntArray(2); target.viewport.getLocationOnScreen(origin)
        check(target.viewport.width > 0 && target.viewport.height > 0) { "empty target viewport" }
        return RectF(origin[0].toFloat(), origin[1].toFloat(), (origin[0] + target.viewport.width).toFloat(), (origin[1] + target.viewport.height).toFloat())
    }

    private fun screenshot(): String {
        check(ui { target.activity.window.attributes.flags and android.view.WindowManager.LayoutParams.FLAG_SECURE == 0 }) {
            "native screenshot is unsupported for a secure window"
        }
        val crop = ui { viewport() }
        val bitmap = checkNotNull(uiAutomation.takeScreenshot()) { "native screenshot unavailable (secure window?)" }
        try {
            check(crop.left >= 0 && crop.top >= 0 && crop.right <= bitmap.width && crop.bottom <= bitmap.height) { "viewport is outside screenshot" }
            val clipped = Bitmap.createBitmap(bitmap, crop.left.toInt(), crop.top.toInt(), crop.width().toInt(), crop.height().toInt())
            try {
                val bytes = ByteArrayOutputStream()
                check(clipped.compress(Bitmap.CompressFormat.PNG, 100, bytes)) { "PNG encoding failed" }
                return Base64.encodeToString(bytes.toByteArray(), Base64.NO_WRAP)
            } finally { if (clipped !== bitmap) clipped.recycle() }
        } finally { bitmap.recycle() }
    }

    private fun publish(force: Boolean, initial: Boolean = false) {
        val (nodes, frames, viewport) = ui { Triple(target.inspection.snapshot(), target.inspection.screenFrames(), viewport()) }
        val state = nodes.toString() + frames.toString() + viewport
        if (!force && state == lastSnapshot) return
        val scale = targetContext.resources.displayMetrics.density
        val ops = buildJsonObject {
            put("generation", ++generation)
            put("ops", buildJsonArray {
                published.keys.forEach { id -> add(buildJsonObject { put("op", "drop-node"); put("id", id) }) }
                nodes.forEach { node ->
                    add(buildJsonObject {
                        put("op", if (node.kind.startsWith("extension:")) "create-extension" else "create-node"); put("id", node.id)
                        put(if (node.kind.startsWith("extension:")) "identifier" else "kind", node.kind.removePrefix("extension:"))
                    })
                    node.properties.forEach { (name, value) -> add(buildJsonObject {
                        put("op", "set-prop"); put("id", node.id); put("property", name)
                        put("value", Json.parseToJsonElement(value.toJsonLiteral()))
                    }) }
                }
                nodes.forEach { node -> node.children.forEachIndexed { index, child -> add(buildJsonObject {
                    put("op", "insert-child"); put("parent", node.id); put("child", child); put("index", index)
                }) } }
            })
        }
        val geometry = buildJsonObject { put("frames", buildJsonArray {
            nodes.forEach { node -> frames[node.id]?.let { original ->
                val frame = RectF(original)
                if (frame.intersect(viewport) && frame.width() > 0 && frame.height() > 0) add(buildJsonArray {
                    add(JsonPrimitive(node.id)); add(JsonPrimitive((frame.left - viewport.left) / scale))
                    add(JsonPrimitive((frame.top - viewport.top) / scale)); add(JsonPrimitive(frame.width() / scale)); add(JsonPrimitive(frame.height() / scale))
                })
            } }
        }) }
        if (initial) { send(geometry); send(ops) } else { send(ops); send(geometry) }
        published = nodes.associate { it.id to it.incarnation }
        lastSnapshot = state
    }

    private fun send(json: JsonObject) {
        val timeout = (deadline - SystemClock.uptimeMillis()).coerceIn(1, 1_000)
        val watchdog = transportWatchdog.schedule({ runCatching { socket.close() } }, timeout, TimeUnit.MILLISECONDS)
        try {
            socket.getOutputStream().write((json.toString() + "\n").toByteArray(Charsets.UTF_8))
            socket.getOutputStream().flush()
        } finally { watchdog.cancel(false) }
    }

    private fun checkTime() { check(SystemClock.uptimeMillis() < deadline) { "native action timeout" } }
    private fun pause(ms: Long) { checkTime(); SystemClock.sleep(ms); checkTime() }

    private fun <T> ui(block: () -> T): T {
        check(Looper.myLooper() != Looper.getMainLooper()) { "Drive worker must not run on UI thread" }
        val cancelled = AtomicBoolean(false)
        val done = CountDownLatch(1)
        var result: Result<T>? = null
        val task = Runnable {
            if (!cancelled.get()) result = runCatching(block)
            done.countDown()
        }
        main.post(task)
        val remaining = (deadline - SystemClock.uptimeMillis()).coerceIn(1, 1_000)
        if (!done.await(remaining, TimeUnit.MILLISECONDS)) {
            cancelled.set(true); main.removeCallbacks(task)
            error("UI thread timeout; closing native host")
        }
        return checkNotNull(result).getOrThrow()
    }
}
