package dev.lui

import app.cash.paparazzi.DeviceConfig
import app.cash.paparazzi.Paparazzi
import org.junit.Rule
import org.junit.Test

/**
 * Screenshot coverage for the Kotlin backend's default theme (light AND
 * dark) at phone size. Trees are fed through the real wire path —
 * applyBatch on hand-written patch JSON — so the shots exercise the same
 * parse/store/render pipeline the gallery uses.
 */
class LuiScreenshotTest {

    @get:Rule
    val paparazzi = Paparazzi(
        deviceConfig = DeviceConfig.PIXEL_5.copy(softButtons = false),
    )

    private fun backendFor(vararg batches: String): LuiBackend {
        val backend = LuiBackend()
        batches.forEachIndexed { index, json ->
            check(backend.applyBatch(json)) { "batch $index rejected: ${backend.lastError}" }
        }
        return backend
    }

    private fun snapshot(name: String, backend: LuiBackend, dark: Boolean) {
        paparazzi.snapshot(name = name) {
            LuiTheme(dark = dark) {
                androidx.compose.material3.Surface(
                    color = androidx.compose.material3.MaterialTheme.colorScheme.background,
                ) {
                    backend.Content()
                }
            }
        }
    }

    private fun galleryScreen(dark: Boolean) {
        // A representative settings-style screen: toolbar, card with
        // controls, list items, and a bottom tab bar.
        val backend = backendFor(
            """
            {"generation":1,"ops":[
              {"op":"create-node","id":1,"kind":"root"},
              {"op":"create-node","id":2,"kind":"column"},
              {"op":"insert-child","parent":1,"child":2,"index":0},
              {"op":"set-prop","id":2,"property":"gap","value":16},
              {"op":"set-prop","id":2,"property":"padding","value":16},

              {"op":"create-node","id":3,"kind":"heading"},
              {"op":"insert-child","parent":2,"child":3,"index":0},
              {"op":"set-prop","id":3,"property":"text","value":"Components"},
              {"op":"set-prop","id":3,"property":"heading-level","value":3},

              {"op":"create-node","id":4,"kind":"card"},
              {"op":"insert-child","parent":2,"child":4,"index":1},
              {"op":"create-node","id":5,"kind":"column"},
              {"op":"insert-child","parent":4,"child":5,"index":0},
              {"op":"set-prop","id":5,"property":"gap","value":12},

              {"op":"create-node","id":6,"kind":"text"},
              {"op":"insert-child","parent":5,"child":6,"index":0},
              {"op":"set-prop","id":6,"property":"text",
               "value":"Polished Material 3 defaults — no per-app CSS."},

              {"op":"create-node","id":7,"kind":"row"},
              {"op":"insert-child","parent":5,"child":7,"index":1},
              {"op":"set-prop","id":7,"property":"gap","value":8},

              {"op":"create-node","id":8,"kind":"button"},
              {"op":"insert-child","parent":7,"child":8,"index":0},
              {"op":"set-prop","id":8,"property":"text","value":"Primary"},
              {"op":"set-prop","id":8,"property":"variant","value":"primary"},

              {"op":"create-node","id":9,"kind":"button"},
              {"op":"insert-child","parent":7,"child":9,"index":1},
              {"op":"set-prop","id":9,"property":"text","value":"Secondary"},
              {"op":"set-prop","id":9,"property":"variant","value":"secondary"},

              {"op":"create-node","id":10,"kind":"button"},
              {"op":"insert-child","parent":7,"child":10,"index":2},
              {"op":"set-prop","id":10,"property":"text","value":"Outline"},
              {"op":"set-prop","id":10,"property":"variant","value":"outline"},

              {"op":"create-node","id":11,"kind":"text-field"},
              {"op":"insert-child","parent":5,"child":11,"index":2},
              {"op":"set-prop","id":11,"property":"placeholder",
               "value":"Search components"},

              {"op":"create-node","id":12,"kind":"row"},
              {"op":"insert-child","parent":5,"child":12,"index":3},
              {"op":"set-prop","id":12,"property":"gap","value":16},
              {"op":"set-prop","id":12,"property":"main","value":"start"},

              {"op":"create-node","id":13,"kind":"switch"},
              {"op":"insert-child","parent":12,"child":13,"index":0},
              {"op":"set-prop","id":13,"property":"text","value":"Enabled"},
              {"op":"set-prop","id":13,"property":"checked","value":true},

              {"op":"create-node","id":14,"kind":"checkbox"},
              {"op":"insert-child","parent":12,"child":14,"index":1},
              {"op":"set-prop","id":14,"property":"text","value":"Remember"},

              {"op":"create-node","id":15,"kind":"slider"},
              {"op":"insert-child","parent":5,"child":15,"index":4},
              {"op":"set-prop","id":15,"property":"value","value":0.65},

              {"op":"create-node","id":16,"kind":"progress"},
              {"op":"insert-child","parent":5,"child":16,"index":5},
              {"op":"set-prop","id":16,"property":"value","value":0.4},

              {"op":"create-node","id":19,"kind":"list"},
              {"op":"insert-child","parent":2,"child":19,"index":2},
              {"op":"create-node","id":20,"kind":"list-section"},
              {"op":"insert-child","parent":19,"child":20,"index":0},
              {"op":"create-node","id":21,"kind":"list-item"},
              {"op":"insert-child","parent":20,"child":21,"index":0},
              {"op":"set-prop","id":21,"property":"text","value":"Inbox"},
              {"op":"set-prop","id":21,"property":"icon","value":"folder"},
              {"op":"set-prop","id":21,"property":"press-enabled","value":true},
              {"op":"create-node","id":22,"kind":"list-item"},
              {"op":"insert-child","parent":20,"child":22,"index":1},
              {"op":"set-prop","id":22,"property":"text","value":"Settings"},
              {"op":"set-prop","id":22,"property":"icon","value":"settings"},
              {"op":"set-prop","id":22,"property":"press-enabled","value":true},
              {"op":"create-node","id":24,"kind":"list-item"},
              {"op":"insert-child","parent":20,"child":24,"index":2},
              {"op":"set-prop","id":24,"property":"text","value":"About"},
              {"op":"set-prop","id":24,"property":"icon","value":"info"},
              {"op":"set-prop","id":24,"property":"press-enabled","value":true}
            ]}
            """.trimIndent(),
        )
        snapshot(if (dark) "gallery-dark" else "gallery-light", backend, dark)
    }

