package dev.lui

import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

/**
 * JNI bridge to the OCaml LUI runtime, porting the semantics of
 * `platform/flutter/native/lui_ocaml_bridge.c` for Android.
 *
 * Threading contract (mirrors the C header's lock discipline): after
 * [start], the OCaml runtime lock is NOT held between calls, so all
 * `native*` exports must be invoked on an OCaml-registered thread. This
 * object owns a dedicated [HandlerThread] (`lui-ocaml`) that runs
 * [nativeStart] once; every event method then enqueues on that thread so
 * ordering is preserved and callers never touch the runtime lock.
 *
 * Patch delivery: the OCaml callbacks return the pending patch batch as a
 * JSON string while the domain lock is held; [dispatchPatch] copies it
 * into the JVM and posts to the main thread — it must not call back into
 * native exports from inside that callback.
 */
object LuiBridge {
    /** platform_code for `operating_system` in components_bridge.ml. */
    const val PLATFORM_ANDROID: Int = 3

    /** host_code for KotlinHost in components_bridge.ml. */
    const val HOST_KOTLIN: Int = 4

    fun interface PatchSink {
        fun onPatch(json: String)
    }

    private val ocamlThread = HandlerThread("lui-ocaml").apply { start() }
    private val ocamlHandler = Handler(ocamlThread.looper)
    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    private var patchSink: PatchSink? = null

    @Volatile
    private var started = false

    /**
     * Called from JNI while the OCaml domain lock is held. Only copies the
     * string into the JVM and enqueues delivery on the main thread — never
     * call back into native exports from here.
     */
    @JvmStatic
    @Suppress("unused")
    private fun dispatchPatch(json: ByteArray) {
        val sink = patchSink ?: return
        val text = json.toString(Charsets.UTF_8)
        mainHandler.post { sink.onPatch(text) }
    }

    /**
     * Loads the OCaml runtime library and starts the app, delivering patch
     * batches to [sink] on the main thread. Blocks until `nativeStart`
     * returns. Call once per process.
     */
    fun start(libraryName: String, hostCode: Int = HOST_KOTLIN, sink: PatchSink): Boolean {
        if (started) return true
        patchSink = sink
        System.loadLibrary(libraryName)
        val result = AtomicReference<Int>()
        val latch = CountDownLatch(1)
        ocamlHandler.post {
            result.set(nativeStart(PLATFORM_ANDROID, hostCode))
            latch.countDown()
        }
        val completed = latch.await(30, TimeUnit.SECONDS)
        if (!completed) {
            started = false
            return false
        }
        started = result.get() == 1
        return started
    }

    private inline fun dispatch(crossinline call: () -> Int) {
        check(started) { "LuiBridge.start() has not been called" }
        ocamlHandler.post { call() }
    }

    /** Synchronous dispatch for calls that must return a value. */
    private inline fun <T> dispatchBlocking(crossinline call: () -> T): T {
        check(started) { "LuiBridge.start() has not been called" }
        val result = AtomicReference<T>()
        val latch = CountDownLatch(1)
        ocamlHandler.post {
            result.set(call())
            latch.countDown()
        }
        if (!latch.await(10, TimeUnit.SECONDS)) {
            error("LuiBridge call timed out")
        }
        return result.get()
    }

    private fun utf8(text: String): ByteArray = text.toByteArray(Charsets.UTF_8)

    fun appear(node: Long) = dispatch { nativeAppear(node) }

    fun press(node: Long) = dispatch { nativePress(node) }

    fun pressModifiers(node: Long, modifiers: Int) = dispatch {
        nativePressEx(node, modifiers)
    }

    fun longPress(node: Long) = dispatch { nativeLongPress(node) }

    fun textChanged(node: Long, text: String) = dispatch {
        nativeTextChanged(node, utf8(text))
    }

    fun submit(node: Long) = dispatch { nativeSubmit(node) }

    fun dismiss(node: Long) = dispatch { nativeDismiss(node) }

    fun picked(node: Long, payload: String) = dispatch {
        nativePicked(node, utf8(payload))
    }

    fun doublePress(node: Long) = dispatch { nativeDoublePress(node) }

    fun toggleChanged(node: Long, checked: Boolean) = dispatch {
        nativeToggleChanged(node, if (checked) 1 else 0)
    }

    fun radioChanged(node: Long) = dispatch { nativeRadioChanged(node) }

    fun sliderChanged(node: Long, fraction: Double) = dispatch {
        nativeSliderChanged(node, fraction)
    }

    fun pressDetail(node: Long, detail: LuiPointerDetail) = dispatch {
        nativePressDetail(
            node, detail.x, detail.y,
            detail.modifiers, detail.button, utf8(detail.targetClass),
        )
    }

    fun pointerDown(node: Long, detail: LuiPointerDetail) = dispatch {
        nativePointerDown(
            node, detail.x, detail.y,
            detail.modifiers, detail.button, utf8(detail.targetClass),
        )
    }

    fun pointerUp(node: Long, detail: LuiPointerDetail) = dispatch {
        nativePointerUp(
            node, detail.x, detail.y,
            detail.modifiers, detail.button, utf8(detail.targetClass),
        )
    }

    fun pointerEnter(node: Long) = dispatch { nativePointerEnter(node) }

    fun pointerLeave(node: Long) = dispatch { nativePointerLeave(node) }

    fun contextMenuPress(node: Long, detail: LuiPointerDetail) = dispatch {
        nativeContextMenuPress(
            node, detail.x, detail.y,
            detail.modifiers, detail.button, utf8(detail.targetClass),
        )
    }

