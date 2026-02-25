// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//                                                       // hydrogen // dragdrop
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

// Core drag and drop system with touch support, keyboard accessibility,
// and constraint handling

// ═══════════════════════════════════════════════════════════════════════════════
//                                                              // foreign utils
// ═══════════════════════════════════════════════════════════════════════════════

export const unsafeToForeign = (x) => x;

// ═══════════════════════════════════════════════════════════════════════════════
//                                                              // drag state
// ═══════════════════════════════════════════════════════════════════════════════

let dragState = null;
let ghostElement = null;
let dropIndicator = null;

export const getDragStateImpl = () => {
  return dragState;
};

export const setDragStateImpl = (state) => () => {
  dragState = state;
};

export const clearDragStateImpl = () => {
  dragState = null;
  removeGhost();
  removeDropIndicator();
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                              // ghost element
// ═══════════════════════════════════════════════════════════════════════════════

export const createGhostImpl = (element) => (x) => (y) => (opacity) => () => {
  removeGhost();
  
  const rect = element.getBoundingClientRect();
  ghostElement = element.cloneNode(true);
  
  ghostElement.style.cssText = `
    position: fixed;
    left: ${x}px;
    top: ${y}px;
    width: ${rect.width}px;
    height: ${rect.height}px;
    opacity: ${opacity};
    pointer-events: none;
    z-index: 10000;
    transition: none;
    transform: scale(1.02);
    box-shadow: 0 10px 25px rgba(0, 0, 0, 0.15);
  `;
  
  ghostElement.setAttribute("data-drag-ghost", "true");
  document.body.appendChild(ghostElement);
  
  return ghostElement;
};

export const updateGhostPositionImpl = (x) => (y) => () => {
  if (ghostElement) {
    ghostElement.style.left = `${x}px`;
    ghostElement.style.top = `${y}px`;
  }
};

export const removeGhostImpl = () => {
  removeGhost();
};

function removeGhost() {
  if (ghostElement && ghostElement.parentNode) {
    ghostElement.parentNode.removeChild(ghostElement);
    ghostElement = null;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//                                                           // drop indicator
// ═══════════════════════════════════════════════════════════════════════════════

export const showDropIndicatorImpl = (x) => (y) => (width) => (height) => (className) => () => {
  removeDropIndicator();
  
  dropIndicator = document.createElement("div");
  dropIndicator.className = className;
  dropIndicator.style.cssText = `
    position: fixed;
    left: ${x}px;
    top: ${y}px;
    width: ${width}px;
    height: ${height}px;
    pointer-events: none;
    z-index: 9999;
  `;
  
  dropIndicator.setAttribute("data-drop-indicator", "true");
  document.body.appendChild(dropIndicator);
  
  return dropIndicator;
};

export const updateDropIndicatorImpl = (x) => (y) => (width) => (height) => () => {
  if (dropIndicator) {
    dropIndicator.style.left = `${x}px`;
    dropIndicator.style.top = `${y}px`;
    dropIndicator.style.width = `${width}px`;
    dropIndicator.style.height = `${height}px`;
  }
};

export const removeDropIndicatorImpl = () => {
  removeDropIndicator();
};

function removeDropIndicator() {
  if (dropIndicator && dropIndicator.parentNode) {
    dropIndicator.parentNode.removeChild(dropIndicator);
    dropIndicator = null;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//                                                            // event handlers
// ═══════════════════════════════════════════════════════════════════════════════

export const addDragListenersImpl = (element) => (config) => (callbacks) => () => {
  let isDragging = false;
  let startX = 0;
  let startY = 0;
  let currentX = 0;
  let currentY = 0;
  let offsetX = 0;
  let offsetY = 0;
  
  const handleStart = (clientX, clientY) => {
    const rect = element.getBoundingClientRect();
    startX = clientX;
    startY = clientY;
    currentX = clientX;
    currentY = clientY;
    offsetX = clientX - rect.left;
    offsetY = clientY - rect.top;
    
    // Set drag data
    dragState = {
      element: element,
      data: config.data,
      startX: startX,
      startY: startY,
      offsetX: offsetX,
      offsetY: offsetY
    };
    
    isDragging = true;
    element.setAttribute("data-dragging", "true");
    
    // Create ghost if enabled
    if (config.showGhost) {
      createGhostImpl(element)(rect.left)(rect.top)(config.ghostOpacity)();
    }
    
    callbacks.onDragStart({
      element: element,
      data: config.data,
      x: clientX,
      y: clientY,
      offsetX: offsetX,
      offsetY: offsetY
    })();
  };
  
  const handleMove = (clientX, clientY) => {
    if (!isDragging) return;
    
    let newX = clientX;
    let newY = clientY;
    
    // Apply axis constraints
    if (config.axis === "x") {
      newY = startY;
    } else if (config.axis === "y") {
      newX = startX;
    }
    
    // Apply bounds constraints
    if (config.bounds) {
      const bounds = config.bounds;
      newX = Math.max(bounds.left, Math.min(bounds.right, newX));
      newY = Math.max(bounds.top, Math.min(bounds.bottom, newY));
    }
    
    currentX = newX;
    currentY = newY;
    
    // Update ghost position
    if (ghostElement) {
      updateGhostPositionImpl(newX - offsetX)(newY - offsetY)();
    }
    
    callbacks.onDrag({
      element: element,
      data: config.data,
      x: newX,
      y: newY,
      deltaX: newX - startX,
      deltaY: newY - startY
    })();
  };
  
  const handleEnd = () => {
    if (!isDragging) return;
    
    isDragging = false;
    element.removeAttribute("data-dragging");
    
    callbacks.onDragEnd({
      element: element,
      data: config.data,
      x: currentX,
      y: currentY,
      deltaX: currentX - startX,
      deltaY: currentY - startY
    })();
    
    clearDragStateImpl();
  };
  
  // Mouse events
  const onMouseDown = (e) => {
    if (config.handleSelector) {
      const handle = e.target.closest(config.handleSelector);
      if (!handle) return;
    }
    e.preventDefault();
    handleStart(e.clientX, e.clientY);
    
    document.addEventListener("mousemove", onMouseMove);
    document.addEventListener("mouseup", onMouseUp);
  };
  
  const onMouseMove = (e) => {
    e.preventDefault();
    handleMove(e.clientX, e.clientY);
  };
  
  const onMouseUp = (e) => {
    handleEnd();
    document.removeEventListener("mousemove", onMouseMove);
    document.removeEventListener("mouseup", onMouseUp);
  };
  
  // Touch events
  const onTouchStart = (e) => {
    if (config.handleSelector) {
      const handle = e.target.closest(config.handleSelector);
      if (!handle) return;
    }
    const touch = e.touches[0];
    handleStart(touch.clientX, touch.clientY);
  };
  
  const onTouchMove = (e) => {
    if (!isDragging) return;
    e.preventDefault();
    const touch = e.touches[0];
    handleMove(touch.clientX, touch.clientY);
  };
  
  const onTouchEnd = (e) => {
    handleEnd();
  };
  
  // Keyboard events for accessibility
  const onKeyDown = (e) => {
    if (!element.hasAttribute("data-keyboard-drag")) return;
    
    const step = config.keyboardStep || 10;
    let moved = false;
    
    switch (e.key) {
      case "ArrowLeft":
        if (config.axis !== "y") {
          currentX -= step;
          moved = true;
        }
        break;
      case "ArrowRight":
        if (config.axis !== "y") {
          currentX += step;
          moved = true;
        }
        break;
      case "ArrowUp":
        if (config.axis !== "x") {
          currentY -= step;
          moved = true;
        }
        break;
      case "ArrowDown":
        if (config.axis !== "x") {
          currentY += step;
          moved = true;
        }
        break;
      case "Escape":
        element.removeAttribute("data-keyboard-drag");
        handleEnd();
        return;
      case "Enter":
      case " ":
        element.removeAttribute("data-keyboard-drag");
        handleEnd();
        return;
    }
    
    if (moved) {
      e.preventDefault();
      handleMove(currentX, currentY);
    }
  };
  
  const onKeyDownActivate = (e) => {
    if (e.key === " " || e.key === "Enter") {
      e.preventDefault();
      const rect = element.getBoundingClientRect();
      currentX = rect.left + rect.width / 2;
      currentY = rect.top + rect.height / 2;
      element.setAttribute("data-keyboard-drag", "true");
      handleStart(currentX, currentY);
    }
  };
  
  element.addEventListener("mousedown", onMouseDown);
  element.addEventListener("touchstart", onTouchStart, { passive: false });
  element.addEventListener("touchmove", onTouchMove, { passive: false });
  element.addEventListener("touchend", onTouchEnd);
  element.addEventListener("keydown", onKeyDownActivate);
  element.addEventListener("keydown", onKeyDown);
  
  // Return cleanup function
  return () => {
    element.removeEventListener("mousedown", onMouseDown);
    element.removeEventListener("touchstart", onTouchStart);
    element.removeEventListener("touchmove", onTouchMove);
    element.removeEventListener("touchend", onTouchEnd);
    element.removeEventListener("keydown", onKeyDownActivate);
    element.removeEventListener("keydown", onKeyDown);
    document.removeEventListener("mousemove", onMouseMove);
    document.removeEventListener("mouseup", onMouseUp);
  };
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                            // drop zone
// ═══════════════════════════════════════════════════════════════════════════════

export const addDropListenersImpl = (element) => (config) => (callbacks) => () => {
  const onDragOver = (e) => {
    e.preventDefault();
    
    if (!dragState) return;
    
    // Check if we accept this drag
    if (config.accepts && !config.accepts(dragState.data)) {
      return;
    }
    
    element.setAttribute("data-drag-over", "true");
    
    callbacks.onDragOver({
      element: element,
      data: dragState.data,
      x: e.clientX,
      y: e.clientY
    })();
  };
  
  const onDragLeave = (e) => {
    // Check if we're still within the element
    const rect = element.getBoundingClientRect();
    if (
      e.clientX >= rect.left &&
      e.clientX <= rect.right &&
      e.clientY >= rect.top &&
      e.clientY <= rect.bottom
    ) {
      return;
    }
    
    element.removeAttribute("data-drag-over");
    
    callbacks.onDragLeave({
      element: element
    })();
  };
  
  const onDrop = (e) => {
    e.preventDefault();
    element.removeAttribute("data-drag-over");
    
    if (!dragState) return;
    
    // Check if we accept this drag
    if (config.accepts && !config.accepts(dragState.data)) {
      return;
    }
    
    callbacks.onDrop({
      element: element,
      data: dragState.data,
      x: e.clientX,
      y: e.clientY
    })();
    
    clearDragStateImpl();
  };
  
  // For our custom drag system, we need to track mouse position
  const onMouseMove = (e) => {
    if (!dragState) return;
    
    const rect = element.getBoundingClientRect();
    const isOver = (
      e.clientX >= rect.left &&
      e.clientX <= rect.right &&
      e.clientY >= rect.top &&
      e.clientY <= rect.bottom
    );
    
    if (isOver && !element.hasAttribute("data-drag-over")) {
      element.setAttribute("data-drag-over", "true");
      callbacks.onDragOver({
        element: element,
        data: dragState.data,
        x: e.clientX,
        y: e.clientY
      })();
    } else if (!isOver && element.hasAttribute("data-drag-over")) {
      element.removeAttribute("data-drag-over");
      callbacks.onDragLeave({ element: element })();
    }
  };
  
  const onMouseUp = (e) => {
    if (!dragState) return;
    if (!element.hasAttribute("data-drag-over")) return;
    
    element.removeAttribute("data-drag-over");
    
    // Check if we accept this drag
    if (config.accepts && !config.accepts(dragState.data)) {
      return;
    }
    
    callbacks.onDrop({
      element: element,
      data: dragState.data,
      x: e.clientX,
      y: e.clientY
    })();
  };
  
  // Native drag and drop events
  element.addEventListener("dragover", onDragOver);
  element.addEventListener("dragleave", onDragLeave);
  element.addEventListener("drop", onDrop);
  
  // Custom drag system events
  document.addEventListener("mousemove", onMouseMove);
  document.addEventListener("mouseup", onMouseUp);
  
  return () => {
    element.removeEventListener("dragover", onDragOver);
    element.removeEventListener("dragleave", onDragLeave);
    element.removeEventListener("drop", onDrop);
    document.removeEventListener("mousemove", onMouseMove);
    document.removeEventListener("mouseup", onMouseUp);
  };
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                            // data transfer
// ═══════════════════════════════════════════════════════════════════════════════

export const setDragDataImpl = (key) => (value) => () => {
  if (dragState) {
    dragState.data = dragState.data || {};
    dragState.data[key] = value;
  }
};

export const getDragDataImpl = (key) => () => {
  if (dragState && dragState.data) {
    return dragState.data[key] || null;
  }
  return null;
};

export const clearDragDataImpl = () => {
  if (dragState) {
    dragState.data = {};
  }
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                            // utilities
// ═══════════════════════════════════════════════════════════════════════════════

export const getBoundingRectImpl = (element) => () => {
  const rect = element.getBoundingClientRect();
  return {
    left: rect.left,
    top: rect.top,
    right: rect.right,
    bottom: rect.bottom,
    width: rect.width,
    height: rect.height
  };
};

export const getElementAtPointImpl = (x) => (y) => () => {
  return document.elementFromPoint(x, y);
};

export const containsImpl = (parent) => (child) => {
  return parent.contains(child);
};

export const setStyleImpl = (element) => (property) => (value) => () => {
  element.style[property] = value;
};

export const addClassImpl = (element) => (className) => () => {
  element.classList.add(className);
};

export const removeClassImpl = (element) => (className) => () => {
  element.classList.remove(className);
};
