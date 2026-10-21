package dev.lui

import android.graphics.Typeface
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.MaterialExpressiveTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.remember
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
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

/** Typography overrides inherited down the tree — the `font-*`,
 * `line-height`, `letter-spacing` and `text-decoration` props, mirroring
 * the CSS-typed web props. Carried as a `TextStyle` delta: unspecified
 * fields leave the base style untouched under `TextStyle.merge`. */
val LocalLuiTypography = compositionLocalOf { TextStyle() }

/** Applies the inherited typography delta over [this]. Leaf renderers
 * that pass an explicit `style` to `Text` bypass `LocalTextStyle`, so
 * they merge the delta here. */
@Composable
fun TextStyle.luiInherited(): TextStyle = merge(LocalLuiTypography.current)

/** Hex resolver shared by color-name props and theme tokens. Accepts
 * `#rgb`, `#rgba`, `#rrggbb` and `#rrggbbaa` (CSS alpha-suffix).
 * Returns null for non-hex names. */
fun luiHexColor(name: String): Color? {
    var value = if (name.startsWith("#")) name.substring(1) else name
    if (value.length == 3 || value.length == 4) {
        value = value.map { "$it$it" }.joinToString("")
    }
    if (value.length == 6) {
        return value.toLongOrNull(16)?.let { Color(0xff000000L or it) }
    }
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
    val tokens = LocalLuiSemanticColors.current
    val scheme = MaterialTheme.colorScheme
    // Cache the lowercasing + table lookup + hex parse per name against
    // the token table and scheme it resolved under.
    return remember(name, foreground, tokens, scheme) {
        resolveLuiThemeColor(name.lowercase(), foreground, tokens, scheme)
    }
}

