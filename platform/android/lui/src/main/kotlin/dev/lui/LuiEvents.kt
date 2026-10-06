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

/** Events sent from the platform backend toward OCaml. */
sealed class LuiEvent {
    data class Press(val node: Int) : LuiEvent()
    data class LongPress(val node: Int) : LuiEvent()
    data class TextChanged(val node: Int, val text: String) : LuiEvent()
    data class Submit(val node: Int) : LuiEvent()
    data class ToggleChanged(val node: Int, val checked: Boolean) : LuiEvent()
    data class Change(val node: Int) : LuiEvent()
    data class ValueChanged(val node: Int, val value: Double) : LuiEvent()
    data class Dismiss(val node: Int) : LuiEvent()
    data class DoublePress(val node: Int) : LuiEvent()
    data class Appear(val node: Int) : LuiEvent()
    data class ScrollCompleted(val node: Int, val token: Int, val outcome: String) : LuiEvent()
    data class VisibleRange(val node: Int, val first: Int, val last: Int) : LuiEvent()
    data class Picked(val node: Int, val payload: String) : LuiEvent()
    data class PressModifiers(val node: Int, val modifiers: Int) : LuiEvent()
    data class PressDetail(val node: Int, val detail: LuiPointerDetail) : LuiEvent()
    data class PointerDown(val node: Int, val detail: LuiPointerDetail) : LuiEvent()
    data class PointerUp(val node: Int, val detail: LuiPointerDetail) : LuiEvent()
    data class PointerEnter(val node: Int) : LuiEvent()
    data class PointerLeave(val node: Int) : LuiEvent()
    data class ContextMenuPress(val node: Int, val detail: LuiPointerDetail) : LuiEvent()
    data class Load(val node: Int) : LuiEvent()
    data class Extension(
        val node: Int,
        val identifier: String,
        val name: String,
        val values: Map<String, LuiWireValue>,
    ) : LuiEvent()
}

fun interface LuiEventSink {
    fun onEvent(event: LuiEvent)
}
