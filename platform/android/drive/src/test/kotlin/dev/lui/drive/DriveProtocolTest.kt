package dev.lui.drive

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class DriveProtocolTest {
    @Test fun strictV1ActionBoundary() {
        val prefix = "\"drive\":\"action\",\"version\":1,\"request\":1"
        listOf(
            "\"action\":\"click\",\"id\":37",
            "\"action\":\"double-click\",\"id\":37",
            "\"action\":\"long-click\",\"id\":37",
            "\"action\":\"tap\",\"x\":1.5,\"y\":0",
            "\"action\":\"type\",\"id\":37,\"text\":\"汉字😀\"",
            "\"action\":\"key\",\"combo\":\"ctrl+a\"",
            "\"action\":\"scroll\",\"id\":37,\"dx\":0,\"dy\":200",
            "\"action\":\"drag\",\"id\":37,\"target\":38",
            "\"action\":\"screenshot\"",
            "\"action\":\"settle\"",
        ).forEach { assertEquals(1L, DriveAction.parse("{$prefix,$it}").request) }
        listOf(
            "{$prefix,\"action\":\"click\",\"id\":\"37\"}",
            "{$prefix,\"action\":\"click\",\"id\":37.0}",
            "{$prefix,\"action\":\"click\",\"id\":-1}",
            "{$prefix,\"action\":\"tap\",\"x\":\"1\",\"y\":2}",
            "{$prefix,\"action\":\"tap\",\"x\":1e999,\"y\":2}",
            "{$prefix,\"action\":\"type\",\"id\":1,\"text\":true}",
            "{$prefix,\"action\":\"click\",\"id\":37,\"event\":\"press\"}",
            "{$prefix,\"action\":\"toggle\",\"id\":37}",
            "{$prefix,\"action\":\"drag\",\"id\":37}",
            "{\"drive\":\"action\",\"version\":2,\"request\":1,\"action\":\"settle\"}",
            "{\"drive\":\"action\",\"version\":1,\"request\":0,\"action\":\"settle\"}",
            "{\"drive\":\"action\",\"version\":\"1\",\"request\":1,\"action\":\"settle\"}",
        ).forEach { source ->
            assertThrows(source, IllegalArgumentException::class.java) { DriveAction.parse(source) }
        }
    }
}
