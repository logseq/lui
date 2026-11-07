package dev.lui.drive.sample

import android.app.Activity
import dev.lui.LuiBackend
import dev.lui.drive.DriveTarget

internal object DriveHook {
    fun attach(activity: Activity, backend: LuiBackend): AutoCloseable? =
        if (activity.intent.getBooleanExtra("luiDrive", false)) DriveTarget.attach(activity, backend) else null
}