    fun extensionEvent(
        node: Long,
        identifier: String,
        name: String,
        jsonValues: String,
    ) = dispatch {
        nativeExtensionEvent(node, utf8(identifier), utf8(name), utf8(jsonValues))
    }

    fun visibleRange(node: Long, first: Long, last: Long) = dispatch {
        nativeVisibleRange(node, first, last)
    }

    fun scrollCompleted(node: Long, token: Long, outcome: String) = dispatch {
        nativeScrollCompleted(node, token, utf8(outcome))
    }

    fun load(node: Long) = dispatch { nativeLoad(node) }

    fun stop() = dispatch { nativeStop() }

    /** Root node id of the running app, or -1 when unavailable. */
    fun rootNode(): Long = dispatchBlocking { nativeRootNode() }

    // ------------------------------------------------------------------
    // JNI exports — see src/main/cpp/lui_jni_bridge.c. Always invoked on
    // the `lui-ocaml` thread via the dispatch helpers above.
    // ------------------------------------------------------------------

    private external fun nativeStart(platformCode: Int, hostCode: Int): Int

    private external fun nativeAppear(node: Long): Int

    private external fun nativePress(node: Long): Int

    private external fun nativeLongPress(node: Long): Int

    private external fun nativePressEx(node: Long, modifiers: Int): Int

    private external fun nativeTextChanged(node: Long, text: ByteArray): Int

    private external fun nativeSubmit(node: Long): Int

    private external fun nativeDismiss(node: Long): Int

    private external fun nativePicked(node: Long, payload: ByteArray): Int

    private external fun nativeDoublePress(node: Long): Int

    private external fun nativeToggleChanged(node: Long, checked: Int): Int

    private external fun nativeRadioChanged(node: Long): Int

    private external fun nativeSliderChanged(node: Long, fraction: Double): Int

    private external fun nativePressDetail(
        node: Long,
        x: Double,
        y: Double,
        modifiers: Int,
        button: Int,
        targetClass: ByteArray,
    ): Int

    private external fun nativePointerDown(
        node: Long,
        x: Double,
        y: Double,
        modifiers: Int,
        button: Int,
        targetClass: ByteArray,
    ): Int

    private external fun nativePointerUp(
        node: Long,
        x: Double,
        y: Double,
        modifiers: Int,
        button: Int,
        targetClass: ByteArray,
    ): Int

    private external fun nativePointerEnter(node: Long): Int

    private external fun nativePointerLeave(node: Long): Int

    private external fun nativeContextMenuPress(
        node: Long,
        x: Double,
        y: Double,
        modifiers: Int,
        button: Int,
        targetClass: ByteArray,
    ): Int

    private external fun nativeExtensionEvent(
        node: Long,
        identifier: ByteArray,
        name: ByteArray,
        jsonValues: ByteArray,
    ): Int

    private external fun nativeVisibleRange(node: Long, first: Long, last: Long): Int

    private external fun nativeScrollCompleted(
        node: Long,
        token: Long,
        outcome: ByteArray,
    ): Int

    private external fun nativeLoad(node: Long): Int

    private external fun nativeStop(): Int

    private external fun nativeRootNode(): Long
}

/**
 * Maps a [LuiEvent] onto the [LuiBridge] JNI calls — the default event
 * sink for a [LuiBackend] wired to the OCaml runtime.
 */
fun LuiEvent.dispatchToBridge() {
    val bridge = LuiBridge
    when (this) {
        is LuiEvent.Press -> bridge.press(node)
        is LuiEvent.LongPress -> bridge.longPress(node)
        is LuiEvent.TextChanged -> bridge.textChanged(node, text)
        is LuiEvent.Submit -> bridge.submit(node)
        is LuiEvent.ToggleChanged -> bridge.toggleChanged(node, checked)
        is LuiEvent.Change -> bridge.radioChanged(node)
        is LuiEvent.ValueChanged -> bridge.sliderChanged(node, value)
        is LuiEvent.Dismiss -> bridge.dismiss(node)
        is LuiEvent.DoublePress -> bridge.doublePress(node)
        is LuiEvent.Appear -> bridge.appear(node)
        is LuiEvent.Picked -> bridge.picked(node, payload)
        is LuiEvent.PressDetail -> bridge.pressDetail(node, detail)
        is LuiEvent.PointerDown -> bridge.pointerDown(node, detail)
        is LuiEvent.PointerUp -> bridge.pointerUp(node, detail)
        is LuiEvent.PointerEnter -> bridge.pointerEnter(node)
        is LuiEvent.PointerLeave -> bridge.pointerLeave(node)
        is LuiEvent.ContextMenuPress -> bridge.contextMenuPress(node, detail)
        is LuiEvent.Extension -> bridge.extensionEvent(
            node, identifier, name,
            values.entries.joinToString(
                prefix = "{", postfix = "}",
                separator = ",",
            ) { (key, value) ->
                "${kotlinx.serialization.json.JsonPrimitive(key)}:${luiScalarLiteral(value)}"
            },
        )
        is LuiEvent.PressModifiers -> bridge.pressModifiers(node, modifiers)
        is LuiEvent.ScrollCompleted -> bridge.scrollCompleted(node, token, outcome)
        is LuiEvent.VisibleRange -> bridge.visibleRange(node, first, last)
        is LuiEvent.Load -> bridge.load(node)
    }
}

/** Serializes one extension-event scalar (String/Number/Boolean/null) to
 * its JSON literal. */
private fun luiScalarLiteral(value: Any?): String = when (value) {
    null -> "null"
    is String -> kotlinx.serialization.json.JsonPrimitive(value).toString()
    is Number -> value.toString()
    is Boolean -> value.toString()
    else -> "null"
}
