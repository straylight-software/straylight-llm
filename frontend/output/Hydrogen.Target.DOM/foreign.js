// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//                                                      // hydrogen // target // dom
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

// | Minimal FFI for DOM target adapter
// |
// | These 3 functions are not available in the standard web-dom PureScript
// | package. They are the absolute minimum JavaScript required to render
// | Hydrogen Elements to the browser DOM.

// | Set a namespaced attribute on an element
// | Used for SVG attributes like xlink:href
export const setAttributeNS = (ns) => (name) => (value) => (element) => () => {
  element.setAttributeNS(ns, name, value);
};

// | Set a DOM property directly on an element
// | Properties differ from attributes - they're live values on the DOM object
// | Examples: element.value, element.checked, element.disabled
export const setProperty = (name) => (value) => (element) => () => {
  element[name] = value;
};

// | Set a CSS style property on an element
// | Uses element.style[prop] = value
export const setStyleProperty = (prop) => (value) => (element) => () => {
  element.style[prop] = value;
};
