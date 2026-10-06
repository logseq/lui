package dev.lui

/** Pointer-level payload shared by press-detail/pointer events; matches the
 * OCaml `pointer_detail` record. On gestures that expose no hit position the
 * host emits zero coordinates — never invented values. */
data class LuiPointerDetail(
    val x: Double = 0.0,
    val y: Double = 0.0,
    val modifiers: Int = 0,
    val button: Int = 0,
    val targetClass: String = "",
)

/** Events sent from the platform backend toward OCaml. Node ids are the
 * wire int64 values. */
sealed class LuiEvent {
    abstract val node: Long

    data class Appear(override val node: Long) : LuiEvent()
    data class Press(override val node: Long) : LuiEvent()
    data class LongPress(override val node: Long) : LuiEvent()
    data class DoublePress(override val node: Long) : LuiEvent()
    data class Change(override val node: Long) : LuiEvent()
    data class Submit(override val node: Long) : LuiEvent()
    data class Dismiss(override val node: Long) : LuiEvent()
    data class TextChanged(override val node: Long, val text: String) : LuiEvent()
    data class ToggleChanged(override val node: Long, val checked: Boolean) : LuiEvent()
    data class ValueChanged(override val node: Long, val value: Double) : LuiEvent()
    data class Picked(override val node: Long, val payload: String) : LuiEvent()
    data class VisibleRange(override val node: Long, val first: Long, val last: Long) : LuiEvent()
    data class ScrollCompleted(
        override val node: Long,
        val token: Long,
        val outcome: String,
    ) : LuiEvent()

    data class PressModifiers(override val node: Long, val modifiers: Int) : LuiEvent()
    data class PressDetail(override val node: Long, val detail: LuiPointerDetail) : LuiEvent()
    data class PointerDown(override val node: Long, val detail: LuiPointerDetail) : LuiEvent()
    data class PointerUp(override val node: Long, val detail: LuiPointerDetail) : LuiEvent()
    data class PointerEnter(override val node: Long) : LuiEvent()
    data class PointerLeave(override val node: Long) : LuiEvent()
    data class ContextMenuPress(override val node: Long, val detail: LuiPointerDetail) : LuiEvent()
    data class Load(override val node: Long) : LuiEvent()

    /** `values` is a flat object of scalar values (String/Number/Boolean/null)
     * validated OCaml-side against the extension's declared event schema. */
    data class Extension(
        override val node: Long,
        val identifier: String,
        val name: String,
        val values: Map<String, Any?>,
    ) : LuiEvent()
}

fun interface LuiEventSink {
    fun onEvent(event: LuiEvent)
}
