package dev.lui

/** A retained standard node. Property keys are wire property names. */
class LuiNode(
    val kind: LuiNodeKind,
    var parent: Long? = null,
    val children: MutableList<Long> = mutableListOf(),
    val properties: MutableMap<String, LuiWireValue> = mutableMapOf(),
) {
    fun copy(): LuiNode = LuiNode(kind, parent, children.toMutableList(), properties.toMutableMap())
}

/** A retained extension node (component or platform tweak). */
class LuiExtensionNode(
    val identifier: String,
    val fingerprint: String,
    var parent: Long? = null,
    val children: MutableList<Long> = mutableListOf(),
    val properties: MutableMap<String, LuiWireValue> = mutableMapOf(),
) {
    fun copy(): LuiExtensionNode =
        LuiExtensionNode(identifier, fingerprint, parent, children.toMutableList(), properties.toMutableMap())
}

/**
 * Retained node store. Mirrors the Flutter backend's apply semantics:
 * ops are validated against deep copies and the whole batch is rejected
 * (no state change) when any op or post-condition fails. Generation must
 * advance by exactly one per batch.
 */
class LuiRetainedTree(private val registry: LuiExtensionRegistry) {
    var generation: Int = 0
        private set

    var nodes: Map<Long, LuiNode> = emptyMap()
        private set
    var extensionNodes: Map<Long, LuiExtensionNode> = emptyMap()
        private set

    /** Nodes removed by the last applied batch (only `drop-node` deletes). */
    var lastDropped: Set<Long> = emptySet()
        private set

    val rootIds: List<Long>
        get() = nodes.filterValues { it.parent == null }.keys.toList() +
            extensionNodes.filterValues { it.parent == null }.keys.toList()

    fun node(id: Long): LuiNode? = nodes[id]
    fun extensionNode(id: Long): LuiExtensionNode? = extensionNodes[id]
    fun contains(id: Long): Boolean = nodes.containsKey(id) || extensionNodes.containsKey(id)

    private fun parentOf(
        nodes: Map<Long, LuiNode>,
        ext: Map<Long, LuiExtensionNode>,
        id: Long,
    ): Long? = nodes[id]?.parent ?: ext[id]?.parent

    private fun childrenOf(
        nodes: Map<Long, LuiNode>,
        ext: Map<Long, LuiExtensionNode>,
        id: Long,
    ): MutableList<Long>? = nodes[id]?.children ?: ext[id]?.children

    private fun setParent(
        nodes: Map<Long, LuiNode>,
        ext: Map<Long, LuiExtensionNode>,
        id: Long,
        parent: Long?,
    ) {
        nodes[id]?.let { it.parent = parent }
        ext[id]?.let { it.parent = parent }
    }

    private fun requireNode(nodes: Map<Long, LuiNode>, id: Long): LuiNode =
        nodes[id] ?: throw LuiBackendException("unknown node $id")

    private fun requireExtension(
        ext: Map<Long, LuiExtensionNode>,
        id: Long,
    ): LuiExtensionNode =
        ext[id] ?: throw LuiBackendException("unknown extension node $id")

    fun apply(batch: LuiPatchBatch) {
        val expected = generation + 1
        if (batch.generation != expected) {
            throw LuiBackendException(
                "expected patch generation $expected, received ${batch.generation}",
            )
        }
        val nextNodes = nodes.mapValues { it.value.copy() }.toMutableMap()
        val nextExt = extensionNodes.mapValues { it.value.copy() }.toMutableMap()
        val dropped = mutableSetOf<Long>()
        for (op in batch.ops) {
            applyOp(nextNodes, nextExt, op, dropped)
        }
        validateStates(nextNodes)
        nodes = nextNodes
        extensionNodes = nextExt
        lastDropped = dropped
        generation = batch.generation
    }

