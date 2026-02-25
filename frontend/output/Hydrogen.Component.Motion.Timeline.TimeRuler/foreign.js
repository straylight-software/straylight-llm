// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//                         // hydrogen // component // motion // timeline // ruler
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

// FFI for TimeRuler.purs

// | Extract clientX from a mouse event
export const getClientX = function(event) {
  return event.clientX;
};

// | Get the bounding client rect left position of the target element
export const getTargetLeft = function(event) {
  if (event.currentTarget && event.currentTarget.getBoundingClientRect) {
    return event.currentTarget.getBoundingClientRect().left;
  }
  return 0;
};
