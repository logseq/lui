package dev.lui

import org.junit.Assert.*
import org.junit.Test

class LuiSparseVirtualCompatibilityTest {
    private fun tree(): LuiRetainedTree {
        val registry = LuiExtensionRegistry()
        registry.register("virtual-row", "v1", builder = {})
        return LuiRetainedTree(registry).also { it.apply(LuiPatchBatch.parse("""{"generation":1,"ops":[
            {"op":"create-node","id":1,"kind":"virtual-list"},
            {"op":"create-node","id":2,"kind":"list-item"},
            {"op":"set-prop","id":2,"property":"text","value":"preserved"},
            {"op":"create-extension","id":3,"identifier":"virtual-row","fingerprint":"v1"},
            {"op":"insert-child","parent":1,"child":2,"index":0},
            {"op":"insert-child","parent":1,"child":3,"index":1}
        ]}""")) }
    }

    private fun metadata(count: String = "100000", generation: String = "1", indices: String = "[0,99999]", target: String? = null): String =
        """{"op":"set-prop","id":1,"property":"virtual-total-count","value":$count},
        {"op":"set-prop","id":1,"property":"virtual-generation","value":$generation},
        {"op":"set-prop","id":1,"property":"virtual-indices","value":"$indices"}""" +
            (target?.let { """,{"op":"set-prop","id":1,"property":"virtual-scroll-index","value":$it}""" } ?: "")

    @Test fun `sparse extension rows accept metadata before final child edits`() {
        val tree = tree()
        tree.apply(LuiPatchBatch.parse("""{"generation":2,"ops":[${metadata()},
            {"op":"move-child","parent":1,"child":3,"index":0}
        ]}"""))
        assertEquals(listOf(3L, 2L), tree.node(1)!!.children)
        assertEquals("[0,99999]", tree.node(1)!!.properties["virtual-indices"]!!.stringValue)
        assertEquals(3, tree.nodes.size + tree.extensionNodes.size)
    }

    @Test fun `invalid sparse relationships roll back preceding text and structural changes`() {
        val invalid = listOf(
            metadata(count = "-1"), metadata(count = "1.5"), metadata(generation = "0"),
            metadata(generation = "1.5"), metadata(indices = "[0]"), metadata(indices = "[]"),
            metadata(indices = "[0,100000]"), metadata(indices = "[2,1]"), metadata(indices = "[0,0]"),
            metadata(indices = "[-1,2]"), metadata(indices = "[0, 1]"), metadata(indices = "[0,1.0]"),
            metadata(indices = "[0,+1]"), metadata(indices = "[0,01]"), metadata(indices = "[0,1,]"),
            metadata(target = "100000"), metadata(target = "-2"),
            """{"op":"set-prop","id":1,"property":"virtual-total-count","value":100000}""",
            """{"op":"set-prop","id":1,"property":"virtual-scroll-index","value":0}""",
        )
        for (ops in invalid) {
            val tree = tree()
            assertThrows("must reject $ops", LuiBackendException::class.java) {
                tree.apply(LuiPatchBatch.parse("""{"generation":2,"ops":[
                    {"op":"set-prop","id":2,"property":"text","value":"wrong"},
                    {"op":"create-node","id":4,"kind":"text"},$ops
                ]}"""))
            }
            assertEquals(1, tree.generation)
            assertEquals("preserved", tree.node(2)!!.properties["text"]!!.stringValue)
            assertEquals(listOf(2L, 3L), tree.node(1)!!.children)
            assertNull(tree.node(4))
            assertNull(tree.node(1)!!.properties["virtual-total-count"])
        }
    }

    @Test fun `metadata removal is atomic and empty source can resync`() {
        val tree = tree()
        tree.apply(LuiPatchBatch.parse("""{"generation":2,"ops":[${metadata(target = "-1")}]}"""))
        assertThrows(LuiBackendException::class.java) {
            tree.apply(LuiPatchBatch.parse("""{"generation":3,"ops":[
                {"op":"remove-prop","id":1,"property":"virtual-indices"}
            ]}"""))
        }
        tree.apply(LuiPatchBatch.parse("""{"generation":3,"ops":[
            {"op":"detach-subtree","id":2},{"op":"detach-subtree","id":3},
            ${metadata(count = "0", generation = "2", indices = "[]", target = "-1")}
        ]}"""))
        assertTrue(tree.node(1)!!.children.isEmpty())
        assertEquals(1, tree.nodes.size)
        tree.apply(LuiPatchBatch.parse("""{"generation":4,"ops":[
            {"op":"remove-prop","id":1,"property":"virtual-scroll-index"},
            {"op":"remove-prop","id":1,"property":"virtual-total-count"},
            {"op":"remove-prop","id":1,"property":"virtual-generation"},
            {"op":"remove-prop","id":1,"property":"virtual-indices"}
        ]}"""))
        assertTrue(tree.node(1)!!.properties.isEmpty())
    }
}
