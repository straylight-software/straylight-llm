// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//                                                 // hydrogen // infinite-scroll
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

// Infinite scroll FFI using Intersection Observer API

// ═══════════════════════════════════════════════════════════════════════════════
//                                                        // intersection observer
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Create an intersection observer for sentinel elements
 */
export const createSentinelObserver = (callback) => (options) => () => {
  if (typeof IntersectionObserver === 'undefined') {
    // Fallback for environments without IntersectionObserver
    console.warn('IntersectionObserver not supported, infinite scroll will not work');
    return { observe: () => {}, disconnect: () => {}, unobserve: () => {} };
  }
  
  return new IntersectionObserver((entries) => {
    for (const entry of entries) {
      if (entry.isIntersecting) {
        callback()();
      }
    }
  }, {
    root: options.root || null,
    rootMargin: options.rootMargin || '0px',
    threshold: options.threshold || 0
  });
};

/**
 * Observe a sentinel element
 */
export const observeSentinel = (observer) => (element) => () => {
  if (observer && observer.observe && element) {
    observer.observe(element);
  }
};

/**
 * Stop observing a sentinel
 */
export const unobserveSentinel = (observer) => (element) => () => {
  if (observer && observer.unobserve && element) {
    observer.unobserve(element);
  }
};

/**
 * Disconnect observer entirely
 */
export const disconnectObserver = (observer) => () => {
  if (observer && observer.disconnect) {
    observer.disconnect();
  }
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                          // scroll restoration
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Save current scroll position
 */
export const saveScrollPositionImpl = (container) => () => {
  if (!container) {
    return {
      scrollTop: 0,
      scrollHeight: 0,
      clientHeight: 0,
      anchorIndex: null,
      anchorOffset: 0
    };
  }
  
  const scrollTop = container.scrollTop;
  const scrollHeight = container.scrollHeight;
  const clientHeight = container.clientHeight;
  
  // Find anchor element (first visible item)
  let anchorIndex = null;
  let anchorOffset = 0;
  
  const items = container.querySelectorAll('[data-index]');
  const containerRect = container.getBoundingClientRect();
  
  for (const item of items) {
    const rect = item.getBoundingClientRect();
    if (rect.top >= containerRect.top) {
      anchorIndex = parseInt(item.dataset.index, 10);
      anchorOffset = rect.top - containerRect.top;
      break;
    }
  }
  
  return { scrollTop, scrollHeight, clientHeight, anchorIndex, anchorOffset };
};

/**
 * Restore scroll position
 */
export const restoreScrollPositionImpl = (container) => (position) => () => {
  if (!container || !position) return;
  
  // If we have an anchor, use it for restoration
  if (position.anchorIndex !== null) {
    const anchorElement = container.querySelector(`[data-index="${position.anchorIndex}"]`);
    
    if (anchorElement) {
      const containerRect = container.getBoundingClientRect();
      const anchorRect = anchorElement.getBoundingClientRect();
      const currentOffset = anchorRect.top - containerRect.top;
      const adjustment = currentOffset - position.anchorOffset;
      
      container.scrollTop += adjustment;
      return;
    }
  }
  
  // Fallback to scroll height difference
  const heightDiff = container.scrollHeight - position.scrollHeight;
  container.scrollTop = position.scrollTop + heightDiff;
};

/**
 * Scroll to bottom
 */
export const scrollToBottomImpl = (container) => () => {
  if (!container) return;
  container.scrollTop = container.scrollHeight - container.clientHeight;
};

/**
 * Scroll to top
 */
export const scrollToTopImpl = (container) => () => {
  if (!container) return;
  container.scrollTop = 0;
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                            // scroll utilities
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Check if user is near bottom of scroll container
 */
export const isNearBottom = (container) => (threshold) => () => {
  if (!container) return false;
  
  const { scrollTop, scrollHeight, clientHeight } = container;
  const distanceFromBottom = scrollHeight - scrollTop - clientHeight;
  const thresholdPx = clientHeight * threshold;
  
  return distanceFromBottom <= thresholdPx;
};

/**
 * Check if user is near top of scroll container
 */
export const isNearTop = (container) => (threshold) => () => {
  if (!container) return false;
  
  const { scrollTop, clientHeight } = container;
  const thresholdPx = clientHeight * threshold;
  
  return scrollTop <= thresholdPx;
};

/**
 * Get scroll percentage (0-1)
 */
export const getScrollPercentage = (container) => () => {
  if (!container) return 0;
  
  const { scrollTop, scrollHeight, clientHeight } = container;
  const maxScroll = scrollHeight - clientHeight;
  
  if (maxScroll <= 0) return 0;
  return scrollTop / maxScroll;
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                       // bi-directional helpers
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Maintain scroll position when prepending content
 * Call this before adding content to the top
 */
export const prepareForPrepend = (container) => () => {
  if (!container) return { scrollHeight: 0, scrollTop: 0 };
  
  return {
    scrollHeight: container.scrollHeight,
    scrollTop: container.scrollTop
  };
};

/**
 * Adjust scroll after prepending content
 * Call this after adding content to the top
 */
export const adjustAfterPrepend = (container) => (prevState) => () => {
  if (!container || !prevState) return;
  
  const heightDiff = container.scrollHeight - prevState.scrollHeight;
  container.scrollTop = prevState.scrollTop + heightDiff;
};

/**
 * Smart scroll for chat-like interfaces
 * If user is at bottom, stay at bottom after new content
 * Otherwise, maintain current position
 */
export const smartScrollForNewContent = (container) => () => {
  if (!container) return null;
  
  const { scrollTop, scrollHeight, clientHeight } = container;
  const isAtBottom = scrollHeight - scrollTop - clientHeight < 50;
  
  return {
    wasAtBottom: isAtBottom,
    restore: () => {
      if (isAtBottom) {
        container.scrollTop = container.scrollHeight - container.clientHeight;
      }
    }
  };
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                        // performance utilities
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Debounced scroll handler
 */
export const createDebouncedScrollHandler = (callback) => (delay) => () => {
  let timeout = null;
  
  return (event) => {
    if (timeout) clearTimeout(timeout);
    
    timeout = setTimeout(() => {
      callback(event.target.scrollTop)();
    }, delay);
  };
};

/**
 * Throttled scroll handler for smoother updates
 */
export const createThrottledScrollHandler = (callback) => (interval) => () => {
  let lastCall = 0;
  let scheduledCall = null;
  
  return (event) => {
    const now = Date.now();
    const scrollTop = event.target.scrollTop;
    
    if (now - lastCall >= interval) {
      lastCall = now;
      callback(scrollTop)();
    } else if (!scheduledCall) {
      scheduledCall = setTimeout(() => {
        lastCall = Date.now();
        scheduledCall = null;
        callback(scrollTop)();
      }, interval - (now - lastCall));
    }
  };
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                              // loading states
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Disable scroll during loading to prevent multiple triggers
 */
export const disableScrollDuringLoad = (container) => () => {
  if (!container) return () => {};
  
  const originalOverflow = container.style.overflow;
  container.style.overflow = 'hidden';
  
  return () => {
    container.style.overflow = originalOverflow;
  };
};

/**
 * Lock scroll position during content update
 */
export const lockScrollPosition = (container) => () => {
  if (!container) return () => {};
  
  const scrollTop = container.scrollTop;
  
  return () => {
    container.scrollTop = scrollTop;
  };
};
