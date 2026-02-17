package com.tofustash.app.domain.calculation

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class FractionalIndexTest {

    @Test
    fun firstKeyIsM() {
        assertEquals("m", generateKeyBetween(null, null))
    }

    @Test
    fun keyAfterMIsN() {
        val key = generateKeyBetween("m", null)
        assertTrue(key > "m")
    }

    @Test
    fun keyBeforeMIsL() {
        val key = generateKeyBetween(null, "m")
        assertTrue(key < "m")
    }

    @Test
    fun keyBetweenTwoKeysIsBetween() {
        val key = generateKeyBetween("b", "d")
        assertTrue(key > "b")
        assertTrue(key < "d")
    }

    @Test
    fun keyBetweenAdjacentKeysIsBetween() {
        val key = generateKeyBetween("a", "b")
        assertTrue(key > "a")
        assertTrue(key < "b")
    }

    @Test
    fun multipleInsertionsMaintainOrder() {
        val keys = mutableListOf<String>()
        keys.add(generateKeyBetween(null, null)) // first key

        // Insert 10 items after each other
        for (i in 0 until 10) {
            val newKey = generateKeyBetween(keys.last(), null)
            assertTrue("$newKey should be > ${keys.last()}", newKey > keys.last())
            keys.add(newKey)
        }

        // Verify all are in order
        for (i in 0 until keys.size - 1) {
            assertTrue("${keys[i]} should be < ${keys[i + 1]}", keys[i] < keys[i + 1])
        }
    }

    @Test
    fun insertionsBetweenExistingKeysMaintainOrder() {
        val a = generateKeyBetween(null, null)
        val c = generateKeyBetween(a, null)
        val b = generateKeyBetween(a, c)

        assertTrue(a < b)
        assertTrue(b < c)
    }

    @Test
    fun deeplyNestedInsertionsMaintainOrder() {
        var low = "a"
        var high = "b"

        // Insert many keys between a and b
        for (i in 0 until 20) {
            val mid = generateKeyBetween(low, high)
            assertTrue("$mid should be > $low", mid > low)
            assertTrue("$mid should be < $high", mid < high)
            high = mid // Keep narrowing from the right
        }
    }

    @Test
    fun prependMultipleKeys() {
        var first = generateKeyBetween(null, null)
        for (i in 0 until 10) {
            val newKey = generateKeyBetween(null, first)
            assertTrue("$newKey should be < $first", newKey < first)
            first = newKey
        }
    }

    @Test(expected = IllegalArgumentException::class)
    fun throwsWhenBeforeIsNotLessThanAfter() {
        generateKeyBetween("z", "a")
    }

    @Test(expected = IllegalArgumentException::class)
    fun throwsWhenBeforeEqualsAfter() {
        generateKeyBetween("m", "m")
    }
}
