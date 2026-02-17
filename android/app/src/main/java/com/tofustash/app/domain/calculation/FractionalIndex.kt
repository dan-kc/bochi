package com.tofustash.app.domain.calculation

private const val DIGITS = "abcdefghijklmnopqrstuvwxyz"
private val BASE = DIGITS.length // 26

fun generateKeyBetween(before: String?, after: String?): String {
    if (before == null && after == null) return "m"
    if (before == null) return decrementKey(after!!)
    if (after == null) return incrementKey(before)
    require(before < after) { "Invalid order: before ($before) must be less than after ($after)" }
    return midpoint(before, after)
}

private fun decrementKey(key: String): String {
    for (i in key.length - 1 downTo 0) {
        val charIndex = DIGITS.indexOf(key[i])
        if (charIndex > 0) {
            return key.substring(0, i) +
                DIGITS[charIndex - 1] +
                DIGITS[BASE - 1].toString().repeat(key.length - i - 1)
        }
    }
    return DIGITS[BASE - 1] + key
}

private fun incrementKey(key: String): String {
    for (i in key.length - 1 downTo 0) {
        val charIndex = DIGITS.indexOf(key[i])
        if (charIndex < BASE - 1) {
            return key.substring(0, i) + DIGITS[charIndex + 1]
        }
    }
    return key + DIGITS[0]
}

private fun midpoint(before: String, after: String): String {
    val maxLen = maxOf(before.length, after.length)
    val beforePadded = before.padEnd(maxLen, DIGITS[0])
    val afterPadded = after.padEnd(maxLen, DIGITS[0])

    val result = StringBuilder()
    var foundDiff = false

    for (i in 0 until maxLen) {
        val beforeIndex = DIGITS.indexOf(beforePadded[i])
        val afterIndex = DIGITS.indexOf(afterPadded[i])

        if (!foundDiff) {
            when {
                beforeIndex == afterIndex -> result.append(DIGITS[beforeIndex])
                afterIndex - beforeIndex == 1 -> {
                    result.append(DIGITS[beforeIndex])
                    val remaining = midpointSuffix(
                        if (i + 1 < before.length) before.substring(i + 1) else "",
                    )
                    return result.toString() + remaining
                }
                else -> {
                    result.append(DIGITS[(beforeIndex + afterIndex) / 2])
                    foundDiff = true
                }
            }
        } else {
            result.append(DIGITS[0])
        }
    }

    if (!foundDiff) {
        result.append(DIGITS[BASE / 2])
    }

    return result.toString()
}

private fun midpointSuffix(beforeSuffix: String): String {
    if (beforeSuffix.isEmpty()) return DIGITS[BASE / 2].toString()

    val lastChar = beforeSuffix[beforeSuffix.length - 1]
    val lastIndex = DIGITS.indexOf(lastChar)

    return if (lastIndex < BASE - 1) {
        val midIndex = (lastIndex + BASE) / 2
        beforeSuffix.substring(0, beforeSuffix.length - 1) + DIGITS[midIndex]
    } else {
        beforeSuffix + DIGITS[BASE / 2]
    }
}
