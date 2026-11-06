package dev.lui.drive

import android.app.Activity
import android.content.pm.ApplicationInfo
import android.os.Looper
import android.view.View
import android.view.ViewTreeObserver
import dev.lui.LuiBackend
import dev.lui.LuiInspection
import java.lang.ref.WeakReference

/** Register from a debug Activity after setContent; registration does not open a socket. */
class DriveTarget private constructor(
    val activity: Activity,
    val inspection: LuiInspection,
) : AutoCloseable {
    val viewport: View = activity.findViewById(android.R.id.content)
    internal var draws = 0L
        private set
    private val drawListener = ViewTreeObserver.OnDrawListener { draws++ }

    init { viewport.viewTreeObserver.addOnDrawListener(drawListener) }

    override fun close() {
        check(Looper.myLooper() == Looper.getMainLooper())
        viewport.viewTreeObserver.takeIf { it.isAlive }?.removeOnDrawListener(drawListener)
        inspection.close()
        if (current === this) reference.clear()
    }

    companion object {
        private var reference = WeakReference<DriveTarget>(null)
        internal val current: DriveTarget? get() = reference.get()

        fun attach(activity: Activity, backend: LuiBackend): DriveTarget {
            check(Looper.myLooper() == Looper.getMainLooper())
            check(activity.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0) {
                "Drive requires a debuggable application"
            }
            check(current == null) { "Drive target is already registered" }
            return DriveTarget(activity, backend.inspect()).also { reference = WeakReference(it) }
        }
    }
}
