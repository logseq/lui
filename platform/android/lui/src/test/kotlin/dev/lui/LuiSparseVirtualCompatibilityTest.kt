package dev.lui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Test

class LuiSparseVirtualCompatibilityTest {
    @Test fun `unsupported sparse metadata rejects the batch while eager rows remain usable`() {
        val properties = listOf(
            "virtual-total-count" to "100000",
            "virtual-generation" to "1",
            "virtual-indices" to "\"[0]\"",
            "virtual-scroll-index" to "99999",
        )
        for ((property, value) in properties) {
            val tree = LuiRetainedTree(LuiExtensionRegistry())
            tree.apply(LuiPatchBatch.parse("""{"generation":1,"ops":[
                {"op":"create-node","id":1,"kind":"virtual-list"},
                {"op":"set-prop","id":1,"property":"overscan","value":0},
                {"op":"set-prop","id":1,"property":"item-extent","value":24.5},
                {"op":"create-node","id":2,"kind":"list-item"},
                {"op":"set-prop","id":2,"property":"text","value":"Eager row"},
                {"op":"insert-child","parent":1,"child":2,"index":0}
            ]}"""))
            assertThrows(LuiBackendException::class.java) {
                tree.apply(LuiPatchBatch.parse("""{"generation":2,"ops":[
                    {"op":"set-prop","id":2,"property":"text","value":"must roll back"},
                    {"op":"create-node","id":3,"kind":"list-item"},
                    {"op":"set-prop","id":1,"property":"$property","value":$value}
                ]}"""))
            }
            assertEquals(1, tree.generation)
            assertEquals(LuiWireValue.Str("Eager row"), tree.nodes[2L]!!.properties["text"])
            assertEquals(listOf(2L), tree.nodes[1L]!!.children)
            assertNull(tree.nodes[3L])
            assertThrows(LuiBackendException::class.java) {
                tree.apply(LuiPatchBatch.parse("""{"generation":2,"ops":[
                    {"op":"set-prop","id":2,"property":"text","value":"must also roll back"},
                    {"op":"remove-prop","id":1,"property":"$property"}
                ]}"""))
            }
            assertEquals(LuiWireValue.Str("Eager row"), tree.nodes[2L]!!.properties["text"])
            tree.apply(LuiPatchBatch.parse("""{"generation":2,"ops":[
                {"op":"set-prop","id":2,"property":"text","value":"Eager update"}
            ]}"""))
            assertEquals(LuiWireValue.Str("Eager update"), tree.nodes[2L]!!.properties["text"])
        }
    }
}
