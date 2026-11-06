package dev.lui.drive

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.longOrNull

internal data class DriveAction(val request: Long, val name: String, val fields: JsonObject) {
    fun id(name: String = "id"): Long = (fields.getValue(name) as JsonPrimitive).longOrNull!!
    fun number(name: String): Float = (fields.getValue(name) as JsonPrimitive).doubleOrNull!!.toFloat()
    fun string(name: String): String = (fields.getValue(name) as JsonPrimitive).content

    companion object {
        val capabilities = listOf("click", "double-click", "long-click", "tap", "type", "key", "scroll", "drag", "screenshot", "settle")
        fun parse(source: String): DriveAction {
            val obj = try { Json.parseToJsonElement(source) as? JsonObject } catch (_: Exception) { null }
            requireNotNull(obj) { "invalid action JSON object" }
            fun primitive(key: String) = obj[key] as? JsonPrimitive
            fun string(key: String): String {
                val value = primitive(key)
                require(value?.isString == true) { "missing or invalid $key" }
                return value.content
            }
            fun integer(key: String, min: Long): Long {
                val value = primitive(key)
                val number = value?.takeUnless { it.isString }?.longOrNull
                require(number != null && number >= min) { "missing or invalid $key" }
                return number
            }
            require(string("drive") == "action") { "expected drive action" }
            require(integer("version", 1) == 1L) { "unsupported Drive version" }
            val request = integer("request", 1)
            val action = string("action")
            val extra = when (action) {
                "click", "double-click", "long-click" -> setOf("id")
                "type" -> setOf("id", "text")
                "key" -> setOf("combo")
                "tap" -> setOf("x", "y")
                "scroll" -> setOf("id", "dx", "dy")
                "drag" -> setOf("id", "target")
                "screenshot", "settle" -> emptySet()
                else -> throw IllegalArgumentException("unsupported native action: $action")
            }
            require(obj.keys == setOf("drive", "version", "request", "action") + extra) { "unexpected or missing action fields" }
            extra.forEach { key ->
                when (key) {
                    "id", "target" -> integer(key, 0)
                    "text", "combo" -> string(key)
                    else -> {
                        val value = primitive(key)
                        val number = value?.takeUnless { it.isString }?.doubleOrNull
                        require(number != null && number.isFinite() && number.toFloat().isFinite()) { "invalid $key" }
                    }
                }
            }
            return DriveAction(request, action, obj)
        }
    }
}
