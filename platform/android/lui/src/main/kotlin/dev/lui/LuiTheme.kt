package dev.lui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonPrimitive

/**
 * LUI default theme — the "默认好看" surface. Views are authored with
 * semantic tokens ("surface-container-high", "muted-foreground", "glass",
 * "accent", ...); this file maps them onto a Material 3 colorScheme with
 * carefully chosen defaults in both light and dark modes, mirroring
 * `LUIThemePolicy.swift` (Apple) and the Flutter backend's `_color` table
 * so all three hosts resolve the same token to an equivalent color.
 */

/** Semantic-color overrides inherited down the tree (`theme` prop). */
val LocalLuiSemanticColors = compositionLocalOf<Map<String, Color>> { emptyMap() }

/** Effective dark-mode flag inside the LUI tree (`theme-mode` prop, or a
 * host-provided override). Null means "not provided" — fall back to the
 * system setting. */
val LocalLuiThemeDark = compositionLocalOf<Boolean?> { null }

/** Hex resolver shared by color-name props and theme tokens. Accepts
 * `#rgb`, `#rgba`, `#rrggbb` and `#rrggbbaa` (CSS alpha-suffix).
 * Returns null for non-hex names. */
fun luiHexColor(name: String): Color? {
    var value = if (name.startsWith("#")) name.substring(1) else name
    if (value.length == 3 || value.length == 4) {
        value = value.map { "$it$it" }.joinToString("")
    }
    if (value.length == 6) value = "ff$value"
    if (value.length != 8) return null
    val rgba = value.toULongOrNull(16) ?: return null
    // CSS hex is #rrggbbaa; Color() takes ARGB.
    val argb = ((rgba and 0xffUL) shl 24) or (rgba shr 8)
    return Color(argb.toLong())
}

/** Resolves a semantic color name against the inherited token table then
 * the Material 3 scheme, mirroring the Flutter `_color` mapping so both
 * mobile hosts agree. [foreground] picks the "on-*" variant for pair
 * tokens like `accent`/`secondary`/`warning`/`success`/`error`. */
@Composable
fun luiThemeColor(name: String?, foreground: Boolean = false): Color? {
    if (name == null) return null
    val lower = name.lowercase()
    LocalLuiSemanticColors.current[lower]?.let { return it }
    val scheme = MaterialTheme.colorScheme
    return when (lower) {
        "transparent" -> Color.Transparent
        "background" -> scheme.surface
        "foreground" -> scheme.onSurface
        "surface" -> scheme.surface
        "surface-container-lowest" -> scheme.surfaceContainerLowest
        "surface-container-low" -> scheme.surfaceContainerLow
        "surface-container" -> scheme.surfaceContainer
        "surface-container-high" -> scheme.surfaceContainerHigh
        "surface-container-highest" -> scheme.surfaceContainerHighest
        "surface-variant" -> scheme.surfaceContainerHighest
        "autocomplete-row-background" -> scheme.surfaceContainerHigh
        "glass" -> scheme.surface.copy(alpha = 0.75f)
        "glass-fallback" -> scheme.surface.copy(alpha = 0.9f)
        // Apple Material.bar approximation: mostly-opaque theme surface.
        "bar" -> scheme.surface.copy(alpha = 0.85f)
        "primary" -> scheme.primary
        "primary-foreground" -> scheme.onPrimary
        "accent" -> if (foreground) scheme.primary else scheme.secondaryContainer
        "accent-foreground" ->
            if (foreground) scheme.onPrimary else scheme.onSecondaryContainer
        "secondary" ->
            if (foreground) scheme.onSurfaceVariant else scheme.secondaryContainer
        "secondary-foreground" -> scheme.onSecondaryContainer
        "muted" -> scheme.surfaceContainerHigh
        "muted-foreground" -> scheme.onSurfaceVariant
        "destructive" -> scheme.error
        "destructive-foreground" -> scheme.onError
        "success" -> scheme.tertiaryContainer
        "success-foreground" -> scheme.onTertiaryContainer
        "warning" -> scheme.secondaryContainer
        "warning-foreground" -> scheme.onSecondaryContainer
        "error" -> scheme.errorContainer
        "error-foreground" -> scheme.onErrorContainer
        "border" -> scheme.outlineVariant
        "black" -> Color.Black
        "white" -> Color.White
        "red" -> Color(0xFFB3261E)
        "blue" -> Color(0xFF0061A4)
        "green" -> Color(0xFF2E7D32)
        else -> luiHexColor(lower) ?: Color.Transparent
    }
}

/** LUI's Material 3 defaults. The stock schemes already carry the M3
 * baseline palette (primary #6750A4 — the same accent the web backend
 * uses for `data-lui-platform="android"`), so the defaults are genuinely
 * Material-3 quality with no per-app tuning. Hosts can pass their own
 * schemes to [LuiTheme]. */
