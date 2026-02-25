// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//                                                  // hydrogen // tour // storage
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

// | Foreign function implementations for Storage module

/**
 * Get current time in milliseconds since epoch
 * @returns {() => number} Effect returning timestamp
 */
export const currentTimeMs = () => Date.now();

/**
 * Convert Int to Number (JavaScript numbers are all doubles)
 * @param {number} n - Integer value
 * @returns {number} Same value as Number
 */
export const toNumberImpl = (n) => n;
