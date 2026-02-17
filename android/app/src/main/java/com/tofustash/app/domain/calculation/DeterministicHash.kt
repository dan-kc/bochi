package com.tofustash.app.domain.calculation

/**
 * MurmurHash3-inspired deterministic hash function.
 * Returns a value between 0.0 and 1.0.
 *
 * Must produce identical results to the TypeScript implementation
 * to ensure cross-platform price/reward consistency.
 */
internal fun deterministicHash(input: String): Double {
    var h1 = 0xDEADBEEF.toInt() // -559038737 signed
    var h2 = 0x41C6CE57

    for (char in input) {
        val c = char.code
        h1 = (h1 xor c) * 0x9E3779B1.toInt() // 2654435761 → -1640531535 signed
        h2 = (h2 xor c) * 1597334677
    }

    // Final mixing for avalanche effect
    h1 = (h1 xor (h1 ushr 16)) * 0x85EBCA6B.toInt() // 2246822507
    h1 = (h1 xor (h1 ushr 13)) * 0xC2B2AE35.toInt() // 3266489909
    h1 = h1 xor (h1 ushr 16)

    h2 = (h2 xor (h2 ushr 16)) * 0x85EBCA6B.toInt()
    h2 = (h2 xor (h2 ushr 13)) * 0xC2B2AE35.toInt()
    h2 = h2 xor (h2 ushr 16)

    // Combine and convert to 0-1 range (unsigned interpretation)
    val combined = (h1 xor h2).toUInt()
    return combined.toDouble() / 0xFFFFFFFFu.toDouble()
}

/** Time bucket size: 30 minutes in milliseconds */
private const val TIME_BUCKET_MS = 30L * 60 * 1000

/** Get the time bucket (30-minute interval since epoch) for a given timestamp. */
fun getTimeBucket(timestampMs: Long = System.currentTimeMillis()): Long =
    timestampMs / TIME_BUCKET_MS
