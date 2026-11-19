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
            assertEquals(scheme.onSecondaryContainer, resolveLuiThemeColor("accent", true, emptyMap(), scheme))
            assertEquals(scheme.onPrimary, resolveLuiThemeColor("accent-foreground", true, emptyMap(), scheme))
            assertEquals(Color.Red, resolveLuiThemeColor("secondary", true, mapOf("secondary-foreground" to Color.Red), scheme))
            assertEquals(Color.Transparent, resolveLuiThemeColor("transparent", false, emptyMap(), scheme))
            assertEquals(Color.Transparent, resolveLuiThemeColor("unknown", false, emptyMap(), scheme))
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
