package dev.lui

import java.net.InetAddress
import java.net.Socket
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class LuiAgentServerTest {
    @Test
    fun answersEveryLineAndBoundsRequests() {
        LuiAgentServer.start(port = 0).use { server ->
            Socket(InetAddress.getLoopbackAddress(), server.port).use { client ->
                val output = client.getOutputStream()
                val replies = client.getInputStream().bufferedReader(Charsets.UTF_8)
                fun exchange(request: String): String? {
                    output.write((request + "\n").toByteArray(Charsets.UTF_8))
                    output.flush()
                    return replies.readLine()
                }
                val reply = exchange("""{"op":"hello"}""")!!
                assertTrue(reply, reply.startsWith("""{"ok":false,"error":"""))
                assertTrue(reply, reply.contains("LuiBridge.start() has not been called"))
                assertEquals(
                    """{"ok":false,"error":"lui: agent request exceeds 1 MiB"}""",
                    exchange("x".repeat((1 shl 20) + 1)),
                )
                assertEquals(reply, exchange("""{"op":"hello"}"""))
                client.shutdownOutput()
                assertNull(replies.readLine())
            }
        }
    }
}
