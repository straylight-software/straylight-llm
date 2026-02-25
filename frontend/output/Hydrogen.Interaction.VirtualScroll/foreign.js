// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//                                                  // hydrogen // virtual-scroll
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

// Virtual scroll FFI for high-performance list virtualization

// ═══════════════════════════════════════════════════════════════════════════════
//                                                              // scroll control
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Scroll container to specific offset
 */
export const scrollToImpl = (container) => (offset) => () => {
  if (container && container.scrollTo) {
    container.scrollTo({
      top: offset,
      behavior: 'auto'
    });
  } else if (container) {
    container.scrollTop = offset;
  }
};

/**
 * Get current scroll offset
 */
export const getScrollOffsetImpl = (container) => () => {
  if (!container) return 0;
  return container.scrollTop || 0;
};

/**
 * Measure an element's height by index
 */
export const measureElementImpl = (container) => (index) => () => {
  if (!container) return 0;
  
  const element = container.querySelector(`[data-index="${index}"]`);
  if (!element) return 0;
  
  return element.getBoundingClientRect().height;
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                         // scroll optimization
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Optimized scroll handler with requestAnimationFrame batching
 * Ensures 60fps scrolling even with complex content
 */
export const createScrollHandler = (callback) => () => {
  let ticking = false;
  let lastScrollTop = 0;
  
  return (event) => {
    lastScrollTop = event.target.scrollTop;
    
    if (!ticking) {
      requestAnimationFrame(() => {
        callback(lastScrollTop)();
        ticking = false;
      });
      ticking = true;
    }
  };
};

/**
 * Create an optimized ResizeObserver for container size tracking
 */
export const createResizeObserver = (callback) => () => {
  if (typeof ResizeObserver === 'undefined') {
    return { observe: () => {}, disconnect: () => {} };
  }
  
  return new ResizeObserver((entries) => {
    for (const entry of entries) {
      const { width, height } = entry.contentRect;
      callback({ width, height })();
    }
  });
};

/**
 * Observe element resize
 */
export const observeResize = (observer) => (element) => () => {
  if (observer && observer.observe) {
    observer.observe(element);
  }
};

/**
 * Disconnect resize observer
 */
export const disconnectResizeObserver = (observer) => () => {
  if (observer && observer.disconnect) {
    observer.disconnect();
  }
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                       // measurement utilities
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Batch measure multiple items at once for efficiency
 */
export const measureItemsImpl = (container) => (startIndex) => (endIndex) => () => {
  if (!container) return [];
  
  const measurements = [];
  
  for (let i = startIndex; i <= endIndex; i++) {
    const element = container.querySelector(`[data-index="${i}"]`);
    if (element) {
      measurements.push({
        index: i,
        height: element.getBoundingClientRect().height,
        width: element.getBoundingClientRect().width
      });
    }
  }
  
  return measurements;
};

/**
 * Measure item using temporary render
 * Used for pre-measuring items before they're in the viewport
 */
export const measureOffscreenImpl = (container) => (renderFn) => (index) => () => {
  if (!container) return 0;
  
  // Create temporary measuring container
  const measureContainer = document.createElement('div');
  measureContainer.style.cssText = `
    position: absolute;
    top: -9999px;
    left: -9999px;
    visibility: hidden;
    pointer-events: none;
  `;
  
  container.appendChild(measureContainer);
  
  // Render the item
  measureContainer.innerHTML = renderFn(index);
  
  // Measure
  const height = measureContainer.getBoundingClientRect().height;
  
  // Cleanup
  container.removeChild(measureContainer);
  
  return height;
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                            // grid positioning
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Get scroll position for both axes
 */
export const getGridScrollPosition = (container) => () => {
  if (!container) return { x: 0, y: 0 };
  
  return {
    x: container.scrollLeft || 0,
    y: container.scrollTop || 0
  };
};

/**
 * Scroll grid to specific position
 */
export const scrollGridTo = (container) => (x) => (y) => () => {
  if (!container) return;
  
  container.scrollTo({
    left: x,
    top: y,
    behavior: 'auto'
  });
};

/**
 * Smooth scroll to position
 */
export const smoothScrollTo = (container) => (x) => (y) => () => {
  if (!container) return;
  
  container.scrollTo({
    left: x,
    top: y,
    behavior: 'smooth'
  });
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                        // intersection observer
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Create intersection observer for visibility tracking
 * Used for dynamic height measurement on first visibility
 */
export const createIntersectionObserver = (callback) => (options) => () => {
  if (typeof IntersectionObserver === 'undefined') {
    return { observe: () => {}, disconnect: () => {} };
  }
  
  return new IntersectionObserver((entries) => {
    const visibleEntries = entries
      .filter(entry => entry.isIntersecting)
      .map(entry => ({
        index: parseInt(entry.target.dataset.index || '0', 10),
        height: entry.boundingClientRect.height
      }));
    
    if (visibleEntries.length > 0) {
      callback(visibleEntries)();
    }
  }, options);
};

/**
 * Observe an element for intersection
 */
export const observeIntersection = (observer) => (element) => () => {
  if (observer && observer.observe) {
    observer.observe(element);
  }
};

/**
 * Stop observing an element
 */
export const unobserveIntersection = (observer) => (element) => () => {
  if (observer && observer.unobserve) {
    observer.unobserve(element);
  }
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                             // dom positioning
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Apply transform for GPU-accelerated positioning
 * Uses translate3d for hardware acceleration
 */
export const setItemTransform = (element) => (x) => (y) => () => {
  if (!element) return;
  
  element.style.transform = `translate3d(${x}px, ${y}px, 0)`;
  element.style.willChange = 'transform';
};

/**
 * Batch update item positions using DocumentFragment
 * More efficient than updating DOM one item at a time
 */
export const batchUpdatePositions = (container) => (updates) => () => {
  if (!container) return;
  
  // Use requestAnimationFrame for batching
  requestAnimationFrame(() => {
    updates.forEach(({ index, x, y }) => {
      const element = container.querySelector(`[data-index="${index}"]`);
      if (element) {
        element.style.transform = `translate3d(${x}px, ${y}px, 0)`;
      }
    });
  });
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                              // scroll anchoring
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Get scroll anchor for maintaining position during content changes
 */
export const getScrollAnchor = (container) => () => {
  if (!container) return null;
  
  const scrollTop = container.scrollTop;
  const items = container.querySelectorAll('[data-index]');
  
  for (const item of items) {
    const rect = item.getBoundingClientRect();
    const containerRect = container.getBoundingClientRect();
    
    if (rect.top >= containerRect.top) {
      return {
        index: parseInt(item.dataset.index || '0', 10),
        offset: rect.top - containerRect.top
      };
    }
  }
  
  return null;
};

/**
 * Restore scroll position based on anchor
 */
export const restoreScrollAnchor = (container) => (anchor) => (getItemOffset) => () => {
  if (!container || !anchor) return;
  
  const itemOffset = getItemOffset(anchor.index);
  const newScrollTop = itemOffset - anchor.offset;
  
  container.scrollTop = Math.max(0, newScrollTop);
};
