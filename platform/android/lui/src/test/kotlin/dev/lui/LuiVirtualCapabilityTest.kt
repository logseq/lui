package dev.lui

import org.junit.Assert.assertEquals
import org.junit.Test

class LuiVirtualCapabilityTest {
    @Test fun `capability preserves Kotlin profile and older JNI remains eager`() {
        assertEquals(260, luiVirtualHostCode(4) { 1 })
        assertEquals(4, luiVirtualHostCode(4) { 0 })
        assertEquals(4, luiVirtualHostCode(4) { 2 })
        assertEquals(4, luiVirtualHostCode(4) { throw UnsatisfiedLinkError("old JNI") })
        assertEquals(0, luiVirtualHostCode(0) { error("must not probe another host") })
        assertEquals(2, luiVirtualHostCode(2) { error("must not probe another host") })
    }
}
