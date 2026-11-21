package org.opensource.tracker

import org.junit.Assert.assertEquals
import org.junit.Test
import org.opensource.tracker.ui.util.UnitFormat

class UnitFormatTest {
    @Test
    fun `metric values pass through`() {
        assertEquals("5.00 km", UnitFormat.distance(5.0, imperial = false))
        assertEquals("12.5 km/h", UnitFormat.speed(12.5, imperial = false))
        assertEquals("+120 m", UnitFormat.elevation(120.0, imperial = false))
        assertEquals("5:30", UnitFormat.pace("5:30", imperial = false))
    }

    @Test
    fun `imperial conversion`() {
        assertEquals("1.00 mi", UnitFormat.distance(1.609344, imperial = true))
        assertEquals("10.0 mph", UnitFormat.speed(16.09344, imperial = true))
        assertEquals("+328 ft", UnitFormat.elevation(100.0, imperial = true))
    }

    @Test
    fun `pace converts from per-km to per-mile`() {
        assertEquals("8:02", UnitFormat.pace("5:00", imperial = true))
        assertEquals("/mi", UnitFormat.paceUnit(imperial = true))
        assertEquals("/km", UnitFormat.paceUnit(imperial = false))
    }

    @Test
    fun `placeholder and malformed pace are left alone`() {
        assertEquals("--:--", UnitFormat.pace("--:--", imperial = true))
        assertEquals("abc", UnitFormat.pace("abc", imperial = true))
    }
}
