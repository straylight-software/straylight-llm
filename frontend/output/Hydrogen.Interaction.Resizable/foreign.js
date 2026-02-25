// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//                                                      // hydrogen // resizable
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

// Resizable panels with min/max constraints, keyboard support,
// persistence, and collapse functionality

// ═══════════════════════════════════════════════════════════════════════════════
//                                                              // resize state
// ═══════════════════════════════════════════════════════════════════════════════

let resizeState = null;

export const getResizeStateImpl = () => {
  return resizeState;
};

export const setResizeStateImpl = (state) => () => {
  resizeState = state;
};

export const clearResizeStateImpl = () => {
  resizeState = null;
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                          // resizable panel
// ═══════════════════════════════════════════════════════════════════════════════

export const initResizablePanelImpl = (container) => (config) => (callbacks) => () => {
  const isHorizontal = config.direction === "horizontal";
  const handles = container.querySelectorAll("[data-resize-handle]");
  
  let isResizing = false;
  let activeHandle = null;
  let startPos = 0;
  let startSizes = [];
  let panels = [];
  
  const getPanels = () => {
    return Array.from(container.querySelectorAll("[data-resizable-panel]"));
  };
  
  const getPanelSizes = () => {
    return getPanels().map(panel => {
      const rect = panel.getBoundingClientRect();
      return isHorizontal ? rect.width : rect.height;
    });
  };
  
  const getHandleIndex = (handle) => {
    const handleList = Array.from(handles);
    return handleList.indexOf(handle);
  };
  
  const applyConstraints = (size, panel) => {
    const minSize = parseFloat(panel.getAttribute("data-min-size")) || 0;
    const maxSize = parseFloat(panel.getAttribute("data-max-size")) || Infinity;
    return Math.max(minSize, Math.min(maxSize, size));
  };
  
  const setPanelSize = (panel, size) => {
    const constrainedSize = applyConstraints(size, panel);
    
    if (isHorizontal) {
      panel.style.width = `${constrainedSize}px`;
      panel.style.flexBasis = `${constrainedSize}px`;
      panel.style.flexGrow = "0";
      panel.style.flexShrink = "0";
    } else {
      panel.style.height = `${constrainedSize}px`;
      panel.style.flexBasis = `${constrainedSize}px`;
      panel.style.flexGrow = "0";
      panel.style.flexShrink = "0";
    }
    
    return constrainedSize;
  };
  
  const handleResizeStart = (handle, clientX, clientY) => {
    isResizing = true;
    activeHandle = handle;
    startPos = isHorizontal ? clientX : clientY;
    panels = getPanels();
    startSizes = getPanelSizes();
    
    const handleIndex = getHandleIndex(handle);
    
    resizeState = {
      container: container,
      handle: handle,
      handleIndex: handleIndex,
      startPos: startPos,
      currentPos: startPos,
      startSizes: startSizes,
      direction: config.direction
    };
    
    handle.setAttribute("data-resizing", "true");
    container.setAttribute("data-resizing", "true");
    document.body.style.cursor = isHorizontal ? "col-resize" : "row-resize";
    document.body.style.userSelect = "none";
    
    callbacks.onResizeStart({
      handle: handle,
      handleIndex: handleIndex,
      sizes: startSizes
    })();
  };
  
  const handleResizeMove = (clientX, clientY) => {
    if (!isResizing || !activeHandle) return;
    
    const currentPos = isHorizontal ? clientX : clientY;
    const delta = currentPos - startPos;
    const handleIndex = getHandleIndex(activeHandle);
    
    // Resize panels adjacent to the handle
    const leftPanel = panels[handleIndex];
    const rightPanel = panels[handleIndex + 1];
    
    if (leftPanel && rightPanel) {
      const leftStartSize = startSizes[handleIndex];
      const rightStartSize = startSizes[handleIndex + 1];
      
      let newLeftSize = leftStartSize + delta;
      let newRightSize = rightStartSize - delta;
      
      // Apply constraints
      const leftMin = parseFloat(leftPanel.getAttribute("data-min-size")) || 0;
      const leftMax = parseFloat(leftPanel.getAttribute("data-max-size")) || Infinity;
      const rightMin = parseFloat(rightPanel.getAttribute("data-min-size")) || 0;
      const rightMax = parseFloat(rightPanel.getAttribute("data-max-size")) || Infinity;
      
      // Constrain left panel
      if (newLeftSize < leftMin) {
        newRightSize += (newLeftSize - leftMin);
        newLeftSize = leftMin;
      } else if (newLeftSize > leftMax) {
        newRightSize += (newLeftSize - leftMax);
        newLeftSize = leftMax;
      }
      
      // Constrain right panel
      if (newRightSize < rightMin) {
        newLeftSize += (newRightSize - rightMin);
        newRightSize = rightMin;
      } else if (newRightSize > rightMax) {
        newLeftSize += (newRightSize - rightMax);
        newRightSize = rightMax;
      }
      
      setPanelSize(leftPanel, newLeftSize);
      setPanelSize(rightPanel, newRightSize);
      
      // Update state
      resizeState.currentPos = currentPos;
      
      const newSizes = getPanelSizes();
      
      callbacks.onResize({
        handle: activeHandle,
        handleIndex: handleIndex,
        sizes: newSizes,
        delta: delta
      })();
    }
  };
  
  const handleResizeEnd = () => {
    if (!isResizing) return;
    
    const handleIndex = getHandleIndex(activeHandle);
    const finalSizes = getPanelSizes();
    
    activeHandle.removeAttribute("data-resizing");
    container.removeAttribute("data-resizing");
    document.body.style.cursor = "";
    document.body.style.userSelect = "";
    
    callbacks.onResizeEnd({
      handle: activeHandle,
      handleIndex: handleIndex,
      sizes: finalSizes
    })();
    
    // Persist sizes if enabled
    if (config.persistKey) {
      try {
        localStorage.setItem(config.persistKey, JSON.stringify(finalSizes));
      } catch (e) {
        // localStorage may not be available
      }
    }
    
    isResizing = false;
    activeHandle = null;
    clearResizeStateImpl();
  };
  
  // Mouse events
  const onMouseDown = (e) => {
    const handle = e.target.closest("[data-resize-handle]");
    if (!handle) return;
    
    e.preventDefault();
    handleResizeStart(handle, e.clientX, e.clientY);
    
    document.addEventListener("mousemove", onMouseMove);
    document.addEventListener("mouseup", onMouseUp);
  };
  
  const onMouseMove = (e) => {
    e.preventDefault();
    handleResizeMove(e.clientX, e.clientY);
  };
  
  const onMouseUp = () => {
    handleResizeEnd();
    document.removeEventListener("mousemove", onMouseMove);
    document.removeEventListener("mouseup", onMouseUp);
  };
  
  // Touch events
  const onTouchStart = (e) => {
    const handle = e.target.closest("[data-resize-handle]");
    if (!handle) return;
    
    const touch = e.touches[0];
    handleResizeStart(handle, touch.clientX, touch.clientY);
  };
  
  const onTouchMove = (e) => {
    if (!isResizing) return;
    e.preventDefault();
    const touch = e.touches[0];
    handleResizeMove(touch.clientX, touch.clientY);
  };
  
  const onTouchEnd = () => {
    handleResizeEnd();
  };
  
  // Keyboard events
  const onKeyDown = (e) => {
    const handle = e.target.closest("[data-resize-handle]");
    if (!handle) return;
    
    const handleIndex = getHandleIndex(handle);
    const step = config.keyboardStep || 10;
    let delta = 0;
    
    switch (e.key) {
      case "ArrowLeft":
      case "ArrowUp":
        e.preventDefault();
        delta = -step;
        break;
      case "ArrowRight":
      case "ArrowDown":
        e.preventDefault();
        delta = step;
        break;
      case "Home":
        e.preventDefault();
        // Collapse to minimum
        collapsePanel(handleIndex, "left");
        return;
      case "End":
        e.preventDefault();
        // Expand to maximum
        collapsePanel(handleIndex, "right");
        return;
      default:
        return;
    }
    
    if (delta !== 0) {
      panels = getPanels();
      startSizes = getPanelSizes();
      startPos = 0;
      
      handleResizeMove(delta, delta);
      
      const finalSizes = getPanelSizes();
      callbacks.onResizeEnd({
        handle: handle,
        handleIndex: handleIndex,
        sizes: finalSizes
      })();
      
      if (config.persistKey) {
        try {
          localStorage.setItem(config.persistKey, JSON.stringify(finalSizes));
        } catch (e) {}
      }
    }
  };
  
  // Double click to reset
  const onDoubleClick = (e) => {
    const handle = e.target.closest("[data-resize-handle]");
    if (!handle) return;
    
    const handleIndex = getHandleIndex(handle);
    resetPanelSizes(handleIndex);
  };
  
  const collapsePanel = (handleIndex, side) => {
    panels = getPanels();
    const leftPanel = panels[handleIndex];
    const rightPanel = panels[handleIndex + 1];
    
    if (side === "left" && leftPanel) {
      const minSize = parseFloat(leftPanel.getAttribute("data-min-size")) || 0;
      setPanelSize(leftPanel, minSize);
      
      // Give remaining space to right panel
      const containerSize = isHorizontal 
        ? container.clientWidth 
        : container.clientHeight;
      const otherSizes = getPanelSizes().reduce((sum, s, i) => 
        i !== handleIndex + 1 ? sum + s : sum, 0);
      setPanelSize(rightPanel, containerSize - otherSizes);
    } else if (side === "right" && rightPanel) {
      const minSize = parseFloat(rightPanel.getAttribute("data-min-size")) || 0;
      setPanelSize(rightPanel, minSize);
      
      const containerSize = isHorizontal 
        ? container.clientWidth 
        : container.clientHeight;
      const otherSizes = getPanelSizes().reduce((sum, s, i) => 
        i !== handleIndex ? sum + s : sum, 0);
      setPanelSize(leftPanel, containerSize - otherSizes);
    }
    
    const finalSizes = getPanelSizes();
    callbacks.onResizeEnd({
      handle: handles[handleIndex],
      handleIndex: handleIndex,
      sizes: finalSizes
    })();
  };
  
  const resetPanelSizes = (handleIndex) => {
    panels = getPanels();
    
    // Reset to default sizes
    panels.forEach(panel => {
      const defaultSize = panel.getAttribute("data-default-size");
      if (defaultSize) {
        if (isHorizontal) {
          panel.style.width = defaultSize;
          panel.style.flexBasis = defaultSize;
        } else {
          panel.style.height = defaultSize;
          panel.style.flexBasis = defaultSize;
        }
        panel.style.flexGrow = "";
        panel.style.flexShrink = "";
      } else {
        // Reset to flex: 1
        panel.style.width = "";
        panel.style.height = "";
        panel.style.flexBasis = "";
        panel.style.flexGrow = "1";
        panel.style.flexShrink = "1";
      }
    });
    
    const finalSizes = getPanelSizes();
    callbacks.onReset({
      handleIndex: handleIndex,
      sizes: finalSizes
    })();
    
    // Clear persisted sizes
    if (config.persistKey) {
      try {
        localStorage.removeItem(config.persistKey);
      } catch (e) {}
    }
  };
  
  // Restore persisted sizes
  if (config.persistKey) {
    try {
      const saved = localStorage.getItem(config.persistKey);
      if (saved) {
        const savedSizes = JSON.parse(saved);
        panels = getPanels();
        panels.forEach((panel, i) => {
          if (savedSizes[i] !== undefined) {
            setPanelSize(panel, savedSizes[i]);
          }
        });
      }
    } catch (e) {}
  }
  
  container.addEventListener("mousedown", onMouseDown);
  container.addEventListener("touchstart", onTouchStart, { passive: false });
  container.addEventListener("touchmove", onTouchMove, { passive: false });
  container.addEventListener("touchend", onTouchEnd);
  container.addEventListener("keydown", onKeyDown);
  container.addEventListener("dblclick", onDoubleClick);
  
  return () => {
    container.removeEventListener("mousedown", onMouseDown);
    container.removeEventListener("touchstart", onTouchStart);
    container.removeEventListener("touchmove", onTouchMove);
    container.removeEventListener("touchend", onTouchEnd);
    container.removeEventListener("keydown", onKeyDown);
    container.removeEventListener("dblclick", onDoubleClick);
    document.removeEventListener("mousemove", onMouseMove);
    document.removeEventListener("mouseup", onMouseUp);
  };
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                              // panel control
// ═══════════════════════════════════════════════════════════════════════════════

export const collapsePanelImpl = (panel) => (direction) => () => {
  const isHorizontal = direction === "horizontal";
  const minSize = parseFloat(panel.getAttribute("data-min-size")) || 0;
  
  if (isHorizontal) {
    panel.style.width = `${minSize}px`;
    panel.style.flexBasis = `${minSize}px`;
  } else {
    panel.style.height = `${minSize}px`;
    panel.style.flexBasis = `${minSize}px`;
  }
  panel.style.flexGrow = "0";
  panel.style.flexShrink = "0";
  
  panel.setAttribute("data-collapsed", "true");
};

export const expandPanelImpl = (panel) => (direction) => (size) => () => {
  const isHorizontal = direction === "horizontal";
  
  if (isHorizontal) {
    panel.style.width = `${size}px`;
    panel.style.flexBasis = `${size}px`;
  } else {
    panel.style.height = `${size}px`;
    panel.style.flexBasis = `${size}px`;
  }
  panel.style.flexGrow = "0";
  panel.style.flexShrink = "0";
  
  panel.removeAttribute("data-collapsed");
};

export const isPanelCollapsedImpl = (panel) => () => {
  return panel.hasAttribute("data-collapsed");
};

export const getPanelSizeImpl = (panel) => (direction) => () => {
  const isHorizontal = direction === "horizontal";
  const rect = panel.getBoundingClientRect();
  return isHorizontal ? rect.width : rect.height;
};

export const setPanelSizeImpl = (panel) => (direction) => (size) => () => {
  const isHorizontal = direction === "horizontal";
  const minSize = parseFloat(panel.getAttribute("data-min-size")) || 0;
  const maxSize = parseFloat(panel.getAttribute("data-max-size")) || Infinity;
  const constrainedSize = Math.max(minSize, Math.min(maxSize, size));
  
  if (isHorizontal) {
    panel.style.width = `${constrainedSize}px`;
    panel.style.flexBasis = `${constrainedSize}px`;
  } else {
    panel.style.height = `${constrainedSize}px`;
    panel.style.flexBasis = `${constrainedSize}px`;
  }
  panel.style.flexGrow = "0";
  panel.style.flexShrink = "0";
  
  return constrainedSize;
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                              // persistence
// ═══════════════════════════════════════════════════════════════════════════════

export const savePanelSizesImpl = (key) => (sizes) => () => {
  try {
    localStorage.setItem(key, JSON.stringify(sizes));
    return true;
  } catch (e) {
    return false;
  }
};

export const loadPanelSizesImpl = (key) => () => {
  try {
    const saved = localStorage.getItem(key);
    if (saved) {
      return JSON.parse(saved);
    }
  } catch (e) {}
  return null;
};

export const clearPanelSizesImpl = (key) => () => {
  try {
    localStorage.removeItem(key);
  } catch (e) {}
};
