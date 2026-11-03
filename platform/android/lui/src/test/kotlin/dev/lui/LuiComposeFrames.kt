package dev.lui

import android.os.Handler
import android.os.Looper
import android.view.Choreographer
import androidx.compose.runtime.Recomposer
import androidx.compose.ui.platform.AndroidUiFrameClock
import androidx.compose.ui.platform.ComposeView
import app.cash.paparazzi.Paparazzi
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.android.asCoroutineDispatcher
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/** Own the frame clock alongside each layoutlib composition, including its teardown. */
internal fun Paparazzi.luiFrames(view: ComposeView, name: String, end: Long, fps: Int) {
    // Paparazzi resets Choreographer callbacks between rules; Compose's cached
    // dispatcher-backed clock outlives that reset. Use the current native clock
    // through a public, independently owned composition context instead.
    val context = Handler(Looper.getMainLooper()).asCoroutineDispatcher() +
        AndroidUiFrameClock(Choreographer.getInstance()) + SupervisorJob()
    val recomposer = Recomposer(context)
    val scope = CoroutineScope(context)
    view.setParentCompositionContext(recomposer)
    scope.launch { recomposer.runRecomposeAndApplyChanges() }
    try {
        gif(view, name = name, end = end, fps = fps)
    } finally {
        view.disposeComposition()
        recomposer.cancel()
        scope.cancel()
    }
}
