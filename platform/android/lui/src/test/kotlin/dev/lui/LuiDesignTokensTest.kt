package dev.lui

import androidx.compose.ui.graphics.Color
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class LuiDesignTokensTest {
    @Test fun canonicalColorsResolveInBothModes() {
        val names = listOf("background", "surface", "surface-raised", "card", "foreground",
            "muted-foreground", "primary", "secondary", "accent", "muted", "destructive",
            "warning", "success", "info", "border", "input", "ring", "glass", "bar")
        for (scheme in listOf(LuiThemeDefaults.lightScheme(), LuiThemeDefaults.darkScheme())) {
            for (name in names) {
                assertNotEquals(name, Color.Transparent, resolveLuiThemeColor(name, false, emptyMap(), scheme))
                assertNotEquals(name, Color.Transparent, resolveLuiThemeColor(name, true, emptyMap(), scheme))
            }
            assertEquals(scheme.onSecondaryContainer, resolveLuiThemeColor("secondary", true, emptyMap(), scheme))
            assertEquals(scheme.secondaryContainer, resolveLuiThemeColor("secondary", false, emptyMap(), scheme))
            assertEquals(scheme.primary, resolveLuiThemeColor("accent", true, emptyMap(), scheme))
            assertEquals(scheme.onPrimary, resolveLuiThemeColor("accent-foreground", true, emptyMap(), scheme))
            assertEquals(Color.Red, resolveLuiThemeColor("secondary", true, mapOf("secondary-foreground" to Color.Red), scheme))
            assertEquals(Color.Transparent, resolveLuiThemeColor("transparent", false, emptyMap(), scheme))
            assertEquals(Color.Transparent, resolveLuiThemeColor("unknown", false, emptyMap(), scheme))
        }
    }

    @Test fun accentInkIsNotReplacedByContainerContentColors() {
        for (scheme in listOf(LuiThemeDefaults.lightScheme(), LuiThemeDefaults.darkScheme())) {
            assertEquals(scheme.primary, resolveLuiThemeColor("primary", true, emptyMap(), scheme))
            assertEquals(scheme.primary, resolveLuiThemeColor("accent", true, emptyMap(), scheme))
            assertEquals(scheme.primary, resolveLuiThemeColor("primary", false, emptyMap(), scheme))
            assertEquals(scheme.secondaryContainer, resolveLuiThemeColor("accent", false, emptyMap(), scheme))
            val tokens = mapOf("primary" to Color.Red, "primary-foreground" to Color.White,
                "accent" to Color.Blue, "accent-foreground" to Color.Yellow)
            assertEquals(Color.Red, resolveLuiThemeColor("primary", true, tokens, scheme))
            assertEquals(Color.Blue, resolveLuiThemeColor("accent", true, tokens, scheme))
            assertEquals(Color.White, resolveLuiThemeColor("primary-foreground", true, tokens, scheme))
            assertEquals(Color.Yellow, resolveLuiThemeColor("accent-foreground", true, tokens, scheme))
        }
    }

    @Test fun singleLineIsAnExactClassToken() {
        assertTrue(LuiTypography.singleLine("caption single-line semibold"))
        assertFalse(LuiTypography.singleLine(null))
        assertFalse(LuiTypography.singleLine(""))
        assertFalse(LuiTypography.singleLine("not-single-line"))
        assertEquals(0, luiSpaceTokens["none"])
        assertEquals(9999, luiRadiusTokens["full"])
    }
}
