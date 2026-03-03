// FocusTrap.js - Focus trap FFI
// Vendored from purescript-radix (straylight/purescript-radix)

export const isVisible = el => () => {
  if (!el) return false;
  const style = window.getComputedStyle(el);
  if (style.display === 'none' || style.visibility === 'hidden') return false;
  if (el.hidden) return false;
  const rect = el.getBoundingClientRect();
  return rect.width > 0 || rect.height > 0;
};

export const elementToHTMLElementImpl = node =>
  node && node.nodeType === 1 && node instanceof HTMLElement ? node : null;

export const refEq = a => b => a === b;
