// Tabs.js - getElementById FFI
// Vendored from purescript-radix (straylight/purescript-radix)

export const getElementByIdImpl = id => doc => () => doc.getElementById(id);
