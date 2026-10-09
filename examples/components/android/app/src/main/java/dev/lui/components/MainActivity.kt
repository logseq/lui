package dev.lui.components

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import dev.lui.LuiBackend
import dev.lui.LuiBridge
import dev.lui.LuiTheme
import dev.lui.dispatchToBridge

/**
 * Components-gallery host: starts the OCaml runtime through [LuiBridge],
 * applies each delivered patch batch to [LuiBackend], and renders the
 * retained tree. When the OCaml toolchain .so was absent at build time the
 * bridge is a stub (start returns false) and a placeholder is shown.
 */
class MainActivity : ComponentActivity() {

    private val backend = LuiBackend(
        onEvent = { event -> event.dispatchToBridge() }
    )

    private var runtimeStarted = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        GalleryExtensions.register(backend.extensions)

        runtimeStarted = runCatching {
            LuiBridge.start(libraryName = "lui_jni_bridge", backend = backend)
        }.getOrDefault(false)

        setContent {
            LuiTheme(dark = isSystemInDarkTheme()) {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.background,
                ) {
                    if (runtimeStarted) {
                        backend.Content()
                    } else {
                        RuntimeUnavailable()
                    }
                }
            }
        }
    }

    override fun onDestroy() {
        if (runtimeStarted) {
            LuiBridge.stop()
        }
        super.onDestroy()
    }
}

@Composable
private fun RuntimeUnavailable() {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            modifier = Modifier.padding(32.dp),
        ) {
            Text(
                "LUI runtime unavailable",
                style = MaterialTheme.typography.titleMedium,
            )
            Text(
                "liblui_components.so was not built for this ABI — run " +
                    "tooling/mobile/build_components_android.sh with the lg " +
                    "Android OCaml toolchain, then rebuild.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 8.dp),
            )
        }
    }
}
