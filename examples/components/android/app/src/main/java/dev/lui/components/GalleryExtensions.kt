package dev.lui.components

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import dev.lui.LuiExtensionProperty
import dev.lui.LuiExtensionRegistry
import dev.lui.LuiExtensionValueKind
import dev.lui.LuiSplit

/**
 * Gallery extension set for the Kotlin host: the LUI split components plus
 * the gallery's own native-card and gallery-accent declarations. The
 * fingerprint literals must equal the ones Lui_extension computes from
 * examples/gallery/extension_schemas.ml — the drift check in test_lui.ml
 * enforces the same invariant for the other hosts.
 */
object GalleryExtensions {

    private const val NATIVE_CARD_FINGERPRINT =
        "lui-extension-v1|10:native-card|profiles:android/kotlin,web/web|standard-children:0|children:|properties:5:title:string:required:none|events:"
    private const val GALLERY_ACCENT_FINGERPRINT =
        "lui-tweak-v1|14:gallery-accent|profiles:android/kotlin,ios/swiftui,linux/gpui,macos/gpui,macos/swiftui,web/web,windows/gpui|properties:"

    fun register(registry: LuiExtensionRegistry) {
        LuiSplit.register(registry)
        registry.register(
            identifier = "native-card",
            fingerprint = NATIVE_CARD_FINGERPRINT,
            properties = listOf(
                LuiExtensionProperty("title", LuiExtensionValueKind.STRING, required = true),
            ),
            builder = {
                Card(Modifier.fillMaxSize().padding(8.dp)) {
                    Column(Modifier.padding(16.dp)) {
                        Text(
                            string("title") ?: "",
                            style = MaterialTheme.typography.titleMedium,
                        )
                    }
                }
            },
        )
        registry.registerTweak(
            identifier = "gallery-accent",
            fingerprint = GALLERY_ACCENT_FINGERPRINT,
        ) {
            Column(Modifier.fillMaxSize()) {
                children.forEach { child(it) }
            }
        }
    }
}
