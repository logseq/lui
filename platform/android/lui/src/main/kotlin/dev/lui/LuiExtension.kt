package dev.lui

import androidx.compose.runtime.Composable

enum class LuiExtensionValueKind {
    STRING,
    BOOLEAN,
    INTEGER,
    DOUBLE,
    ;

    fun accepts(value: LuiWireValue): Boolean = when (this) {
        STRING -> value is LuiWireValue.Str
        BOOLEAN -> value is LuiWireValue.Bool
        INTEGER -> value is LuiWireValue.IntValue
        DOUBLE -> value.doubleValue?.isFinite() == true
    }

    fun normalize(value: LuiWireValue): LuiWireValue =
        if (this == DOUBLE && value is LuiWireValue.IntValue) {
            LuiWireValue.DoubleValue(value.value.toDouble())
        } else {
            value
        }
}

class LuiExtensionProperty(
    val name: String,
    val kind: LuiExtensionValueKind,
    val required: Boolean = false,
    val defaultValue: LuiWireValue? = null,
)

class LuiExtensionEventSchema(
    val name: String = "",
    val fields: List<LuiExtensionProperty> = emptyList(),
)

/** View-model passed to extension composable builders. */
class LuiExtensionContext internal constructor(
    internal val backend: LuiBackend,
    val nodeId: Int,
    val identifier: String,
    val properties: Map<String, LuiWireValue>,
    val children: List<Int> = emptyList(),
    internal val renderChild: @Composable (Int) -> Unit,
) {
    fun string(name: String): String? = properties[name]?.stringValue
    fun bool(name: String): Boolean? = properties[name]?.boolValue
    fun int(name: String): Int? = properties[name]?.intValue
    fun double(name: String): Double? = properties[name]?.doubleValue

    fun emitEvent(name: String, values: Map<String, LuiWireValue> = emptyMap()) {
        backend.emitExtensionEvent(nodeId, identifier, name, values)
    }

    /** The extension node behind a declared-child id, if it is one. */
    fun extensionChild(id: Int): LuiExtensionNode? = backend.extensionNode(id)

    @Composable
    fun child(id: Int) = renderChild(id)
}

class LuiExtensionRegistration internal constructor(
    val identifier: String,
    val fingerprint: String,
    val builder: (@Composable LuiExtensionContext.() -> Unit)?,
    val acceptsStandardChildren: Boolean = false,
    val childIdentifiers: List<String> = emptyList(),
    val properties: List<LuiExtensionProperty> = emptyList(),
    val events: List<LuiExtensionEventSchema> = emptyList(),
    val isTweak: Boolean = false,
) {
    internal fun defaultProperties(): MutableMap<String, LuiWireValue> {
        val map = mutableMapOf<String, LuiWireValue>()
        for (property in properties) {
            property.defaultValue?.let { map[property.name] = property.kind.normalize(it) }
        }
        return map
    }
}

/**
 * Host registry for extension components and tweaks, mirroring
 * `LUIFlutterExtensionRegistry`. A registration binds an identifier to a
 * Composable builder plus the declared prop/event schema used to validate
 * `create-extension`/`set-extension-prop` ops on the wire.
 */
class LuiExtensionRegistry {
    private val registrations = mutableMapOf<String, LuiExtensionRegistration>()
    private var frozen = false

    fun register(registration: LuiExtensionRegistration) {
        check(!frozen) { "extension registry is frozen" }
        require(isValidExtensionName(registration.identifier)) {
            "invalid extension identifier"
        }
        require(!isStandardNodeName(registration.identifier)) {
            "extension identifier shadows a standard node"
        }
        require(!registrations.containsKey(registration.identifier)) {
            "extension identifier is already registered"
        }
        registrations[registration.identifier] = registration
    }

    /** Convenience for component extensions. */
    fun register(
        identifier: String,
        fingerprint: String,
        acceptsStandardChildren: Boolean = false,
        childIdentifiers: List<String> = emptyList(),
        properties: List<LuiExtensionProperty> = emptyList(),
        events: List<LuiExtensionEventSchema> = emptyList(),
        builder: @Composable LuiExtensionContext.() -> Unit,
    ) = register(
        LuiExtensionRegistration(
            identifier = identifier,
            fingerprint = fingerprint,
            builder = builder,
            acceptsStandardChildren = acceptsStandardChildren,
            childIdentifiers = childIdentifiers,
            properties = properties,
            events = events,
        ),
    )

    /** A tweak wraps exactly one child with platform-specific styling. */
    fun registerTweak(
        identifier: String,
        fingerprint: String,
        properties: List<LuiExtensionProperty> = emptyList(),
        builder: (@Composable LuiExtensionContext.() -> Unit)?,
    ) = register(
        LuiExtensionRegistration(
            identifier = identifier,
            fingerprint = fingerprint,
            builder = builder,
            acceptsStandardChildren = true,
            properties = properties,
            isTweak = true,
        ),
    )

    internal fun freeze() {
        frozen = true
    }

    fun registration(identifier: String): LuiExtensionRegistration? = registrations[identifier]

    fun isStandardNodeName(name: String): Boolean = LuiNodeKind.fromWire(name) != null

    private fun isValidExtensionName(name: String): Boolean =
        name.isNotEmpty() &&
            name.all { it in 'a'..'z' || it in '0'..'9' || it == '-' || it == '_' } &&
            name.first() in 'a'..'z'
}