    private fun applyOp(
        nodes: MutableMap<Long, LuiNode>,
        ext: MutableMap<Long, LuiExtensionNode>,
        op: LuiPatchOp,
        dropped: MutableSet<Long>,
    ) {
        when (op) {
            is LuiPatchOp.CreateNode -> {
                if (nodes.containsKey(op.id) || ext.containsKey(op.id)) {
                    throw LuiBackendException("node already exists")
                }
                nodes[op.id] = LuiNode(op.kind)
            }
            is LuiPatchOp.CreateExtension -> {
                if (nodes.containsKey(op.id) || ext.containsKey(op.id)) {
                    throw LuiBackendException("node already exists")
                }
                val registration = registry.registration(op.identifier)
                    ?: throw LuiBackendException("unknown extension")
                // "" = same fingerprint as already registered for this
                // identifier (per-session dedupe on the wire); resolve to
                // the registered value like the SwiftUI host does
                if (op.fingerprint.isNotEmpty() && registration.fingerprint != op.fingerprint) {
                    throw LuiBackendException("extension fingerprint mismatch")
                }
                ext[op.id] = LuiExtensionNode(
                    identifier = op.identifier,
                    fingerprint = op.fingerprint.ifEmpty { registration.fingerprint },
                    properties = registration.defaultProperties(),
                )
            }
            is LuiPatchOp.DropNode -> {
                if (parentOf(nodes, ext, op.id) != null ||
                    childrenOf(nodes, ext, op.id)?.isNotEmpty() == true
                ) {
                    throw LuiBackendException("cannot drop an attached node")
                }
                if (nodes.remove(op.id) == null && ext.remove(op.id) == null) {
                    throw LuiBackendException("unknown node ${op.id}")
                }
                dropped.add(op.id)
            }
            is LuiPatchOp.DetachSubtree -> {
                // detach-subtree unmounts a whole retained subtree: the
                // root is unlinked from whatever parent still records it
                // and every descendant is dropped recursively — handlers
                // and registry entries die with it.
                if (!nodes.containsKey(op.id) && !ext.containsKey(op.id)) {
                    throw LuiBackendException("unknown node ${op.id}")
                }
                dropSubtree(nodes, ext, op.id, dropped)
            }
            is LuiPatchOp.SetProp -> {
                val node = requireNode(nodes, op.id)
                if (!LuiKindRules.supports(node.kind, op.property, op.value)) {
                    throw LuiBackendException(
                        "unsupported property value: ${node.kind}.${op.property}",
                    )
                }
                node.properties[op.property] = op.value
            }
            is LuiPatchOp.RemoveProp -> {
                val node = requireNode(nodes, op.id)
                if (!node.properties.containsKey(op.property)) {
                    throw LuiBackendException(
                        "unsupported property: ${node.kind}.${op.property}",
                    )
                }
                node.properties.remove(op.property)
            }
            is LuiPatchOp.SetExtensionProp -> {
                val node = requireExtension(ext, op.id)
                val registration = registry.registration(node.identifier)!!
                val property = registration.properties.firstOrNull { it.name == op.property }
                if (property == null || !property.kind.accepts(op.value)) {
                    throw LuiBackendException("unsupported extension property value")
                }
                node.properties[op.property] = property.kind.normalize(op.value)
            }
            is LuiPatchOp.RemoveExtensionProp -> {
                val node = requireExtension(ext, op.id)
                val registration = registry.registration(node.identifier)!!
                val property = registration.properties.firstOrNull { it.name == op.property }
                    ?: throw LuiBackendException("unknown extension property")
                val default = property.defaultValue
                if (default == null) {
                    node.properties.remove(op.property)
                } else {
                    node.properties[op.property] = property.kind.normalize(default)
                }
            }
            is LuiPatchOp.InsertChild -> {
                if ((!nodes.containsKey(op.parent) && !ext.containsKey(op.parent)) ||
                    (!nodes.containsKey(op.child) && !ext.containsKey(op.child))
                ) {
                    throw LuiBackendException("unknown parent or child node")
                }
                if (parentOf(nodes, ext, op.child) != null) {
                    throw LuiBackendException("child is already attached")
                }
                validateChildRelationship(nodes, ext, op.parent, op.child)
                val children = childrenOf(nodes, ext, op.parent)!!
                if (op.index < 0 || op.index > children.size) {
                    throw LuiBackendException("child index is out of bounds")
                }
                if (isDescendant(nodes, ext, target = op.parent, root = op.child)) {
                    throw LuiBackendException("child insertion would create a cycle")
                }
                children.add(op.index, op.child)
                setParent(nodes, ext, op.child, op.parent)
            }
            is LuiPatchOp.RemoveChild -> {
                val children = childrenOf(nodes, ext, op.parent)
                if (children == null || !children.remove(op.child)) {
                    throw LuiBackendException("child is not attached to parent")
                }
                setParent(nodes, ext, op.child, null)
            }
            is LuiPatchOp.MoveChild -> {
                val children = childrenOf(nodes, ext, op.parent)
                if (children == null || !children.remove(op.child)) {
                    throw LuiBackendException("child is not attached to parent")
                }
                if (op.index < 0 || op.index > children.size) {
                    throw LuiBackendException("child index is out of bounds")
                }
                children.add(op.index, op.child)
            }
        }
    }