    @Test
    fun galleryLight() = galleryScreen(dark = false)

    @Test
    fun galleryDark() = galleryScreen(dark = true)

    private fun controlsScreen(dark: Boolean) {
        val backend = backendFor(
            """
            {"generation":1,"ops":[
              {"op":"create-node","id":1,"kind":"root"},
              {"op":"create-node","id":2,"kind":"column"},
              {"op":"insert-child","parent":1,"child":2,"index":0},
              {"op":"set-prop","id":2,"property":"gap","value":12},
              {"op":"set-prop","id":2,"property":"padding","value":16},

              {"op":"create-node","id":3,"kind":"tabs"},
              {"op":"insert-child","parent":2,"child":3,"index":0},
              {"op":"create-node","id":4,"kind":"button"},
              {"op":"insert-child","parent":3,"child":4,"index":0},
              {"op":"set-prop","id":4,"property":"text","value":"Feed"},
              {"op":"set-prop","id":4,"property":"selected","value":true},
              {"op":"create-node","id":5,"kind":"button"},
              {"op":"insert-child","parent":3,"child":5,"index":1},
              {"op":"set-prop","id":5,"property":"text","value":"Saved"},
              {"op":"create-node","id":6,"kind":"button"},
              {"op":"insert-child","parent":3,"child":6,"index":2},
              {"op":"set-prop","id":6,"property":"text","value":"Settings"},

              {"op":"create-node","id":7,"kind":"row"},
              {"op":"insert-child","parent":2,"child":7,"index":1},
              {"op":"set-prop","id":7,"property":"gap","value":12},

              {"op":"create-node","id":8,"kind":"avatar"},
              {"op":"insert-child","parent":7,"child":8,"index":0},
              {"op":"set-prop","id":8,"property":"text","value":"JD"},

              {"op":"create-node","id":9,"kind":"column"},
              {"op":"insert-child","parent":7,"child":9,"index":1},
              {"op":"set-prop","id":9,"property":"gap","value":2},
              {"op":"create-node","id":10,"kind":"text"},
              {"op":"insert-child","parent":9,"child":10,"index":0},
              {"op":"set-prop","id":10,"property":"text","value":"Jane Doe"},
              {"op":"create-node","id":11,"kind":"text"},
              {"op":"insert-child","parent":9,"child":11,"index":1},
              {"op":"set-prop","id":11,"property":"text",
               "value":"jane@example.com"},
              {"op":"set-prop","id":11,"property":"foreground",
               "value":"muted-foreground"},

              {"op":"create-node","id":13,"kind":"radio-group"},
              {"op":"insert-child","parent":2,"child":13,"index":2},
              {"op":"create-node","id":14,"kind":"radio"},
              {"op":"insert-child","parent":13,"child":14,"index":0},
              {"op":"set-prop","id":14,"property":"text","value":"Daily"},
              {"op":"set-prop","id":14,"property":"checked","value":true},
              {"op":"create-node","id":15,"kind":"radio"},
              {"op":"insert-child","parent":13,"child":15,"index":1},
              {"op":"set-prop","id":15,"property":"text","value":"Weekly"},

              {"op":"create-node","id":16,"kind":"alert"},
              {"op":"insert-child","parent":2,"child":16,"index":3},
              {"op":"set-prop","id":16,"property":"text","value":"Heads up"},
              {"op":"create-node","id":17,"kind":"text"},
              {"op":"insert-child","parent":16,"child":17,"index":0},
              {"op":"set-prop","id":17,"property":"text",
               "value":"Sync finished with 3 warnings."},

              {"op":"create-node","id":18,"kind":"accordion"},
              {"op":"insert-child","parent":2,"child":18,"index":4},
              {"op":"set-prop","id":18,"property":"text","value":"Advanced"},
              {"op":"set-prop","id":18,"property":"selected","value":true},
              {"op":"create-node","id":19,"kind":"text"},
              {"op":"insert-child","parent":18,"child":19,"index":0},
              {"op":"set-prop","id":19,"property":"text",
               "value":"Hidden details stay reachable."},

              {"op":"create-node","id":25,"kind":"stepper"},
              {"op":"insert-child","parent":2,"child":25,"index":5},
              {"op":"set-prop","id":25,"property":"active","value":1},
              {"op":"create-node","id":26,"kind":"step"},
              {"op":"insert-child","parent":25,"child":26,"index":0},
              {"op":"set-prop","id":26,"property":"text","value":"Account"},
              {"op":"create-node","id":27,"kind":"step"},
              {"op":"insert-child","parent":25,"child":27,"index":1},
              {"op":"set-prop","id":27,"property":"text","value":"Profile"},
              {"op":"create-node","id":28,"kind":"step"},
              {"op":"insert-child","parent":25,"child":28,"index":2},
              {"op":"set-prop","id":28,"property":"text","value":"Done"}
            ]}
            """.trimIndent(),
        )
        snapshot(if (dark) "controls-dark" else "controls-light", backend, dark)
    }

    @Test
    fun controlsLight() = controlsScreen(dark = false)

    @Test
    fun controlsDark() = controlsScreen(dark = true)
}
