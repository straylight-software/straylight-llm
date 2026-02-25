// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//                                                 // hydrogen // tour // highlight
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

// FFI implementations for Tour Highlight module

export const toNumber = (n) => n;

export const foldlImpl = (f) => (init) => (arr) => {
  let acc = init;
  for (let i = 0; i < arr.length; i++) {
    acc = f(acc)(arr[i]);
  }
  return acc;
};
