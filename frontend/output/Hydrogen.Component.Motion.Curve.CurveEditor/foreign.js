// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//                       // hydrogen // component // motion // curve // curveeditor
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

// FFI for CurveEditor.purs

// | Extract clientX from a mouse event
export const getClientX = function(event) {
  return event.clientX;
};

// | Extract clientY from a mouse event
export const getClientY = function(event) {
  return event.clientY;
};

// | Get element bounding rect left from event target
export const getTargetLeft = function(event) {
  var target;
  if (event.currentTarget && event.currentTarget.getBoundingClientRect) {
    target = event.currentTarget.getBoundingClientRect();
    return target.left;
  }
  return 0;
};

// | Get element bounding rect top from event target
export const getTargetTop = function(event) {
  var target;
  if (event.currentTarget && event.currentTarget.getBoundingClientRect) {
    target = event.currentTarget.getBoundingClientRect();
    return target.top;
  }
  return 0;
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                    // document-level drag support
// ═══════════════════════════════════════════════════════════════════════════════

// Global drag state - only one drag can be active at a time
var activeDrag = null;

// | Start document-level drag tracking
// | Takes the originating element (to capture bounding rect) and callbacks
export const startDocumentDrag = function(element) {
  return function(onMove) {
    return function(onEnd) {
      return function() {
        // Capture element bounds at drag start (won't change during drag)
        var rect = element.getBoundingClientRect();
        
        // Clean up any existing drag
        if (activeDrag) {
          document.removeEventListener('mousemove', activeDrag.moveHandler);
          document.removeEventListener('mouseup', activeDrag.upHandler);
        }
        
        activeDrag = {
          left: rect.left,
          top: rect.top,
          width: rect.width,
          height: rect.height,
          moveHandler: null,
          upHandler: null
        };
        
        activeDrag.moveHandler = function(event) {
          // Calculate position relative to the original element
          var relX = event.clientX - activeDrag.left;
          var relY = event.clientY - activeDrag.top;
          onMove(relX)(relY)();
        };
        
        activeDrag.upHandler = function(event) {
          document.removeEventListener('mousemove', activeDrag.moveHandler);
          document.removeEventListener('mouseup', activeDrag.upHandler);
          activeDrag = null;
          onEnd();
        };
        
        document.addEventListener('mousemove', activeDrag.moveHandler);
        document.addEventListener('mouseup', activeDrag.upHandler);
        
        return {};
      };
    };
  };
};

// | Stop any active document drag (for cleanup on unmount)
export const stopDocumentDrag = function() {
  if (activeDrag) {
    document.removeEventListener('mousemove', activeDrag.moveHandler);
    document.removeEventListener('mouseup', activeDrag.upHandler);
    activeDrag = null;
  }
};

// | Get the SVG element from a mouse event for drag initialization
export const getTargetElement = function(event) {
  // Walk up to find the SVG element
  var el = event.currentTarget;
  while (el && el.tagName !== 'svg' && el.tagName !== 'SVG') {
    el = el.parentElement;
  }
  return el || event.currentTarget;
};
