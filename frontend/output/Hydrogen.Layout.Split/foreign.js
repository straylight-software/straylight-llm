// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//                                                          // hydrogen // split
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

// Split pane layout FFI
// Provides draggable resizable split panes with persistence

/**
 * Initialize split layout
 * @param {string} selector - CSS selector for split container
 * @returns {SplitHandle}
 */
export const initSplit = (selector) => {
  const container = document.querySelector(selector);
  if (!container) {
    console.warn(`Split: No element found for selector "${selector}"`);
    return { container: null, sizes: [50, 50] };
  }

  const handle = {
    container,
    primaryPane: container.querySelector('[data-split-pane="primary"]'),
    secondaryPane: container.querySelector('[data-split-pane="secondary"]'),
    gutter: container.querySelector('[data-split-gutter]'),
    direction: container.dataset.direction || 'horizontal',
    minSize: parseFloat(container.dataset.minSize) || 10,
    maxSize: parseFloat(container.dataset.maxSize) || 90,
    persistKey: container.dataset.persist || null,
    sizes: [50, 50],
    isDragging: false
  };

  // Load persisted sizes
  if (handle.persistKey) {
    try {
      const saved = localStorage.getItem(handle.persistKey);
      if (saved) {
        handle.sizes = JSON.parse(saved);
        applySizes(handle);
      }
    } catch (e) {
      console.warn('Split: Failed to load persisted sizes', e);
    }
  }

  // Set up drag handlers
  if (handle.gutter) {
    handle.gutter.addEventListener('mousedown', (e) => startDrag(e, handle));
    handle.gutter.addEventListener('touchstart', (e) => startDrag(e.touches[0], handle), { passive: true });
  }

  // Global handlers for drag
  const handleMouseMove = (e) => {
    if (handle.isDragging) {
      updateSplit(e, handle);
    }
  };

  const handleTouchMove = (e) => {
    if (handle.isDragging) {
      updateSplit(e.touches[0], handle);
    }
  };

  const handleEnd = () => {
    if (handle.isDragging) {
      endDrag(handle);
    }
  };

  document.addEventListener('mousemove', handleMouseMove);
  document.addEventListener('touchmove', handleTouchMove, { passive: true });
  document.addEventListener('mouseup', handleEnd);
  document.addEventListener('touchend', handleEnd);

  // Store cleanup function
  handle.cleanup = () => {
    document.removeEventListener('mousemove', handleMouseMove);
    document.removeEventListener('touchmove', handleTouchMove);
    document.removeEventListener('mouseup', handleEnd);
    document.removeEventListener('touchend', handleEnd);
  };

  return handle;
};

/**
 * Start drag operation
 * @param {MouseEvent|Touch} e
 * @param {SplitHandle} handle
 */
function startDrag(e, handle) {
  handle.isDragging = true;
  handle.startPos = handle.direction === 'horizontal' ? e.clientX : e.clientY;
  handle.startSize = handle.sizes[0];
  
  // Add dragging class
  if (handle.container) {
    handle.container.classList.add('select-none');
  }
  if (handle.gutter) {
    handle.gutter.classList.add('bg-primary/30');
  }
}

/**
 * Update split during drag
 * @param {MouseEvent|Touch} e
 * @param {SplitHandle} handle
 */
function updateSplit(e, handle) {
  if (!handle.container || !handle.primaryPane) return;

  const containerRect = handle.container.getBoundingClientRect();
  const containerSize = handle.direction === 'horizontal' 
    ? containerRect.width 
    : containerRect.height;
  
  const currentPos = handle.direction === 'horizontal' ? e.clientX : e.clientY;
  const containerStart = handle.direction === 'horizontal' 
    ? containerRect.left 
    : containerRect.top;
  
  // Calculate percentage
  let newSize = ((currentPos - containerStart) / containerSize) * 100;
  
  // Apply constraints
  newSize = Math.max(handle.minSize, Math.min(handle.maxSize, newSize));
  
  handle.sizes = [newSize, 100 - newSize];
  applySizes(handle);
}

/**
 * End drag operation
 * @param {SplitHandle} handle
 */
function endDrag(handle) {
  handle.isDragging = false;
  
  // Remove dragging class
  if (handle.container) {
    handle.container.classList.remove('select-none');
  }
  if (handle.gutter) {
    handle.gutter.classList.remove('bg-primary/30');
  }
  
  // Persist sizes
  if (handle.persistKey) {
    try {
      localStorage.setItem(handle.persistKey, JSON.stringify(handle.sizes));
    } catch (e) {
      console.warn('Split: Failed to persist sizes', e);
    }
  }
  
  // Fire resize event
  if (handle.container) {
    handle.container.dispatchEvent(new CustomEvent('split-resize', {
      detail: { sizes: handle.sizes }
    }));
  }
}

/**
 * Apply sizes to panes
 * @param {SplitHandle} handle
 */
function applySizes(handle) {
  if (!handle.primaryPane || !handle.secondaryPane) return;
  
  const prop = handle.direction === 'horizontal' ? 'width' : 'height';
  handle.primaryPane.style[prop] = `${handle.sizes[0]}%`;
  handle.secondaryPane.style[prop] = `${handle.sizes[1]}%`;
}

/**
 * Set pane sizes programmatically
 * @param {SplitHandle} handle
 * @param {number[]} sizes
 */
export const setSizesImpl = (handle, sizes) => {
  if (sizes.length >= 2) {
    handle.sizes = [sizes[0], sizes[1]];
    applySizes(handle);
    
    // Persist if enabled
    if (handle.persistKey) {
      try {
        localStorage.setItem(handle.persistKey, JSON.stringify(handle.sizes));
      } catch (e) {
        console.warn('Split: Failed to persist sizes', e);
      }
    }
  }
};

/**
 * Collapse primary pane
 * @param {SplitHandle} handle
 */
export const collapseImpl = (handle) => {
  handle.sizes = [0, 100];
  applySizes(handle);
  
  if (handle.container) {
    handle.container.dispatchEvent(new CustomEvent('split-collapse', {
      detail: { collapsed: true }
    }));
  }
};

/**
 * Expand primary pane to previous size
 * @param {SplitHandle} handle
 */
export const expandImpl = (handle) => {
  // Restore to min size if currently collapsed
  if (handle.sizes[0] < handle.minSize) {
    handle.sizes = [handle.minSize, 100 - handle.minSize];
  }
  applySizes(handle);
  
  if (handle.container) {
    handle.container.dispatchEvent(new CustomEvent('split-collapse', {
      detail: { collapsed: false }
    }));
  }
};

/**
 * Get current sizes
 * @param {SplitHandle} handle
 * @returns {number[]}
 */
export const getSizesImpl = (handle) => {
  return handle.sizes;
};

/**
 * Destroy split instance
 * @param {SplitHandle} handle
 */
export const destroySplit = (handle) => {
  if (handle.cleanup) {
    handle.cleanup();
  }
  
  // Reset styles
  if (handle.primaryPane) {
    handle.primaryPane.style.width = '';
    handle.primaryPane.style.height = '';
  }
  if (handle.secondaryPane) {
    handle.secondaryPane.style.width = '';
    handle.secondaryPane.style.height = '';
  }
};
