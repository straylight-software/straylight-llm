// Dialog.js - Scroll lock FFI
// Vendored from purescript-radix (straylight/purescript-radix)

let originalOverflow = null;
let lockCount = 0;

export const lockBodyScroll = () => {
  if (++lockCount === 1) {
    originalOverflow = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
  }
};

export const restoreBodyScroll = () => {
  if (--lockCount === 0 && originalOverflow !== null) {
    document.body.style.overflow = originalOverflow;
    originalOverflow = null;
  }
  lockCount = Math.max(0, lockCount);
};
