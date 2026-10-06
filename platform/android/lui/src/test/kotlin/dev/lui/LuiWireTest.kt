package dev.lui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class LuiWireTest {

    @Test
    fun `parses a patch batch with every op kind`() {
        val batch = LuiPatchBatch.parse(
            """
            {
              "generation": 1,
              "ops": [
                {"op": "create-node", "id": 1, "kind": "root"},
                {"op": "create-node", "id": 2, "kind": "column"},
                {"op": "insert-child", "parent": 1, "child": 2, "index": 0},
                {"op": "set-prop", "id": 2, "property": "gap", "value": 8},
                {"op": "remove-prop", "id": 2, "property": "gap"},
                {"op": "move-child", "parent": 1, "child": 2, "index": 0},
                {"op": "remove-child", "parent": 1, "child": 2},
                {"op": "create-extension", "id": 9, "identifier": "split-view",
                 "fingerprint": "fp"},
                {"op": "set-extension-prop", "id": 9, "property": "title",
                 "value": "hi"},
                {"op": "remove-extension-prop", "id": 9, "property": "title"},
                {"op": "drop-node", "id": 2}
              ]
            }
            """.trimIndent(),
        )
        assertEquals(1, batch.generation)
        assertEquals(11, batch.ops.size)
        assertEquals(
            LuiPatchOp.CreateNode(1L, LuiNodeKind.root),
            batch.ops[0],
        )
        assertEquals(
            LuiPatchOp.InsertChild(parent = 1, child = 2, index = 0),
            batch.ops[2],
        )
        assertEquals(
            LuiPatchOp.SetProp(2, "gap", LuiWireValue.IntValue(8)),
            batch.ops[3],
        )
        assertEquals(
            LuiPatchOp.CreateExtension(9, "split-view", "fp"),
            batch.ops[7],
        )
        assertEquals(
            LuiPatchOp.SetExtensionProp(9, "title", LuiWireValue.Str("hi")),
            batch.ops[8],
        )
        assertEquals(LuiPatchOp.DropNode(2L), batch.ops[10])
    }

    @Test
    fun `decodes all wire value kinds`() {
        val batch = LuiPatchBatch.parse(
            """
            {"generation": 1, "ops": [
              {"op": "set-prop", "id": 1, "property": "text", "value": "hello"},
              {"op": "set-prop", "id": 1, "property": "enabled", "value": true},
              {"op": "set-prop", "id": 1, "property": "width", "value": 42},
              {"op": "set-prop", "id": 1, "property": "value", "value": 0.5}
            ]}
            """.trimIndent(),
        )
        val values = batch.ops.map { (it as LuiPatchOp.SetProp).value }
        assertEquals(LuiWireValue.Str("hello"), values[0])
        assertEquals(LuiWireValue.Bool(true), values[1])
        assertEquals(LuiWireValue.IntValue(42), values[2])
        assertEquals(LuiWireValue.DoubleValue(0.5), values[3])
        assertEquals(42.0, values[2].numberValue)
        assertEquals(0.5, values[3].doubleValue)
    }

    @Test
    fun `rejects malformed batches`() {
        assertThrows(LuiBackendException::class.java) {
            LuiPatchBatch.parse("not json")
        }
        assertThrows(LuiBackendException::class.java) {
            LuiPatchBatch.parse("""{"ops": []}""")
        }
        assertThrows(LuiBackendException::class.java) {
            LuiPatchBatch.parse("""{"generation": 1}""")
        }
        assertThrows(LuiBackendException::class.java) {
            LuiPatchBatch.parse(
                """{"generation": 1, "ops": [{"op": "bogus"}]}""",
            )
        }
        assertThrows(LuiBackendException::class.java) {
            LuiPatchBatch.parse(
                """{"generation": 1, "ops":
                   [{"op": "create-node", "id": 1, "kind": "no-such-kind"}]}""",
            )
        }
    }

    @Test
    fun `node kind wire mapping covers the full schema`() {
        assertEquals(LuiNodeKind.bottomTabs, LuiNodeKind.fromWire("bottom-tabs"))
        assertEquals(LuiNodeKind.numberStepper, LuiNodeKind.fromWire("number-stepper"))
        assertEquals(null, LuiNodeKind.fromWire("not-a-kind"))
        assertTrue(LuiNodeKind.entries.size >= 80)
        assertTrue(LuiNodeKind.tabs.isContainer)
        assertTrue(!LuiNodeKind.slider.isContainer)
    }

    @Test
    fun `wire value serializes to JSON literal`() {
        assertEquals("\"hi\"", LuiWireValue.Str("hi").toJsonLiteral())
        assertEquals("true", LuiWireValue.Bool(true).toJsonLiteral())
        assertEquals("3", LuiWireValue.IntValue(3).toJsonLiteral())
        assertEquals("1.5", LuiWireValue.DoubleValue(1.5).toJsonLiteral())
        assertEquals("\"a\\\"b\"", LuiWireValue.Str("a\"b").toJsonLiteral())
    }
}
