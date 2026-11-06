package dev.lui.drive

import android.content.pm.ApplicationInfo
import android.inputmethodservice.InputMethodService
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.ExtractedTextRequest
import android.view.inputmethod.InputConnection

/** An explicitly selected test-device IME. No clipboard or semantic editing is used. */
class DriveInputMethod : InputMethodService() {
    internal var session = 0L
        private set
    internal var editor: EditorInfo? = null
        private set

    override fun onCreate() {
        super.onCreate()
        check(applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0) {
            "Drive IME requires a debuggable application"
        }
        active = this
    }

    override fun onStartInput(attribute: EditorInfo, restarting: Boolean) {
        super.onStartInput(attribute, restarting)
        session++
        editor = attribute
    }

    override fun onFinishInput() {
        editor = null
        session++
        super.onFinishInput()
    }

    override fun onDestroy() {
        if (active === this) active = null
        super.onDestroy()
    }

    override fun onEvaluateInputViewShown(): Boolean {
        super.onEvaluateInputViewShown()
        return false
    }

    internal fun connection(packageName: String): InputConnection {
        check(editor?.packageName == packageName) { "test IME is not connected to the target editor" }
        return checkNotNull(currentInputConnection) { "no native InputConnection" }
    }

    companion object {
        @Volatile internal var active: DriveInputMethod? = null
            private set

        // RemoteInputConnection queries must not block the editor's UI looper.
        internal fun replace(connection: InputConnection, text: String, checkCurrent: () -> Unit) {
            val extracted = checkNotNull(connection.getExtractedText(ExtractedTextRequest().apply {
                hintMaxChars = 1_048_576
                hintMaxLines = 1_048_576
            }, 0)) { "editor does not support complete native text extraction" }
            check(extracted.startOffset == 0 && extracted.partialStartOffset == -1) {
                "editor returned a partial text value; replacement is unsupported"
            }
            checkCurrent()
            check(connection.beginBatchEdit()) { "editor rejected native batch edit" }
            try {
                check(connection.setSelection(0, extracted.text.length)) { "editor rejected native selection" }
                checkCurrent()
                check(connection.commitText(text, 1)) { "editor rejected native Unicode commit" }
            } finally {
                connection.endBatchEdit()
            }
        }
    }
}
