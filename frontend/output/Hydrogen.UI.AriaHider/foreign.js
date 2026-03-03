// AriaHider.js - aria-hidden management for modal dialogs
// Vendored from purescript-radix (straylight/purescript-radix)

export const hideOthers = el => () => {
  const hidden = [];
  let current = el;
  
  while (current && current !== document.body && current.parentElement) {
    const parent = current.parentElement;
    for (const sibling of parent.children) {
      if (sibling === current) continue;
      if (shouldIgnore(sibling)) continue;
      hidden.push({ element: sibling, original: sibling.getAttribute('aria-hidden') });
      sibling.setAttribute('aria-hidden', 'true');
    }
    current = parent;
  }
  return { hidden };
};

export const restoreOthers = state => () => {
  for (const { element, original } of state.hidden) {
    if (original === null) element.removeAttribute('aria-hidden');
    else element.setAttribute('aria-hidden', original);
  }
};

const shouldIgnore = el => {
  const tag = el.tagName.toLowerCase();
  if (tag === 'script' || tag === 'style' || tag === 'template') return true;
  if (el.hasAttribute('data-hydrogen-portal')) return true;
  const live = el.getAttribute('aria-live');
  if (live === 'polite' || live === 'assertive') return true;
  return el.getAttribute('aria-hidden') === 'true';
};
