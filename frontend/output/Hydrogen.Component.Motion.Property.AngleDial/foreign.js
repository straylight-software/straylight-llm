// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//                      // hydrogen // component // motion // property // angledial
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

// FFI for AngleDial.purs
// Only DOM-specific functions that require getBoundingClientRect

// | Get element center X position from the event target
// | Uses getBoundingClientRect which has no PureScript equivalent
export const getElementCenterX = function(event) {
  if (event.currentTarget && event.currentTarget.getBoundingClientRect) {
    const rect = event.currentTarget.getBoundingClientRect();
    return rect.left + rect.width / 2;
  }
  return event.clientX;
};

// | Get element center Y position from the event target
// | Uses getBoundingClientRect which has no PureScript equivalent
export const getElementCenterY = function(event) {
  if (event.currentTarget && event.currentTarget.getBoundingClientRect) {
    const rect = event.currentTarget.getBoundingClientRect();
    return rect.top + rect.height / 2;
  }
  return event.clientY;
};
