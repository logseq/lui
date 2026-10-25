package dev.lui

import androidx.compose.foundation.layout.Box
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsNode
import androidx.compose.ui.semantics.SemanticsOwner
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.text.AnnotatedString
import app.cash.paparazzi.Paparazzi
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

class LuiEditorVirtualTuningTest {
    @get:Rule val paparazzi = Paparazzi()

    @Test fun `readonly fields reject actual native semantics editing while remaining enabled`() {
        for (kind in listOf("text-field", "secure-field", "input", "search-field", "textarea", "combobox")) {
            val events = mutableListOf<LuiEvent>()
            val backend = LuiBackend(onEvent = { events.add(it) })
            assertTrue(backend.lastError, backend.applyBatch("""{"generation":1,"ops":[
                {"op":"create-node","id":1,"kind":"$kind"},
                {"op":"set-prop","id":1,"property":"text","value":"preserved"},
                {"op":"set-prop","id":1,"property":"read-only","value":true},
                {"op":"set-prop","id":1,"property":"change-enabled","value":true},
                {"op":"set-prop","id":1,"property":"submit-enabled","value":true}
            ]}"""))
            var inspected = false
            paparazzi.snapshot(name = "readonly-$kind") {
                val native = LocalView.current
                Box(Modifier.onGloballyPositioned {
                    if (!inspected) {
                        val owner = native.javaClass.methods.first { it.name == "getSemanticsOwner" }.invoke(native) as SemanticsOwner
                        fun fields(node: SemanticsNode): List<SemanticsNode> =
                            (if (node.config.getOrNull(SemanticsProperties.EditableText) != null) listOf(node) else emptyList()) + node.children.flatMap(::fields)
                        val field = fields(owner.unmergedRootSemanticsNode).firstOrNull()
                        if (field != null) {
                            inspected = true
                            assertNull(field.config.getOrNull(SemanticsProperties.Disabled))
                            val edit = field.config.getOrNull(SemanticsActions.SetText)?.action
                            assertTrue("readonly $kind accepted text editing", edit == null || !edit(AnnotatedString("mutated")))
                            assertTrue(events.none { it is LuiEvent.TextChanged })
                        }
                    }
                }) { backend.Content(1) }
            }
            assertTrue("native editor semantics were not mounted for $kind", inspected)
        }
    }

    @Test fun `typed extent takes precedence in real lazy row geometry`() {
        val backend = LuiBackend()
        assertTrue(backend.lastError, backend.applyBatch("""{"generation":1,"ops":[
            {"op":"create-node","id":1,"kind":"virtual-list"},
            {"op":"set-prop","id":1,"property":"height","value":300},
            {"op":"set-prop","id":1,"property":"item-extent","value":24.5},
            {"op":"set-prop","id":1,"property":"data-attrs","value":"data-item-extent\u001f55"},
            {"op":"create-node","id":2,"kind":"column"},
            {"op":"set-prop","id":2,"property":"data-attrs","value":"data-virtual-count\u001f100\u001edata-virtual-start\u001f5\u001edata-virtual-length\u001f1\u001edata-item-extent\u001f40"},
            {"op":"create-node","id":3,"kind":"text"},
            {"op":"set-prop","id":3,"property":"text","value":"Sentinel"},
            {"op":"insert-child","parent":2,"child":3,"index":0},
            {"op":"insert-child","parent":1,"child":2,"index":0}
        ]}"""))
        var measured: Float? = null
        paparazzi.snapshot(name = "typed-extent") {
            val native = LocalView.current
            val density = LocalDensity.current.density
            Box(Modifier.onGloballyPositioned {
                val owner = native.javaClass.methods.first { it.name == "getSemanticsOwner" }.invoke(native) as SemanticsOwner
                fun marker(node: SemanticsNode): SemanticsNode? {
                    if (node.config.getOrNull(SemanticsProperties.Text)?.any { it.text == "Sentinel" } == true) return node
                    return node.children.firstNotNullOfOrNull(::marker)
                }
                measured = marker(owner.unmergedRootSemanticsNode)?.boundsInRoot?.top?.div(density)
            }) { backend.Content(1) }
        }
        assertNotNull("typed estimate should place the retained marker inside the viewport", measured)
        assertEquals(122.5f, measured!!, 1f)
    }

    @Test fun `typed virtual tuning validates zero overscan and positive fractional extent`() {
        val backend = LuiBackend()
        assertTrue(backend.lastError, backend.applyBatch("""{"generation":1,"ops":[
            {"op":"create-node","id":1,"kind":"virtual-list"},
            {"op":"set-prop","id":1,"property":"overscan","value":0},
            {"op":"set-prop","id":1,"property":"item-extent","value":24.5}
        ]}"""))
        for ((property, value) in listOf("overscan" to "-1", "overscan" to "1.5", "item-extent" to "0")) {
            assertFalse(backend.applyBatch("""{"generation":2,"ops":[{"op":"set-prop","id":1,"property":"$property","value":$value}]}"""))
            assertEquals(24.5, backend.node(1)!!.prop("item-extent")!!.numberValue)
        }
    }
}
