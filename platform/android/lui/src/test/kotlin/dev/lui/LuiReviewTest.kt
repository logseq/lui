package dev.lui

import androidx.compose.runtime.snapshots.Snapshot
import androidx.compose.runtime.snapshots.SnapshotStateObserver
import kotlinx.serialization.json.Json
import org.junit.Assert.*
import org.junit.Test
import org.junit.Rule
import app.cash.paparazzi.Paparazzi

class LuiReviewTest {
    @get:Rule
    val paparazzi = Paparazzi()

    private fun initial() = """{"generation":1,"ops":[
        {"op":"create-node","id":1,"kind":"column"},
        {"op":"create-node","id":2,"kind":"text"},
        {"op":"create-node","id":3,"kind":"text"},
        {"op":"set-prop","id":2,"property":"text","value":"before"},
        {"op":"insert-child","parent":1,"child":2,"index":0},
        {"op":"insert-child","parent":1,"child":3,"index":1}
    ]}"""

    @Test
    fun `quoted scalar content always remains a string`() {
        for (content in listOf("123", "true", "false", "1.5", "-42", "null")) {
            assertEquals(LuiWireValue.Str(content), LuiWireValue.of(Json.parseToJsonElement("\"$content\"")))
        }
    }

    @Test
    fun `wire integers preserve values outside 32 bits`() {
        val value = LuiWireValue.of(Json.parseToJsonElement("4294967296"))
        assertEquals("4294967296", value.toJsonLiteral())
        assertEquals(4294967296.0, value.numberValue)
    }

    @Test
    fun `numeric looking text traverses the real backend`() {
        val backend = LuiBackend()
        assertTrue(backend.applyBatch(initial()))
        assertTrue(backend.applyBatch("""{"generation":2,"ops":[
            {"op":"set-prop","id":2,"property":"text","value":"123"}
        ]}"""))
        assertEquals("123", backend.node(2)!!.properties["text"]!!.stringValue)
    }

    @Test
    fun `node reads observe committed changes without invalidating unrelated nodes`() {
        val backend = LuiBackend()
        assertTrue(backend.applyBatch(initial()))
        val changes = mutableListOf<String>()
        val observer = SnapshotStateObserver { it() }
        observer.start()
        try {
            observer.observeReads("changed", { changes += it }) { backend.node(2) }
            observer.observeReads("unrelated", { changes += it }) { backend.node(3) }
            assertTrue(backend.applyBatch("""{"generation":2,"ops":[
                {"op":"set-prop","id":2,"property":"text","value":"after"}
            ]}"""))
            Snapshot.sendApplyNotifications()
            assertEquals(listOf("changed"), changes)
        } finally {
            observer.stop()
            observer.clear()
        }
    }

    @Test
    fun `a local patch preserves unrelated retained node identity`() {
        val backend = LuiBackend()
        assertTrue(backend.applyBatch(initial()))
        val unrelated = backend.node(3)
        assertTrue(backend.applyBatch("""{"generation":2,"ops":[
            {"op":"set-prop","id":2,"property":"text","value":"after"}
        ]}"""))
        assertSame(unrelated, backend.node(3))
    }

    @Test
    fun `self parenting is rejected and rollback retains the old tree`() {
        val tree = LuiRetainedTree(LuiExtensionRegistry())
        tree.apply(LuiPatchBatch.parse(initial()))
        assertThrows(LuiBackendException::class.java) {
            tree.apply(LuiPatchBatch.parse("""{"generation":2,"ops":[
                {"op":"insert-child","parent":1,"child":1,"index":0}
            ]}"""))
        }
        assertNull(tree.node(1)!!.parent)
        assertEquals(listOf(2L, 3L), tree.node(1)!!.children)
    }

    @Test
    fun `an authoritative snapshot recovers a rejected generation and accepts later deltas`() {
        val backend = LuiBackend()
        assertTrue(backend.applyBatch(initial()))
        assertFalse(backend.applyBatch("""{"generation":2,"ops":[
            {"op":"set-prop","id":99,"property":"text","value":"invalid"}
        ]}"""))
        // A full snapshot is a separate application boundary, not a delta.
        val method = backend.javaClass.methods.firstOrNull {
            it.name == "applySnapshot" && it.parameterTypes.contentEquals(arrayOf(String::class.java))
        }
        assertNotNull("backend must accept an authoritative snapshot after host rejection", method)
        val snapshot = initial().replace("\"generation\":1", "\"generation\":2")
        assertEquals(true, method!!.invoke(backend, snapshot))
        assertTrue(backend.applyBatch("""{"generation":3,"ops":[
            {"op":"set-prop","id":2,"property":"text","value":"recovered"}
        ]}"""))
        assertEquals("recovered", backend.node(2)!!.properties["text"]!!.stringValue)
        assertEquals(listOf(2L, 3L), backend.node(1)!!.children)
    }

    @Test
    fun `bridge stop retires the active sink and allows a fresh start`() {
        val started = LuiBridge.javaClass.getDeclaredField("started").apply { isAccessible = true }
        val sink = LuiBridge.javaClass.getDeclaredField("patchSink").apply { isAccessible = true }
        val originalStarted = started.getBoolean(LuiBridge)
        val originalSink = sink.get(LuiBridge)
        try {
            started.setBoolean(LuiBridge, true)
            sink.set(LuiBridge, LuiBridge.PatchSink { _, _ -> true })
            LuiBridge.stop()
            assertFalse("a stopped runtime must not report that it is started", started.getBoolean(LuiBridge))
            assertNull("a retired Activity must not receive future patches", sink.get(LuiBridge))
        } finally {
            started.setBoolean(LuiBridge, originalStarted)
            sink.set(LuiBridge, originalSink)
        }
    }

    @Test
    fun `failed native loading does not retain a patch receiver`() {
        val sink = LuiBridge.javaClass.getDeclaredField("patchSink").apply { isAccessible = true }
        assertThrows(UnsatisfiedLinkError::class.java) {
            LuiBridge.start("lui_missing_review_library", sink = LuiBridge.PatchSink { _, _ -> true })
        }
        assertNull(sink.get(LuiBridge))
    }
}
