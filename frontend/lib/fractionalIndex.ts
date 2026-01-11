/**
 * Fractional Indexing Utility
 *
 * Generates lexicographically ordered strings that can always have
 * new strings inserted between any two existing strings.
 *
 * Based on the fractional indexing algorithm.
 * See: https://www.figma.com/blog/realtime-editing-of-ordered-sequences/
 */

const DIGITS = 'abcdefghijklmnopqrstuvwxyz';
const BASE = DIGITS.length; // 26

/**
 * Generate a key between two optional existing keys.
 *
 * @param before - The key that should come before the new key (or null for start)
 * @param after - The key that should come after the new key (or null for end)
 * @returns A new key that sorts between before and after
 */
export function generateKeyBetween(
  before: string | null,
  after: string | null
): string {
  // Handle edge cases
  if (before === null && after === null) {
    return 'm'; // First item - middle of the alphabet
  }

  if (before === null) {
    // Insert before the first item
    return decrementKey(after!);
  }

  if (after === null) {
    // Insert after the last item
    return incrementKey(before);
  }

  // Validate ordering
  if (before >= after) {
    throw new Error(`Invalid order: before (${before}) must be less than after (${after})`);
  }

  // Find midpoint between before and after
  return midpoint(before, after);
}

/**
 * Generate a key that comes before the given key.
 */
function decrementKey(key: string): string {
  // Find the rightmost character we can decrement
  for (let i = key.length - 1; i >= 0; i--) {
    const charIndex = DIGITS.indexOf(key[i]);
    if (charIndex > 0) {
      // Decrement this character and set all following to max
      return key.slice(0, i) + DIGITS[charIndex - 1] + DIGITS[BASE - 1].repeat(key.length - i - 1);
    }
  }
  // All characters are at minimum, prepend a character before '0'
  // Use 'Z' (one before 'a' in our ordering since capitals come before lowercase)
  return DIGITS[BASE - 1] + key;
}

/**
 * Generate a key that comes after the given key.
 */
function incrementKey(key: string): string {
  // Find the rightmost character we can increment
  for (let i = key.length - 1; i >= 0; i--) {
    const charIndex = DIGITS.indexOf(key[i]);
    if (charIndex < BASE - 1) {
      // Increment this character
      return key.slice(0, i) + DIGITS[charIndex + 1];
    }
  }
  // All characters are at maximum, append '0'
  return key + DIGITS[0];
}

/**
 * Find the midpoint between two keys.
 */
function midpoint(before: string, after: string): string {
  // Pad keys to same length for comparison
  const maxLen = Math.max(before.length, after.length);
  const beforePadded = before.padEnd(maxLen, DIGITS[0]);
  const afterPadded = after.padEnd(maxLen, DIGITS[0]);

  // Convert to numbers for each position and find midpoint
  let result = '';
  let foundDiff = false;

  for (let i = 0; i < maxLen; i++) {
    const beforeIndex = DIGITS.indexOf(beforePadded[i]);
    const afterIndex = DIGITS.indexOf(afterPadded[i]);

    if (!foundDiff) {
      if (beforeIndex === afterIndex) {
        result += DIGITS[beforeIndex];
      } else if (afterIndex - beforeIndex === 1) {
        // Adjacent characters - need to go deeper
        result += DIGITS[beforeIndex];
        // Continue with before's remaining chars vs "highest" value
        const remaining = midpointSuffix(before.slice(i + 1), after.slice(i + 1));
        return result + remaining;
      } else {
        // Gap exists - take middle
        const midIndex = Math.floor((beforeIndex + afterIndex) / 2);
        result += DIGITS[midIndex];
        foundDiff = true;
      }
    } else {
      // After finding difference, just use minimum
      result += DIGITS[0];
    }
  }

  // If we get here without finding a midpoint, append a middle character
  if (!foundDiff) {
    result += DIGITS[Math.floor(BASE / 2)];
  }

  return result;
}

/**
 * Find midpoint suffix when the main characters are adjacent.
 */
function midpointSuffix(beforeSuffix: string, afterSuffix: string): string {
  // We need to find something between beforeSuffix and the "infinity" represented by afterSuffix
  // Starting fresh with before and computing increment
  if (beforeSuffix === '') {
    // Return middle of the alphabet
    return DIGITS[Math.floor(BASE / 2)];
  }

  // Try to find midpoint between beforeSuffix and max possible value
  const lastChar = beforeSuffix[beforeSuffix.length - 1];
  const lastIndex = DIGITS.indexOf(lastChar);

  if (lastIndex < BASE - 1) {
    // Can increment last character and add middle
    const midIndex = Math.floor((lastIndex + BASE) / 2);
    return beforeSuffix.slice(0, -1) + DIGITS[midIndex];
  }

  // Need to go deeper
  return beforeSuffix + DIGITS[Math.floor(BASE / 2)];
}
