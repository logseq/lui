package dev.lui

import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEvent
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.type
import androidx.compose.ui.text.input.TextFieldValue

/** One retained field owns native completion and its subsequent blur. */
internal class LuiTextBlurLifecycle {
    private var focused = false
    private var suppressBlur = false
    private var cancelled = false

    fun edited() { suppressBlur = false; cancelled = false }

    fun compositionChanged(composing: Boolean) {
        // Native focus loss may finish composition without beginning a draft.
        if (composing) edited()
    }

    fun beforeSubmit(action: () -> Unit) {
        if (cancelled) return
        suppressBlur = true
        action()
    }

    fun beforeDismiss(action: () -> Unit) {
        if (cancelled) return
        cancelled = true
        suppressBlur = true
        action()
    }

    fun focusChanged(next: Boolean, enabled: Boolean, submitOnBlur: Boolean,
                     composing: Boolean, submit: () -> Unit) {
        val gained = !focused && next
        val lost = focused && !next
        focused = next
        if (gained) edited()
        else if (lost) {
            val suppressed = suppressBlur
            suppressBlur = false
            if (enabled && submitOnBlur && !composing && !suppressed && !cancelled) submit()
        }
    }
}

internal fun luiTextDismissRequested(node: LuiNodeLike, value: TextFieldValue, event: KeyEvent): Boolean {
    val native = event.nativeKeyEvent
    return LuiKindRules.isTextControl(node.kind) && node.kind != LuiNodeKind.combobox &&
        node.prop("dismiss-enabled")?.boolValue == true && node.isEnabled() &&
        value.composition == null && event.type == KeyEventType.KeyDown && event.key == Key.Escape &&
        native.repeatCount == 0 && !native.isShiftPressed && !native.isCtrlPressed &&
        !native.isMetaPressed && !native.isAltPressed
}
