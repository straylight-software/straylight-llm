// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//                                                      // hydrogen // scroll-area
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

// Custom scrollbar FFI with touch support and auto-hide

// ═══════════════════════════════════════════════════════════════════════════════
//                                                              // scroll control
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Scroll to specific position
 */
export const scrollToImpl = (container) => (x) => (y) => () => {
  if (!container) return;
  
  const viewport = container.querySelector('.scroll-area-viewport');
  if (viewport) {
    viewport.scrollTo({
      left: x,
      top: y,
      behavior: 'smooth'
    });
  }
};

/**
 * Scroll to element by selector
 */
export const scrollToElementImpl = (container) => (selector) => () => {
  if (!container) return;
  
  const viewport = container.querySelector('.scroll-area-viewport');
  const target = container.querySelector(selector);
  
  if (viewport && target) {
    const viewportRect = viewport.getBoundingClientRect();
    const targetRect = target.getBoundingClientRect();
    
    const offsetTop = targetRect.top - viewportRect.top + viewport.scrollTop;
    const offsetLeft = targetRect.left - viewportRect.left + viewport.scrollLeft;
    
    viewport.scrollTo({
      top: offsetTop,
      left: offsetLeft,
      behavior: 'smooth'
    });
  }
};

/**
 * Get current scroll position
 */
