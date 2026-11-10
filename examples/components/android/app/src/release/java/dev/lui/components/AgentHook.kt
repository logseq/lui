package dev.lui.components

import android.content.Intent

/** Release builds never open the lui-agent socket. */
internal object AgentHook {
    @Suppress("UNUSED_PARAMETER")
    fun start(intent: Intent): AutoCloseable? = null
}
