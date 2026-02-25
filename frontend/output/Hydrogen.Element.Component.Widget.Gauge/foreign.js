// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//                                     // hydrogen // element // widget // gauge
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

// FFI implementations for Gauge widget helpers.

"use strict";

// Cosine function.
export const cos = (x) => Math.cos(x);

// Sine function.
export const sin = (x) => Math.sin(x);

// Truncate to integer.
export const truncate = (n) => Math.trunc(n);

// Convert Int to Number (identity in JS).
export const toNumber = (n) => n;