private fun resolveLuiThemeColor(
    lower: String,
    foreground: Boolean,
    tokens: Map<String, Color>,
    scheme: ColorScheme,
): Color? {
    tokens[lower]?.let { return it }
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
        "glass", "glass-fallback" -> scheme.surfaceContainerHigh
        "bar" -> scheme.surfaceContainer
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
        // iOS maps these to SwiftUI .green/.orange at 15% container opacity
        // (LUIThemePolicy); Material container roles read as dark neutrals.
        "success" -> Color(0xFF34C759).copy(alpha = 0.15f)
        "success-foreground" -> Color(0xFF34C759)
        "warning" -> Color(0xFFFF9500).copy(alpha = 0.15f)
        "warning-foreground" -> Color(0xFFFF9500)
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
    MaterialExpressiveTheme(colorScheme = if (effectiveDark) darkScheme else light) {
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
    private val cssLength = Regex("^\\s*([+-]?\\d*\\.?\\d+)(px|pt|sp|em|rem)?\\s*$")

    /** Wire props consumed by [nodeSpec]; used to skip the decode for
     * nodes that carry none of them. */
    internal val propNames = setOf(
        "font-size", "font-weight", "font-style", "line-height",
        "letter-spacing", "font-family", "text-decoration",
    )

    /** Resolve relative sizes against inherited and Material body typography. */
    private fun fontSizeSpec(value: String?, inheritedSize: TextUnit, rootSize: TextUnit): TextUnit? =
        cssLength.matchEntire(value ?: return null)?.let { m ->
            val amount = m.groupValues[1].toFloatOrNull() ?: return null
            when (m.groupValues[2]) {
                "em" -> inheritedSize * amount
                "rem" -> rootSize * amount
                else -> amount.sp
            }
        }

    /** CSS `line-height`: a unitless value is the multiplier (em);
     * lengths resolve to sp. */
    private fun lineHeightSpec(value: String?): TextUnit? =
        cssLength.matchEntire(value ?: return null)?.let { m ->
            val amount = m.groupValues[1].toFloatOrNull() ?: return null
            when (m.groupValues[2]) {
                "", "em", "rem" -> amount.em
                else -> amount.sp
            }
        }

    /** First family in the CSS list wins; generic keywords map to the
     * Compose defaults, named families resolve through `Typeface`. */
    private fun familySpec(value: String?): FontFamily? {
        val name = (value ?: return null)
            .split(',').firstOrNull()
            ?.trim()?.trim('"', '\'')
            ?.takeIf { it.isNotEmpty() } ?: return null
        return when (name.lowercase()) {
            "system-ui", "-apple-system", "sans-serif", "ui-sans-serif" ->
                FontFamily.Default
            "serif", "ui-serif" -> FontFamily.Serif
            "monospace", "ui-monospace" -> FontFamily.Monospace
            "cursive" -> FontFamily.Cursive
            else -> FontFamily(Typeface.create(name, Typeface.NORMAL))
        }
    }

    private fun decorationSpec(value: String?): TextDecoration? {
        val tokens = (value ?: return null).split(' ').filter { it.isNotBlank() }
        if (tokens == listOf("none")) return TextDecoration.None
        val decorations = tokens.mapNotNull {
            when (it) {
                "underline" -> TextDecoration.Underline
                "line-through" -> TextDecoration.LineThrough
                else -> null
            }
        }
        return decorations.takeIf { it.isNotEmpty() }?.let(TextDecoration::combine)
    }

    /** Typography delta contributed by a node's own props, merged over
     * the inherited spec in `LuiThemeScope`. Null when the node sets no
     * typography props. */
    fun nodeSpec(
        properties: Map<String, LuiWireValue>,
        inheritedSize: TextUnit = 16.sp,
        rootSize: TextUnit = 16.sp,
    ): TextStyle? {
        val size = fontSizeSpec(properties["font-size"]?.stringValue, inheritedSize, rootSize)
        val lineHeight = lineHeightSpec(properties["line-height"]?.stringValue)
        val weight = properties["font-weight"]?.intValue
            ?.let { FontWeight(it.coerceIn(1, 1000)) }
        val style = when (properties["font-style"]?.stringValue) {
            "italic", "oblique" -> FontStyle.Italic
            else -> null
        }
        val family = familySpec(properties["font-family"]?.stringValue)
        val tracking = properties["letter-spacing"]?.numberValue?.toFloat()?.sp
        val decoration = decorationSpec(properties["text-decoration"]?.stringValue)
        if (size == null && lineHeight == null && weight == null &&
            style == null && family == null && tracking == null &&
            decoration == null
        ) {
            return null
        }
        return TextStyle(
            fontSize = size ?: TextUnit.Unspecified,
            fontWeight = weight,
            fontStyle = style,
            fontFamily = family,
            letterSpacing = tracking ?: TextUnit.Unspecified,
            lineHeight = lineHeight ?: TextUnit.Unspecified,
            textDecoration = decoration,
        )
    }

    @Composable
    fun headingStyle(level: Int): TextStyle {
        val theme = MaterialTheme.typography
        return when (level) {
            1 -> theme.headlineLarge
            2 -> theme.headlineMedium
            3 -> theme.headlineSmall
            4 -> theme.titleLarge
            5 -> theme.titleMedium
            else -> theme.titleSmall
        }.luiInherited()
    }

    @Composable
    fun textStyleForSize(size: String?): TextStyle {
        val theme = MaterialTheme.typography
        return when (size) {
            "sm" -> theme.bodySmall
            "lg" -> theme.titleLarge
            "heading" -> theme.headlineSmall
            "display" -> theme.displaySmall
            else -> theme.bodyLarge
        }
    }

    /**
     * Maps shared semantic style names to Material typography roles.
     * Explicit typography props are merged afterward, so hosts can customize
     * their theme without an implicit Apple point-size override.
     */
    @Composable
    fun textStyle(size: String?, styleClass: String?): TextStyle {
        val theme = MaterialTheme.typography
        val classes = styleClass?.split(' ') ?: emptyList()
        var style: TextStyle = when {
            classes.contains("title2") -> theme.titleLarge
            classes.contains("headline") -> theme.titleMedium
            classes.contains("subheadline") -> theme.bodyMedium
            classes.contains("caption") -> theme.bodySmall
            classes.contains("footnote") -> theme.labelMedium
            else -> textStyleForSize(size)
        }
        if (classes.contains("semibold")) {
            style = style.copy(fontWeight = FontWeight.SemiBold)
        }
        if (classes.contains("mono")) {
            style = style.copy(fontFamily = FontFamily.Monospace)
        }
        return style.luiInherited()
    }
}