object LuiThemeDefaults {
    fun lightScheme(): ColorScheme = lightColorScheme()
    fun darkScheme(): ColorScheme = darkColorScheme()
}

/**
 * Applies the LUI theme: a Material 3 `MaterialTheme` plus the semantic
 * token CompositionLocals LUI renderers resolve through. [dark] selects
 * the scheme (`null` follows the system); [semanticColors] are merged
 * over inherited tokens; [light]/[darkScheme] let a host override the
 * base palette.
 */
@Composable
fun LuiTheme(
    dark: Boolean? = null,
    semanticColors: Map<String, Color> = emptyMap(),
    light: ColorScheme = LuiThemeDefaults.lightScheme(),
    darkScheme: ColorScheme = LuiThemeDefaults.darkScheme(),
    content: @Composable () -> Unit,
) {
    // An explicit [dark] wins, then an app-provided local, then the system.
    val effectiveDark = dark ?: LocalLuiThemeDark.current ?: isSystemInDarkTheme()
    MaterialTheme(colorScheme = if (effectiveDark) darkScheme else light) {
        val inherited = LocalLuiSemanticColors.current
        CompositionLocalProvider(
            LocalLuiThemeDark provides effectiveDark,
            LocalLuiSemanticColors provides inherited + semanticColors,
        ) {
            content()
        }
    }
}

object LuiThemeTokenDecoder {
    private val json = Json { ignoreUnknownKeys = true }

    /** Parses the `theme` wire prop into semantic-color entries consulted
     * before platform defaults. A token value is either a color string
     * used in both modes or a `{"light": ..., "dark": ...}` object picked
     * by [dark]. Entries that do not decode to a color are ignored so
     * non-color tokens can join the table later without breaking hosts. */
    fun colors(jsonSource: String?, dark: Boolean): Map<String, Color> {
        if (jsonSource.isNullOrEmpty()) return emptyMap()
        val obj = try {
            json.parseToJsonElement(jsonSource) as? JsonObject
        } catch (_: Exception) {
            null
        } ?: return emptyMap()
        val colors = mutableMapOf<String, Color>()
        for ((key, element) in obj) {
            val raw = when {
                element is kotlinx.serialization.json.JsonPrimitive && element.isString ->
                    element.content
                element is JsonObject ->
                    element[if (dark) "dark" else "light"]?.jsonPrimitive?.content
                else -> null
            } ?: continue
            val color = luiHexColor(raw) ?: continue
            colors[key.lowercase()] = color
        }
        return colors
    }

    fun colorScheme(value: String?): Boolean? = when (value) {
        "dark" -> true
        "light" -> false
        else -> null
    }
}

object LuiTypography {
    @Composable
    fun headingStyle(level: Int): TextStyle {
        val theme = MaterialTheme.typography
        return when (level) {
            1 -> theme.headlineLarge
            2 -> theme.headlineMedium
            3 -> theme.titleLarge
            4 -> theme.titleMedium
            5 -> theme.titleSmall
            else -> theme.labelLarge
        }
    }

    @Composable
    fun textStyleForSize(size: String?): TextStyle {
        val theme = MaterialTheme.typography
        return when (size) {
            "sm" -> theme.bodySmall
            "lg" -> theme.titleMedium
            "heading" -> theme.headlineSmall
            "display" -> theme.displaySmall
            else -> theme.bodyMedium
        }
    }

    /**
     * Mirrors the Apple backend's `LUITextView.font`: `style-class` tokens
     * pick the text style (title2/headline/subheadline/caption/footnote),
     * headline and subheadline render semibold, `semibold` forces it, and
     * `mono` switches to a monospaced family. `size` remains the base
     * mapping when no style-class token matches.
     */
    @Composable
    fun textStyle(size: String?, styleClass: String?): TextStyle {
        val theme = MaterialTheme.typography
        val classes = styleClass?.split(' ') ?: emptyList()
        var style: TextStyle = when {
            classes.contains("title2") -> theme.titleLarge
            classes.contains("headline") -> theme.bodyLarge
            classes.contains("subheadline") -> theme.bodyMedium
            classes.contains("caption") -> theme.bodySmall
            classes.contains("footnote") -> theme.labelMedium
            else -> textStyleForSize(size)
        }
        if (classes.contains("semibold") ||
            classes.contains("headline") ||
            classes.contains("subheadline")
        ) {
            style = style.copy(fontWeight = FontWeight.SemiBold)
        }
        if (classes.contains("mono")) {
            style = style.copy(fontFamily = FontFamily.Monospace)
        }
        return style
    }
}
