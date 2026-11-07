package dev.lui.drive.sample

import android.app.Activity
import dev.lui.LuiBackend

internal object DriveHook {
    fun attach(activity: Activity, backend: LuiBackend): AutoCloseable? = null
}