    private fun dropSubtree(
        nodes: MutableMap<Long, LuiNode>,
        ext: MutableMap<Long, LuiExtensionNode>,
        id: Long,
        dropped: MutableSet<Long>,
    ) {
        childrenOf(nodes, ext, id)?.toList()?.forEach {
            dropSubtree(nodes, ext, it, dropped)
        }
        parentOf(nodes, ext, id)?.let { parent ->
            childrenOf(nodes, ext, parent)?.remove(id)
        }
        setParent(nodes, ext, id, null)
        nodes.remove(id)
        ext.remove(id)
        dropped.add(id)
    }

    private fun isDescendant(
        nodes: Map<Long, LuiNode>,
        ext: Map<Long, LuiExtensionNode>,
        target: Long,
        root: Long,
    ): Boolean {
        var cursor = parentOf(nodes, ext, target)
        while (cursor != null) {
            if (cursor == root) return true
            cursor = parentOf(nodes, ext, cursor)
        }
        return false
    }

    private fun validateChildRelationship(
        nodes: Map<Long, LuiNode>,
        ext: Map<Long, LuiExtensionNode>,
        parentID: Long,
        childID: Long,
    ) {
        if (nodes[childID]?.kind == LuiNodeKind.root) {
            throw LuiBackendException("runtime root cannot be nested")
        }
        val transparentChild = ext[childID]
        if (transparentChild != null &&
            registry.registration(transparentChild.identifier)?.isTweak == true
        ) {
            if (transparentChild.children.size != 1) {
                throw LuiBackendException("platform tweak requires exactly one child")
            }
            validateChildRelationship(nodes, ext, parentID, transparentChild.children.single())
            return
        }
        val parent = nodes[parentID]
        val child = nodes[childID]
        if (parent != null && child == null) {
            if (!LuiKindRules.acceptsExtensionChildren(parent.kind)) {
                throw LuiBackendException("standard node cannot contain extension")
            }
            return
        }
        val extensionParent = ext[parentID]
        val extensionChild = ext[childID]
        if (extensionParent != null) {
            val registration = registry.registration(extensionParent.identifier)!!
            if (registration.isTweak) {
                if (extensionParent.children.isNotEmpty()) {
                    throw LuiBackendException("platform tweak requires exactly one child")
                }
                return
            }
            if (child != null) {
                if (!registration.acceptsStandardChildren) {
                    throw LuiBackendException("extension does not accept standard children")
                }
                return
            }
            if (extensionChild == null ||
                !registration.childIdentifiers.contains(extensionChild.identifier)
            ) {
                throw LuiBackendException("extension child relationship is not registered")
            }
            return
        }
        if (parent == null || child == null) {
            throw LuiBackendException("unknown parent or child node")
        }
        if (!LuiKindRules.canContainChildren(parent.kind)) {
            throw LuiBackendException("parent cannot contain child")
        }
        if ((parent.kind == LuiNodeKind.dropdownMenu || parent.kind == LuiNodeKind.contextMenu) &&
            child.kind != LuiNodeKind.menuItem &&
            child.kind != LuiNodeKind.menuTrigger &&
            child.kind != LuiNodeKind.divider
        ) {
            throw LuiBackendException("menu accepts only menu-item or separator children")
        }
        if (parent.kind == LuiNodeKind.menuTrigger && child.kind != LuiNodeKind.dropdownMenu) {
            throw LuiBackendException("menu-trigger accepts only a dropdown-menu child")
        }
        if (parent.kind == LuiNodeKind.menuItem &&
            child.kind != LuiNodeKind.contextMenu &&
            child.kind != LuiNodeKind.dropdownMenu
        ) {
            throw LuiBackendException("menu-item accepts only nested menu metadata")
        }
        if (parent.kind != LuiNodeKind.menuItem &&
            LuiKindRules.isContextMenuLeafHost(parent.kind) &&
            child.kind != LuiNodeKind.contextMenu
        ) {
            throw LuiBackendException("interactive leaf accepts only context-menu metadata")
        }
        if (parent.kind == LuiNodeKind.table && child.kind != LuiNodeKind.tableRow) {
            throw LuiBackendException("table can contain only table-row")
        }
        if (parent.kind == LuiNodeKind.tableRow && child.kind != LuiNodeKind.tableCell) {
            throw LuiBackendException("table-row can contain only table-cell")
        }
        if (parent.kind == LuiNodeKind.tree && !LuiKindRules.isTreeRowKind(child.kind)) {
            throw LuiBackendException("tree accepts only row containers")
        }
        if (parent.kind == LuiNodeKind.stepper && child.kind != LuiNodeKind.step) {
            throw LuiBackendException("stepper accepts only step children")
        }
        if (parent.kind == LuiNodeKind.timeline && child.kind != LuiNodeKind.timelineItem) {
            throw LuiBackendException("timeline accepts only timeline-item children")
        }
        if (parent.kind == LuiNodeKind.bottomTabs && child.kind != LuiNodeKind.bottomTab) {
            throw LuiBackendException("bottom-tabs accepts only bottom-tab children")
        }
        if (parent.kind == LuiNodeKind.bottomTab && child.kind == LuiNodeKind.bottomTab) {
            throw LuiBackendException("bottom-tab cannot directly contain bottom-tab")
        }
        if (parent.kind == LuiNodeKind.inputGroup &&
            child.kind != LuiNodeKind.textarea &&
            child.kind != LuiNodeKind.inputGroupActions
        ) {
            throw LuiBackendException(
                "input-group accepts only textarea and input-group-actions children",
            )
        }
        if (parent.kind == LuiNodeKind.toolbar && !LuiKindRules.isToolbarChild(child.kind)) {
            throw LuiBackendException("toolbar accepts only interactive controls and dividers")
        }
        if (parent.kind == LuiNodeKind.listSection &&
            child.kind != LuiNodeKind.listItem &&
            child.kind != LuiNodeKind.listSectionHeader &&
            child.kind != LuiNodeKind.listSectionFooter
        ) {
            throw LuiBackendException(
                "list-section accepts only list rows and section header/footer",
            )
        }
        if ((child.kind == LuiNodeKind.listSectionHeader ||
                child.kind == LuiNodeKind.listSectionFooter) &&
            parent.kind != LuiNodeKind.listSection
        ) {
            throw LuiBackendException("list-section header/footer requires a list-section parent")
        }
        if (child.kind == LuiNodeKind.listSection && parent.kind != LuiNodeKind.list) {
            throw LuiBackendException("list-section requires a direct list parent")
        }
        if (child.kind == LuiNodeKind.swipeActions && parent.kind != LuiNodeKind.listItem) {
            throw LuiBackendException("swipe-actions requires a list-item parent")
        }
        if (parent.kind == LuiNodeKind.swipeActions && child.kind != LuiNodeKind.swipeAction) {
            throw LuiBackendException("swipe-actions accepts only swipe-action children")
        }
        if (child.kind == LuiNodeKind.swipeAction && parent.kind != LuiNodeKind.swipeActions) {
            throw LuiBackendException("swipe-action requires a swipe-actions parent")
        }
    }

    private fun validateStates(nodes: Map<Long, LuiNode>) {
        for (state in nodes.values) {
            if (state.kind == LuiNodeKind.root) {
                if (state.parent != null) {
                    throw LuiBackendException("runtime root cannot have a parent")
                }
                if (state.children.size != 1) {
                    throw LuiBackendException("runtime root requires exactly one child")
                }
            }
            validateSizeAxis(state, "width", "min-width", "max-width")
            validateSizeAxis(state, "height", "min-height", "max-height")
        }
    }

    private fun validateSizeAxis(state: LuiNode, size: String, min: String, max: String) {
        val sizeValue = state.properties[size]?.intValue
        val minValue = state.properties[min]?.intValue
        val maxValue = state.properties[max]?.intValue
        if (sizeValue != null && minValue != null && sizeValue < minValue) {
            throw LuiBackendException("$size below $min")
        }
        if (sizeValue != null && maxValue != null && sizeValue > maxValue) {
            throw LuiBackendException("$size above $max")
        }
        if (minValue != null && maxValue != null && minValue > maxValue) {
            throw LuiBackendException("$min above $max")
        }
    }
}
