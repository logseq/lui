package dev.lui

import java.io.IOException
import java.io.Reader
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/**
 * Serves lui-agent requests (see tooling/lui_agent.mjs) from one loopback
 * TCP client at a time: each request line goes to [LuiBridge.agent] and each
 * reply is one line. Start it from debug code only, after [LuiBridge.start];
 * the app needs the INTERNET permission, and `adb forward tcp:PORT tcp:PORT`
 * exposes the port to the development machine.
 */
class LuiAgentServer private constructor(private val socket: ServerSocket) : AutoCloseable {
    @Volatile
    private var client: Socket? = null

    val port: Int get() = socket.localPort

    private val thread = Thread(::serve, "lui-agent").apply {
        isDaemon = true
        start()
    }

    private fun serve() {
        while (!socket.isClosed) {
            val connection = try {
                socket.accept()
            } catch (_: IOException) {
                return
            }
            client = connection
            try {
                connection.use(::answer)
            } catch (_: IOException) {
            } finally {
                client = null
            }
        }
    }

    private fun answer(connection: Socket) {
        val reader = connection.getInputStream().bufferedReader(Charsets.UTF_8)
        val writer = connection.getOutputStream().bufferedWriter(Charsets.UTF_8)
        while (true) {
            val line = try {
                readLine(reader) ?: return
            } catch (_: LineTooLong) {
                null
            }
            if (line != null && line.isBlank()) continue
            val reply = if (line == null) failure("lui: agent request exceeds 1 MiB") else try {
                LuiBridge.agent(line)
            } catch (error: RuntimeException) {
                failure(error.message ?: "lui: agent request failed")
            }
            writer.write(reply)
            writer.write("\n")
            writer.flush()
        }
    }

    private class LineTooLong : IOException()

    // Null at end of stream. A line longer than MAX_LINE is consumed to its
    // end and then refused, so the client can keep the connection.
    private fun readLine(reader: Reader): String? {
        val line = StringBuilder()
        var tooLong = false
        while (true) {
            val next = reader.read()
            if (next == -1 || next == '\n'.code) {
                if (tooLong) throw LineTooLong()
                return if (next == -1 && line.isEmpty()) null else line.toString()
            }
            if (line.length >= MAX_LINE) tooLong = true else line.append(next.toChar())
        }
    }

    override fun close() {
        socket.close()
        client?.close()
        thread.join(1000)
    }

    companion object {
        const val DEFAULT_PORT: Int = 49380
        private const val MAX_LINE = 1 shl 20

        private fun failure(message: String): String =
            buildJsonObject {
                put("ok", false)
                put("error", message)
            }.toString()

        /** Listens on the loopback interface only; port 0 picks a free port. */
        fun start(port: Int = DEFAULT_PORT): LuiAgentServer =
            LuiAgentServer(ServerSocket(port, 1, InetAddress.getLoopbackAddress()))
    }
}
