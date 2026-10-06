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
    private fun dispatchPatch(json: String) {
        val sink = patchSink ?: return
        mainHandler.post { sink.onPatch(json) }
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
        latch.await(30, TimeUnit.SECONDS)
        started = true
        return result.get() != 0
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
        latch.await(10, TimeUnit.SECONDS)
        return result.get()
    }

    fun appear(node: Int) = dispatch { nativeAppear(node.toLong()) }

    fun press(node: Int) = dispatch { nativePress(node.toLong()) }

    fun longPress(node: Int) = dispatch { nativeLongPress(node.toLong()) }

    fun textChanged(node: Int, text: String) = dispatch {
        nativeTextChanged(node.toLong(), text)
    }

    fun submit(node: Int) = dispatch { nativeSubmit(node.toLong()) }

    fun dismiss(node: Int) = dispatch { nativeDismiss(node.toLong()) }

    fun picked(node: Int, payload: String) = dispatch {
        nativePicked(node.toLong(), payload)
    }

    fun doublePress(node: Int) = dispatch { nativeDoublePress(node.toLong()) }

    fun toggleChanged(node: Int, checked: Boolean) = dispatch {
        nativeToggleChanged(node.toLong(), if (checked) 1 else 0)
    }

    fun radioChanged(node: Int) = dispatch { nativeRadioChanged(node.toLong()) }

    fun sliderChanged(node: Int, fraction: Double) = dispatch {
        nativeSliderChanged(node.toLong(), fraction)
    }

    fun pressDetail(node: Int, detail: LuiPointerDetail) = dispatch {
        nativePressDetail(
            node.toLong(), detail.x, detail.y,
            detail.modifiers, detail.button, detail.targetClass,
        )
    }

    fun pointerDown(node: Int, detail: LuiPointerDetail) = dispatch {
        nativePointerDown(
            node.toLong(), detail.x, detail.y,
            detail.modifiers, detail.button, detail.targetClass,
        )
    }

    fun pointerUp(node: Int, detail: LuiPointerDetail) = dispatch {
        nativePointerUp(
            node.toLong(), detail.x, detail.y,
            detail.modifiers, detail.button, detail.targetClass,
        )
    }

    fun pointerEnter(node: Int) = dispatch { nativePointerEnter(node.toLong()) }

    fun pointerLeave(node: Int) = dispatch { nativePointerLeave(node.toLong()) }

    fun contextMenuPress(node: Int, detail: LuiPointerDetail) = dispatch {
        nativeContextMenuPress(
            node.toLong(), detail.x, detail.y,
            detail.modifiers, detail.button, detail.targetClass,
        )
    }

    fun extensionEvent(
        node: Int,
        identifier: String,
        name: String,
        jsonValues: String,
    ) = dispatch {
        nativeExtensionEvent(node.toLong(), identifier, name, jsonValues)
    }

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

    private external fun nativeTextChanged(node: Long, text: String): Int

    private external fun nativeSubmit(node: Long): Int

    private external fun nativeDismiss(node: Long): Int

    private external fun nativePicked(node: Long, payload: String): Int

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
        targetClass: String,
    ): Int

    private external fun nativePointerDown(
        node: Long,
        x: Double,
        y: Double,
        modifiers: Int,
        button: Int,
        targetClass: String,
    ): Int

    private external fun nativePointerUp(
        node: Long,
        x: Double,
        y: Double,
        modifiers: Int,
        button: Int,
        targetClass: String,
    ): Int

    private external fun nativePointerEnter(node: Long): Int

    private external fun nativePointerLeave(node: Long): Int

    private external fun nativeContextMenuPress(
        node: Long,
        x: Double,
        y: Double,
        modifiers: Int,
        button: Int,
        targetClass: String,
    ): Int

    private external fun nativeExtensionEvent(
        node: Long,
        identifier: String,
        name: String,
        jsonValues: String,
    ): Int

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
            ) { (key, value) -> "\"$key\":${value.toJsonLiteral()}" },
        )
        // Events the mobile bridge has no dedicated export for; the OCaml
        // side handles them through other paths or ignores them.
        is LuiEvent.PressModifiers,
        is LuiEvent.ScrollCompleted,
        is LuiEvent.VisibleRange,
        is LuiEvent.Load,
        -> Unit
    }
}
