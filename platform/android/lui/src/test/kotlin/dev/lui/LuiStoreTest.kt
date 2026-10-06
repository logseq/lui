package dev.lui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class LuiStoreTest {

    private fun tree() = LuiRetainedTree(LuiExtensionRegistry())

    private fun batch(generation: Int, vararg ops: LuiPatchOp) =
        LuiPatchBatch(generation, ops.toList())

    @Test
    fun `applies create insert set-prop and drop in order`() {
        val tree = tree()
        tree.apply(
            batch(
                1,
                LuiPatchOp.CreateNode(1, LuiNodeKind.root),
                LuiPatchOp.CreateNode(2, LuiNodeKind.column),
                LuiPatchOp.InsertChild(1, 2, 0),
                LuiPatchOp.SetProp(2, "gap", LuiWireValue.IntValue(8)),
            ),
        )
        assertEquals(1, tree.generation)
        assertEquals(listOf(1), tree.rootIds)
        assertEquals(listOf(2), tree.nodes[1]!!.children)
        assertEquals(1, tree.nodes[2]!!.parent)
        assertEquals(LuiWireValue.IntValue(8), tree.nodes[2]!!.properties["gap"])

        tree.apply(
            batch(
                2,
                LuiPatchOp.CreateNode(3, LuiNodeKind.text),
                LuiPatchOp.InsertChild(1, 3, 1),
                LuiPatchOp.RemoveChild(1, 2),
                LuiPatchOp.DropNode(2),
            ),
        )
        assertNull(tree.nodes[2])
        assertEquals(listOf(3), tree.nodes[1]!!.children)
        assertEquals(setOf(2), tree.lastDropped)
    }

    @Test
    fun `rejects generation gaps`() {
        val tree = tree()
        tree.apply(
            batch(
                1,
                LuiPatchOp.CreateNode(1, LuiNodeKind.root),
                LuiPatchOp.CreateNode(2, LuiNodeKind.column),
                LuiPatchOp.InsertChild(1, 2, 0),
            ),
        )
        val error = assertThrows(LuiBackendException::class.java) {
            tree.apply(batch(3, LuiPatchOp.CreateNode(5, LuiNodeKind.column)))
        }
        assertTrue(error.message!!.contains("generation 2"))
        assertNull(tree.nodes[5])
    }

    @Test
    fun `rolls the whole batch back on failure`() {
        val tree = tree()
        tree.apply(
            batch(
                1,
                LuiPatchOp.CreateNode(1, LuiNodeKind.root),
                LuiPatchOp.CreateNode(2, LuiNodeKind.column),
                LuiPatchOp.InsertChild(1, 2, 0),
            ),
        )
        assertThrows(LuiBackendException::class.java) {
            tree.apply(
                batch(
                    2,
                    LuiPatchOp.CreateNode(3, LuiNodeKind.text),
                    // Attach an unknown parent -> whole batch must roll back.
                    LuiPatchOp.InsertChild(99, 3, 0),
                ),
            )
        }
        assertEquals(1, tree.generation)
        assertNull(tree.nodes[3])
    }

    @Test
    fun `set-prop validates against the kind matrix`() {
        val tree = tree()
        tree.apply(
            batch(
                1,
                LuiPatchOp.CreateNode(1, LuiNodeKind.root),
                LuiPatchOp.CreateNode(2, LuiNodeKind.text),
                LuiPatchOp.InsertChild(1, 2, 0),
            ),
        )
        tree.apply(
            batch(2, LuiPatchOp.SetProp(2, "text", LuiWireValue.Str("hi"))),
        )
        assertEquals(LuiWireValue.Str("hi"), tree.nodes[2]!!.properties["text"])
    }

    @Test
    fun `move-child reorders within a parent`() {
        val tree = tree()
        tree.apply(
            batch(
                1,
                LuiPatchOp.CreateNode(1, LuiNodeKind.root),
                LuiPatchOp.CreateNode(2, LuiNodeKind.column),
                LuiPatchOp.CreateNode(3, LuiNodeKind.text),
                LuiPatchOp.CreateNode(4, LuiNodeKind.text),
                LuiPatchOp.InsertChild(1, 2, 0),
                LuiPatchOp.InsertChild(2, 3, 0),
                LuiPatchOp.InsertChild(2, 4, 1),
            ),
        )
        tree.apply(batch(2, LuiPatchOp.MoveChild(2, 4, 0)))
        assertEquals(listOf(4, 3), tree.nodes[2]!!.children)
    }

    @Test
    fun `drop-node requires a detached node`() {
        val tree = tree()
        tree.apply(
            batch(
                1,
                LuiPatchOp.CreateNode(1, LuiNodeKind.root),
                LuiPatchOp.CreateNode(2, LuiNodeKind.column),
                LuiPatchOp.InsertChild(1, 2, 0),
            ),
        )
        assertThrows(LuiBackendException::class.java) {
            tree.apply(batch(2, LuiPatchOp.DropNode(2)))
        }
        assertEquals(1, tree.generation)
    }

    @Test
    fun `insert-child rejects cycles`() {
        val tree = tree()
        tree.apply(
            batch(
                1,
                LuiPatchOp.CreateNode(1, LuiNodeKind.root),
                LuiPatchOp.CreateNode(2, LuiNodeKind.column),
                LuiPatchOp.CreateNode(3, LuiNodeKind.column),
                LuiPatchOp.InsertChild(1, 2, 0),
                LuiPatchOp.InsertChild(2, 3, 0),
            ),
        )
        // Attaching the root under a descendant would create a cycle.
        assertThrows(LuiBackendException::class.java) {
            tree.apply(batch(2, LuiPatchOp.InsertChild(3, 1, 0)))
        }
        assertNull(tree.nodes[1]!!.parent)
    }

    @Test
    fun `extension nodes validate fingerprint and defaults`() {
        val registry = LuiExtensionRegistry()
        registry.register(
            identifier = "chart",
            fingerprint = "fp-1",
            properties = listOf(
                LuiExtensionProperty(
                    "title",
                    LuiExtensionValueKind.STRING,
                    defaultValue = LuiWireValue.Str("untitled"),
                ),
            ),
            builder = {},
        )
        val tree = LuiRetainedTree(registry)
        assertThrows(LuiBackendException::class.java) {
            tree.apply(
                batch(1, LuiPatchOp.CreateExtension(1, "chart", "wrong-fp")),
            )
        }
        tree.apply(
            batch(
                1,
                LuiPatchOp.CreateExtension(1, "chart", "fp-1"),
            ),
        )
        assertEquals("chart", tree.extensionNodes[1]!!.identifier)
        assertEquals(
            LuiWireValue.Str("untitled"),
            tree.extensionNodes[1]!!.properties["title"],
        )

        tree.apply(
            batch(2, LuiPatchOp.SetExtensionProp(1, "title", LuiWireValue.Str("q1"))),
        )
        // apply() swaps in fresh node copies, so re-read after each batch.
        assertEquals(
            LuiWireValue.Str("q1"),
            tree.extensionNodes[1]!!.properties["title"],
        )
        // Removing restores the declared default.
        tree.apply(batch(3, LuiPatchOp.RemoveExtensionProp(1, "title")))
        assertEquals(
            LuiWireValue.Str("untitled"),
            tree.extensionNodes[1]!!.properties["title"],
        )
    }

    @Test
    fun `backend reports failure without touching state`() {
        val backend = LuiBackend()
        assertTrue(
            backend.applyBatch(
                """{"generation":1,"ops":[
                    {"op":"create-node","id":1,"kind":"root"},
                    {"op":"create-node","id":9,"kind":"column"},
                    {"op":"insert-child","parent":1,"child":9,"index":0}
                ]}""",
            ),
        )
        assertFalse(
            backend.applyBatch(
                """{"generation":5,"ops":[]}""",
            ),
        )
        // A rejected batch leaves the committed generation untouched.
        assertTrue(
            backend.applyBatch(
                """{"generation":2,"ops":[{"op":"create-node","id":2,"kind":"text"}]}""",
            ),
        )
    }
}
