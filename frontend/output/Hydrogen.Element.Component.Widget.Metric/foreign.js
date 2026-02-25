// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//                                    // hydrogen // element // widget // metric
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

// FFI implementations for Metric widget helpers.
// These are minimal, deterministic functions for number/array operations.

"use strict";

// Truncate positive number to integer (floor).
// Invariant: n >= 0
export const truncatePositive = (n) => Math.floor(n);

// Convert Int to Number (identity in JS, but distinct types in PureScript).
export const toNumber = (n) => n;

// Get string length.
export const stringLength = (s) => s.length;

// Fold over array with accumulator.
// foldl :: (b -> a -> b) -> b -> Array a -> b
export const arrayFold = (f) => (init) => (arr) => {
  let acc = init;
  for (let i = 0; i < arr.length; i++) {
    acc = f(acc)(arr[i]);
  }
  return acc;
};
