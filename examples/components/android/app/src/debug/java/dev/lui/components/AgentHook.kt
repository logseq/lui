package dev.lui.components

import android.content.Intent
import android.util.Log
import dev.lui.LuiAgentServer
import java.io.IOException

/**
 * Debug builds answer lui-agent requests when launched with
 * `am start -n dev.lui.components/.MainActivity --ei lui-agent-port 49380`;
 * `adb forward tcp:49380 tcp:49380` then lets tooling/lui_agent.mjs drive
 * the running gallery.
 */
internal object AgentHook {
    fun start(intent: Intent): AutoCloseable? {
        val port = intent.getIntExtra("lui-agent-port", -1)
        if (port < 0) return null
        return try {
            LuiAgentServer.start(port).also { Log.i("LuiAgent", "lui-agent listening on 127.0.0.1:${it.port}") }
        } catch (error: IOException) {
            Log.e("LuiAgent", "lui-agent could not listen on port $port", error)
            null
        }
    }
}
