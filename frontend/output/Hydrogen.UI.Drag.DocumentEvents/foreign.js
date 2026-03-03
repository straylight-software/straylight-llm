// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//                              // hydrogen // ui // drag // documentevents
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

// FFI for DocumentEvents.purs
// Provides document-level mouse event handling for drag operations

// | Start listening for document-level mouse events
// | Returns a handle object containing state and cleanup functions
export const startDragImpl = function(onMove) {
  return function(onEnd) {
    return function() {
      // Create handle object to track state
      var handle = {
        clientX: 0,
        clientY: 0,
        movementX: 0,
        movementY: 0,
        isActive: true,
        moveHandler: null,
        upHandler: null
      };
      
      // Mouse move handler
      handle.moveHandler = function(event) {
        if (!handle.isActive) return;
        
        handle.movementX = event.clientX - handle.clientX;
        handle.movementY = event.clientY - handle.clientY;
        handle.clientX = event.clientX;
        handle.clientY = event.clientY;
        
        // Call the PureScript callback
        onMove(event.clientX)(event.clientY)();
      };
      
      // Mouse up handler
      handle.upHandler = function(event) {
        if (!handle.isActive) return;
        
        handle.isActive = false;
        
        // Remove listeners
        document.removeEventListener('mousemove', handle.moveHandler);
        document.removeEventListener('mouseup', handle.upHandler);
        
        // Call the PureScript callback
        onEnd();
      };
      
      // Attach listeners to document
      document.addEventListener('mousemove', handle.moveHandler);
      document.addEventListener('mouseup', handle.upHandler);
      
      return handle;
    };
  };
};

// | Stop listening for document-level mouse events
export const stopDragImpl = function(handle) {
  return function() {
    if (handle.isActive) {
      handle.isActive = false;
      document.removeEventListener('mousemove', handle.moveHandler);
      document.removeEventListener('mouseup', handle.upHandler);
    }
  };
};

// | Get clientX from the handle
export const getClientXImpl = function(handle) {
  return function() {
    return handle.clientX;
  };
};

// | Get clientY from the handle
export const getClientYImpl = function(handle) {
  return function() {
    return handle.clientY;
  };
};

// | Get movementX from the handle
export const getMovementXImpl = function(handle) {
  return function() {
    return handle.movementX;
  };
};

// | Get movementY from the handle
export const getMovementYImpl = function(handle) {
  return function() {
    return handle.movementY;
  };
};
