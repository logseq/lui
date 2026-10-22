package dev.lui

import app.cash.paparazzi.DeviceConfig
import app.cash.paparazzi.Paparazzi
import org.junit.Rule
import org.junit.Test

class LuiRowStretchTest {
    @get:Rule val paparazzi = Paparazzi(deviceConfig = DeviceConfig.PIXEL_5.copy(softButtons = false))

    @Test fun tableDividersAndGrowingCellsMatchRowHeight() {
        val backend = LuiBackend()
        check(backend.applyBatch("""{"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"root"},
          {"op":"create-node","id":2,"kind":"row"},
          {"op":"insert-child","parent":1,"child":2,"index":0},
          {"op":"set-prop","id":2,"property":"cross","value":"stretch"},
          {"op":"create-node","id":3,"kind":"text"},
          {"op":"insert-child","parent":2,"child":3,"index":0},
          {"op":"set-prop","id":3,"property":"grow","value":1},
          {"op":"set-prop","id":3,"property":"min-height","value":48},
          {"op":"set-prop","id":3,"property":"text","value":"Name"},
          {"op":"set-prop","id":3,"property":"background","value":"secondary"},
          {"op":"create-node","id":4,"kind":"divider"},
          {"op":"insert-child","parent":2,"child":4,"index":1},
          {"op":"set-prop","id":4,"property":"orientation","value":"vertical"},
          {"op":"create-node","id":5,"kind":"text"},
          {"op":"insert-child","parent":2,"child":5,"index":2},
          {"op":"set-prop","id":5,"property":"width","value":170},
          {"op":"set-prop","id":5,"property":"height","value":96},
          {"op":"set-prop","id":5,"property":"text","value":"A taller value cell"},
          {"op":"set-prop","id":5,"property":"background","value":"secondary"}
        ]}""")) { backend.lastError.orEmpty() }
        paparazzi.snapshot(name = "stretched-table-row") { LuiTheme { backend.Content() } }
    }
}