export const getScrollPositionImpl = (container) => () => {
  if (!container) return { x: 0, y: 0 };
  
  const viewport = container.querySelector('.scroll-area-viewport');
  if (!viewport) return { x: 0, y: 0 };
  
  return {
    x: viewport.scrollLeft,
    y: viewport.scrollTop
  };
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                             // scrollbar setup
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Initialize scroll area with custom scrollbar support
 */
export const initScrollArea = (container) => (options) => () => {
  if (!container) return { cleanup: () => {} };
  
  const viewport = container.querySelector('.scroll-area-viewport');
  if (!viewport) return { cleanup: () => {} };
  
  let state = {
    isDragging: false,
    dragAxis: null,
    startY: 0,
    startX: 0,
    startScrollTop: 0,
    startScrollLeft: 0,
    hideTimeout: null,
    isHovering: false
  };
  
  const callbacks = [];
  
  // Scroll handler
  const handleScroll = () => {
    const scrollState = {
      scrollTop: viewport.scrollTop,
      scrollLeft: viewport.scrollLeft,
      scrollHeight: viewport.scrollHeight,
      scrollWidth: viewport.scrollWidth,
      clientHeight: viewport.clientHeight,
      clientWidth: viewport.clientWidth
    };
    
    if (options.onScroll) {
      options.onScroll(scrollState)();
    }
    
    // Auto-hide logic
    if (options.autoHide) {
      showScrollbars();
      scheduleHide();
    }
  };
  
  // Show scrollbars
  const showScrollbars = () => {
    const scrollbars = container.querySelectorAll('.scroll-area-scrollbar');
    scrollbars.forEach(sb => {
      sb.classList.remove('opacity-0');
      sb.classList.add('opacity-100');
    });
  };
  
  // Hide scrollbars
  const hideScrollbars = () => {
    if (state.isDragging || state.isHovering) return;
    
    const scrollbars = container.querySelectorAll('.scroll-area-scrollbar');
    scrollbars.forEach(sb => {
      sb.classList.remove('opacity-100');
      sb.classList.add('opacity-0');
    });
  };
  
  // Schedule hide after delay
  const scheduleHide = () => {
    if (state.hideTimeout) {
      clearTimeout(state.hideTimeout);
    }
    state.hideTimeout = setTimeout(hideScrollbars, options.hideDelay || 1000);
  };
  
  // Mouse enter/leave for scrollbar hover
  const handleMouseEnter = () => {
    state.isHovering = true;
    showScrollbars();
    if (state.hideTimeout) {
      clearTimeout(state.hideTimeout);
    }
  };
  
  const handleMouseLeave = () => {
    state.isHovering = false;
    if (options.autoHide) {
      scheduleHide();
    }
  };
  
  // Add event listeners
  viewport.addEventListener('scroll', handleScroll, { passive: true });
  container.addEventListener('mouseenter', handleMouseEnter);
  container.addEventListener('mouseleave', handleMouseLeave);
  
  // Initial state update
  handleScroll();
  
  // Setup scrollbar drag
  setupScrollbarDrag(container, viewport, state);
  
  // Cleanup
  return {
    cleanup: () => {
      viewport.removeEventListener('scroll', handleScroll);
      container.removeEventListener('mouseenter', handleMouseEnter);
      container.removeEventListener('mouseleave', handleMouseLeave);
      if (state.hideTimeout) {
        clearTimeout(state.hideTimeout);
      }
    }
  };
};

/**
 * Setup scrollbar drag handling
 */
const setupScrollbarDrag = (container, viewport, state) => {
  const verticalThumb = container.querySelector('.scroll-area-scrollbar[data-orientation="vertical"] .scroll-area-thumb');
  const horizontalThumb = container.querySelector('.scroll-area-scrollbar[data-orientation="horizontal"] .scroll-area-thumb');
  
  const handleMouseDown = (axis) => (e) => {
    e.preventDefault();
    state.isDragging = true;
    state.dragAxis = axis;
    state.startY = e.clientY;
    state.startX = e.clientX;
    state.startScrollTop = viewport.scrollTop;
    state.startScrollLeft = viewport.scrollLeft;
    
    document.addEventListener('mousemove', handleMouseMove);
    document.addEventListener('mouseup', handleMouseUp);
    document.body.style.userSelect = 'none';
  };
  
  const handleMouseMove = (e) => {
    if (!state.isDragging) return;
    
    if (state.dragAxis === 'vertical') {
      const deltaY = e.clientY - state.startY;
      const scrollbarHeight = container.querySelector('.scroll-area-scrollbar[data-orientation="vertical"]').clientHeight;
      const scrollRatio = viewport.scrollHeight / scrollbarHeight;
      viewport.scrollTop = state.startScrollTop + deltaY * scrollRatio;
    } else if (state.dragAxis === 'horizontal') {
      const deltaX = e.clientX - state.startX;
      const scrollbarWidth = container.querySelector('.scroll-area-scrollbar[data-orientation="horizontal"]').clientWidth;
      const scrollRatio = viewport.scrollWidth / scrollbarWidth;
      viewport.scrollLeft = state.startScrollLeft + deltaX * scrollRatio;
    }
  };
  
  const handleMouseUp = () => {
    state.isDragging = false;
    state.dragAxis = null;
    document.removeEventListener('mousemove', handleMouseMove);
    document.removeEventListener('mouseup', handleMouseUp);
    document.body.style.userSelect = '';
  };
  
  if (verticalThumb) {
    verticalThumb.addEventListener('mousedown', handleMouseDown('vertical'));
  }
  
  if (horizontalThumb) {
    horizontalThumb.addEventListener('mousedown', handleMouseDown('horizontal'));
  }
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                              // touch scrolling
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Setup touch scrolling with momentum
 */
export const setupTouchScroll = (container) => () => {
  if (!container) return { cleanup: () => {} };
  
  const viewport = container.querySelector('.scroll-area-viewport');
  if (!viewport) return { cleanup: () => {} };
  
  let state = {
    isTouching: false,
    startY: 0,
    startX: 0,
    startScrollTop: 0,
    startScrollLeft: 0,
    lastY: 0,
    lastX: 0,
    lastTime: 0,
    velocityY: 0,
    velocityX: 0,
    momentumId: null
  };
  
  const handleTouchStart = (e) => {
    state.isTouching = true;
    state.startY = e.touches[0].clientY;
    state.startX = e.touches[0].clientX;
    state.startScrollTop = viewport.scrollTop;
    state.startScrollLeft = viewport.scrollLeft;
    state.lastY = state.startY;
    state.lastX = state.startX;
    state.lastTime = Date.now();
    state.velocityY = 0;
    state.velocityX = 0;
    
    if (state.momentumId) {
      cancelAnimationFrame(state.momentumId);
      state.momentumId = null;
    }
  };
  
  const handleTouchMove = (e) => {
    if (!state.isTouching) return;
    
    const currentY = e.touches[0].clientY;
    const currentX = e.touches[0].clientX;
    const currentTime = Date.now();
    
    const deltaY = state.lastY - currentY;
    const deltaX = state.lastX - currentX;
    const deltaTime = currentTime - state.lastTime;
    
    if (deltaTime > 0) {
      state.velocityY = deltaY / deltaTime;
      state.velocityX = deltaX / deltaTime;
    }
    
    viewport.scrollTop += deltaY;
    viewport.scrollLeft += deltaX;
    
    state.lastY = currentY;
    state.lastX = currentX;
    state.lastTime = currentTime;
  };
  
  const handleTouchEnd = () => {
    state.isTouching = false;
    
    // Apply momentum scrolling
    const momentum = () => {
      if (Math.abs(state.velocityY) < 0.01 && Math.abs(state.velocityX) < 0.01) {
        return;
      }
      
      viewport.scrollTop += state.velocityY * 16;
      viewport.scrollLeft += state.velocityX * 16;
      
      state.velocityY *= 0.95;
      state.velocityX *= 0.95;
      
      state.momentumId = requestAnimationFrame(momentum);
    };
    
    momentum();
  };
  
  viewport.addEventListener('touchstart', handleTouchStart, { passive: true });
  viewport.addEventListener('touchmove', handleTouchMove, { passive: true });
  viewport.addEventListener('touchend', handleTouchEnd, { passive: true });
  
  return {
    cleanup: () => {
      viewport.removeEventListener('touchstart', handleTouchStart);
      viewport.removeEventListener('touchmove', handleTouchMove);
      viewport.removeEventListener('touchend', handleTouchEnd);
      if (state.momentumId) {
        cancelAnimationFrame(state.momentumId);
      }
    }
  };
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                                   // utilities
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Get scroll dimensions
 */
export const getScrollDimensions = (container) => () => {
  if (!container) {
    return {
      scrollTop: 0,
      scrollLeft: 0,
      scrollHeight: 0,
      scrollWidth: 0,
      clientHeight: 0,
      clientWidth: 0
    };
  }
  
  const viewport = container.querySelector('.scroll-area-viewport');
  if (!viewport) {
    return {
      scrollTop: 0,
      scrollLeft: 0,
      scrollHeight: 0,
      scrollWidth: 0,
      clientHeight: 0,
      clientWidth: 0
    };
  }
  
  return {
    scrollTop: viewport.scrollTop,
    scrollLeft: viewport.scrollLeft,
    scrollHeight: viewport.scrollHeight,
    scrollWidth: viewport.scrollWidth,
    clientHeight: viewport.clientHeight,
    clientWidth: viewport.clientWidth
  };
};

/**
 * Create resize observer for scroll area
 */
export const createScrollAreaResizeObserver = (callback) => () => {
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
 * Observe scroll area for size changes
 */
export const observeScrollArea = (observer) => (container) => () => {
  if (!observer || !container) return;
  
  const viewport = container.querySelector('.scroll-area-viewport');
  if (viewport) {
    observer.observe(viewport);
  }
};
