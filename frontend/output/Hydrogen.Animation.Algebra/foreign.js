// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Hydrogen.Animation.Algebra — FFI
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//
// Minimal FFI for pure math functions.
// These are the ONLY escape hatches to JavaScript.
//
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

export const nativeLog = (x) => Math.log(x);
export const nativeExp = (x) => Math.exp(x);
export const nativeSqrt = (x) => Math.sqrt(x);
export const nativeSin = (x) => Math.sin(x);
export const nativeCos = (x) => Math.cos(x);
export const nativeFloor = (x) => Math.floor(x);
