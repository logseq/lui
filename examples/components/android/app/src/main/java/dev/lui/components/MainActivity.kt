package dev.lui.components

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Menu
import androidx.compose.material3.DrawerValue
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalDrawerSheet
import androidx.compose.material3.ModalNavigationDrawer
import androidx.compose.material3.NavigationDrawerItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.rememberDrawerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.unit.dp
import dev.lui.LuiBackend
import dev.lui.LuiBridge
import dev.lui.LuiNodeKind
import dev.lui.LuiTheme
import dev.lui.dispatchToBridge
import kotlinx.coroutines.launch

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
                        val rootId = remember { LuiBridge.rootNode() }
                        Gallery(backend, rootId)
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

private data class GalleryPage(val id: Long, val title: String)

private fun pageTitle(backend: LuiBackend, id: Long): String? {
    val node = backend.node(id) ?: return null
    if (node.kind == LuiNodeKind.heading || node.kind == LuiNodeKind.text) {
        node.properties["text"]?.stringValue?.takeIf { it.isNotEmpty() }?.let { return it }
    }
    return node.children.firstNotNullOfOrNull { pageTitle(backend, it) }
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalComposeUiApi::class)
@Composable
private fun Gallery(backend: LuiBackend, rootId: Long) {
    val root = backend.node(rootId)
    val pageRoot = if (root?.kind == LuiNodeKind.root) root.children.firstOrNull()?.let(backend::node) else root
    val pages = pageRoot?.children.orEmpty().map { id ->
        GalleryPage(id, pageTitle(backend, id) ?: "Component $id")
    }
    var selectedId by remember { mutableStateOf<Long?>(null) }
    val selected = pages.firstOrNull { it.id == selectedId }
        ?: pages.firstOrNull { it.title == "Row" } ?: pages.firstOrNull()
    val drawer = rememberDrawerState(DrawerValue.Closed)
    val scope = rememberCoroutineScope()
    ModalNavigationDrawer(
        drawerState = drawer,
        drawerContent = {
            ModalDrawerSheet {
                Text("Components", Modifier.padding(24.dp), style = MaterialTheme.typography.titleLarge)
                LazyColumn {
                    items(pages, key = { it.id }) { page ->
                        NavigationDrawerItem(
                            label = { Text(page.title) },
                            selected = page.id == selected?.id,
                            onClick = {
                                selectedId = page.id
                                scope.launch { drawer.close() }
                            },
                            modifier = Modifier.padding(horizontal = 12.dp)
                                .semantics { testTagsAsResourceId = true }
                                .testTag("component-row-${page.title}"),
                        )
                    }
                }
            }
        },
    ) {
        Scaffold(topBar = {
            TopAppBar(
                title = { Text(selected?.title ?: "Components") },
                navigationIcon = {
                    IconButton(onClick = { scope.launch { drawer.open() } }) {
                        Icon(Icons.Filled.Menu, contentDescription = "Open navigation menu")
                    }
                },
            )
        }) { padding ->
            selected?.let { page ->
                key(page.id) {
                    Box(Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState())) {
                        backend.Content(page.id)
                    }
                }
            }
        }
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
