package dev.lui

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.int
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull

class LuiBackendException(message: String) : Exception(message)

/** Wire-level property value, mirroring OCaml `wire_value`. */
sealed class LuiWireValue {
    data class Str(val value: String) : LuiWireValue()
    data class Bool(val value: Boolean) : LuiWireValue()
    data class IntValue(val value: Int) : LuiWireValue()
    data class DoubleValue(val value: Double) : LuiWireValue()

    val stringValue: String? get() = (this as? Str)?.value
    val boolValue: Boolean? get() = (this as? Bool)?.value
    val intValue: Int? get() = (this as? IntValue)?.value
    val doubleValue: Double?
        get() = when (this) {
            is DoubleValue -> value
            is IntValue -> value.toDouble()
            else -> null
        }
    val numberValue: Double?
        get() = when (this) {
            is DoubleValue -> value
            is IntValue -> value.toDouble()
            else -> null
        }

    /** JSON literal form, for extension-event payloads. */
    fun toJsonLiteral(): String = when (this) {
        is Str -> JsonPrimitive(value).toString()
        is Bool -> value.toString()
        is IntValue -> value.toString()
        is DoubleValue -> value.toString()
    }

    /** Platform-neutral scalar form (String/Int/Double/Boolean). */
    val scalarValue: Any
        get() = when (this) {
            is Str -> value
            is Bool -> value
            is IntValue -> value
            is DoubleValue -> value
        }

    companion object {
        fun of(element: JsonElement): LuiWireValue {
            val primitive = element.jsonPrimitive
            primitive.booleanOrNull?.let { return Bool(it) }
            primitive.longOrNull?.let { return IntValue(it.toInt()) }
            primitive.doubleOrNull?.let { return DoubleValue(it) }
            if (primitive.isString) return Str(primitive.content)
            throw LuiBackendException("unsupported wire value")
        }

        fun toJson(value: LuiWireValue): Any = when (value) {
            is Str -> value.value
            is Bool -> value.value
            is IntValue -> value.value
            is DoubleValue -> value.value
        }
    }
}

sealed class LuiPatchOp {
    data class CreateNode(val id: Long, val kind: LuiNodeKind) : LuiPatchOp()
    data class CreateExtension(val id: Long, val identifier: String, val fingerprint: String) : LuiPatchOp()
    data class DropNode(val id: Long) : LuiPatchOp()
    /** Unmounts a whole retained subtree: the root is unlinked from
        whatever parent still records it and every descendant is dropped
        — handlers and registry entries die with the node recursively. */
    data class DetachSubtree(val id: Long) : LuiPatchOp()
    data class SetProp(val id: Long, val property: String, val value: LuiWireValue) : LuiPatchOp()
    data class RemoveProp(val id: Long, val property: String) : LuiPatchOp()
    data class SetExtensionProp(val id: Long, val property: String, val value: LuiWireValue) : LuiPatchOp()
    data class RemoveExtensionProp(val id: Long, val property: String) : LuiPatchOp()
    data class InsertChild(val parent: Long, val child: Long, val index: Int) : LuiPatchOp()
    data class RemoveChild(val parent: Long, val child: Long) : LuiPatchOp()
    data class MoveChild(val parent: Long, val child: Long, val index: Int) : LuiPatchOp()

    companion object {
        private fun requiredInt(obj: JsonObject, key: String): Int =
            obj[key]?.jsonPrimitive?.intOrNull
                ?: throw LuiBackendException("missing or invalid '$key'")

        private fun requiredLong(obj: JsonObject, key: String): Long =
            obj[key]?.jsonPrimitive?.longOrNull
                ?: throw LuiBackendException("missing or invalid '$key'")

        private fun requiredString(obj: JsonObject, key: String): String =
            obj[key]?.jsonPrimitive?.takeIf { it.isString }?.content
                ?: throw LuiBackendException("missing or invalid '$key'")

        fun of(element: JsonElement): LuiPatchOp {
            val obj = element as? JsonObject
                ?: throw LuiBackendException("operation must be an object")
            return when (val op = obj["op"]?.jsonPrimitive?.content) {
                "create-node" -> CreateNode(
                    id = requiredLong(obj, "id"),
                    kind = LuiNodeKind.fromWire(requiredString(obj, "kind"))
                        ?: throw LuiBackendException("unknown node kind"),
                )
                "create-extension" -> CreateExtension(
                    id = requiredLong(obj, "id"),
                    identifier = requiredString(obj, "identifier"),
                    fingerprint = requiredString(obj, "fingerprint"),
                )
                "drop-node" -> DropNode(id = requiredLong(obj, "id"))
                "detach-subtree" -> DetachSubtree(id = requiredLong(obj, "id"))
                "set-prop" -> SetProp(
                    id = requiredLong(obj, "id"),
                    property = requiredString(obj, "property"),
                    value = LuiWireValue.of(
                        obj["value"] ?: throw LuiBackendException("missing 'value'"),
                    ),
                )
                "remove-prop" -> RemoveProp(
                    id = requiredLong(obj, "id"),
                    property = requiredString(obj, "property"),
                )
                "set-extension-prop" -> SetExtensionProp(
                    id = requiredLong(obj, "id"),
                    property = requiredString(obj, "property"),
                    value = LuiWireValue.of(
                        obj["value"] ?: throw LuiBackendException("missing 'value'"),
                    ),
                )
                "remove-extension-prop" -> RemoveExtensionProp(
                    id = requiredLong(obj, "id"),
                    property = requiredString(obj, "property"),
                )
                "insert-child" -> InsertChild(
                    parent = requiredLong(obj, "parent"),
                    child = requiredLong(obj, "child"),
                    index = requiredInt(obj, "index"),
                )
                "remove-child" -> RemoveChild(
                    parent = requiredLong(obj, "parent"),
                    child = requiredLong(obj, "child"),
                )
                "move-child" -> MoveChild(
                    parent = requiredLong(obj, "parent"),
                    child = requiredLong(obj, "child"),
                    index = requiredInt(obj, "index"),
                )
                else -> throw LuiBackendException("unknown patch operation: $op")
            }
        }
    }
}

class LuiPatchBatch(val generation: Int, val ops: List<LuiPatchOp>) {
    companion object {
        private val json = Json { ignoreUnknownKeys = true }

        fun parse(source: String): LuiPatchBatch {
            val decoded = try {
                json.parseToJsonElement(source)
            } catch (error: Exception) {
                throw LuiBackendException(error.message ?: "invalid patch batch")
            }
            val obj = decoded as? JsonObject
                ?: throw LuiBackendException("patch batch must be an object")
            val generation = obj["generation"]?.jsonPrimitive?.intOrNull
                ?: throw LuiBackendException("missing 'generation'")
            val ops = (obj["ops"] as? kotlinx.serialization.json.JsonArray)
                ?.map(LuiPatchOp::of)
                ?: throw LuiBackendException("missing 'ops'")
            return LuiPatchBatch(generation, ops)
        }
    }
}
