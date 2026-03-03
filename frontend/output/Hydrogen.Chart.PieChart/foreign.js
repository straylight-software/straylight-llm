// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//                                                       // hydrogen // piechart
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

// Pie/Donut Chart animation and interactivity FFI

// ═══════════════════════════════════════════════════════════════════════════════
//                                                                   // animation
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Animate pie slices appearing
 * @param {string} containerId - Container element ID
 * @param {number} duration - Animation duration in ms
 */
export const animateSlicesImpl = (containerId) => (duration) => () => {
  const container = document.getElementById(containerId);
  if (!container) return;

  const slices = container.querySelectorAll('.pie-slice path');
  
  slices.forEach((slice, index) => {
    // Scale from center animation
    slice.style.transformOrigin = 'center';
    slice.style.transform = 'scale(0)';
    slice.style.opacity = '0';
    
    const delay = index * 80;
    
    setTimeout(() => {
      slice.style.transition = `transform ${duration}ms cubic-bezier(0.34, 1.56, 0.64, 1), opacity ${duration * 0.5}ms ease-out`;
      slice.style.transform = 'scale(1)';
      slice.style.opacity = '1';
    }, delay);
  });
};

/**
 * Animate slices with rotation
 * @param {string} containerId - Container element ID
 * @param {number} duration - Animation duration in ms
 */
export const animateSlicesRotateImpl = (containerId) => (duration) => () => {
  const container = document.getElementById(containerId);
  if (!container) return;

  const chartGroup = container.querySelector('g');
  if (!chartGroup) return;

  // Rotate entire chart
  chartGroup.style.transformOrigin = 'center';
  chartGroup.style.transform = 'rotate(-180deg) scale(0.8)';
  chartGroup.style.opacity = '0';
  
  requestAnimationFrame(() => {
    chartGroup.style.transition = `transform ${duration}ms cubic-bezier(0.34, 1.56, 0.64, 1), opacity ${duration * 0.5}ms ease-out`;
    chartGroup.style.transform = 'rotate(0deg) scale(1)';
    chartGroup.style.opacity = '1';
  });
};

/**
 * Reset slice animation
 * @param {string} containerId - Container element ID
 */
export const resetSlicesImpl = (containerId) => () => {
  const container = document.getElementById(containerId);
  if (!container) return;

  const slices = container.querySelectorAll('.pie-slice path');
  
  slices.forEach((slice) => {
    slice.style.transition = 'none';
    slice.style.transform = 'scale(0)';
    slice.style.opacity = '0';
  });
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                              // explode effect
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Explode a slice outward from center
 * @param {string} containerId - Container element ID
 * @param {number} index - Slice index
 * @param {number} distance - Explode distance in pixels
 */
export const explodeSliceImpl = (containerId) => (index) => (distance) => () => {
  const container = document.getElementById(containerId);
  if (!container) return;

  const slices = container.querySelectorAll('.pie-slice');
  
  slices.forEach((slice, i) => {
    if (i === index) {
      // Get slice center angle from data attribute or calculate
      const path = slice.querySelector('path');
      if (!path) return;
      
      // Get bounding box center relative to SVG center
      const svg = container.querySelector('svg');
      if (!svg) return;
      
      const viewBox = svg.viewBox.baseVal;
      const centerX = viewBox.width / 2;
      const centerY = viewBox.height / 2;
      
      // Calculate slice midpoint angle (simplified - uses transform)
      const pathBBox = path.getBBox();
      const sliceCenterX = pathBBox.x + pathBBox.width / 2;
      const sliceCenterY = pathBBox.y + pathBBox.height / 2;
      
      // Direction from center to slice center
      const dx = sliceCenterX - centerX;
      const dy = sliceCenterY - centerY;
      const length = Math.sqrt(dx * dx + dy * dy);
      
      if (length > 0) {
        const translateX = (dx / length) * distance;
        const translateY = (dy / length) * distance;
        
        path.style.transition = 'transform 200ms ease-out';
        path.style.transform = `translate(${translateX}px, ${translateY}px)`;
      }
    }
  });
};

/**
 * Reset exploded slices
 * @param {string} containerId - Container element ID
 */
export const resetExplodeImpl = (containerId) => () => {
  const container = document.getElementById(containerId);
  if (!container) return;

  const paths = container.querySelectorAll('.pie-slice path');
  
  paths.forEach((path) => {
    path.style.transition = 'transform 200ms ease-out';
    path.style.transform = 'translate(0, 0)';
  });
};

/**
 * Initialize click-to-explode behavior
 * @param {string} containerId - Container element ID
 * @param {number} distance - Explode distance
 * @param {function} onClick - Callback when slice clicked
 */
export const initExplodeOnClickImpl = (containerId) => (distance) => (onClick) => () => {
  const container = document.getElementById(containerId);
  if (!container) return () => {};

  let explodedIndex = -1;

  const handleClick = (e) => {
    const slice = e.target.closest('.pie-slice');
    if (!slice) {
      // Click outside - reset all
      resetExplodeImpl(containerId)();
      explodedIndex = -1;
      onClick(-1)();
      return;
    }

    const index = parseInt(slice.getAttribute('data-index'), 10);
    
    if (index === explodedIndex) {
      // Click same slice - collapse
      resetExplodeImpl(containerId)();
      explodedIndex = -1;
      onClick(-1)();
    } else {
      // Click new slice - explode it
      resetExplodeImpl(containerId)();
      explodeSliceImpl(containerId)(index)(distance)();
      explodedIndex = index;
      onClick(index)();
    }
  };

  container.addEventListener('click', handleClick);

  return () => {
    container.removeEventListener('click', handleClick);
  };
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                                    // tooltips
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Initialize tooltips for pie chart
 * @param {string} containerId - Container element ID
 * @param {Array<{label: string, value: number, percentage: number}>} data - Slice data
 */
export const initTooltipsImpl = (containerId) => (data) => () => {
  const container = document.getElementById(containerId);
  if (!container) return () => {};

  let tooltip = null;

  const createTooltip = () => {
    tooltip = document.createElement('div');
    tooltip.id = containerId + '-tooltip';
    tooltip.className = 'fixed z-50 px-3 py-2 text-sm bg-popover text-popover-foreground rounded-lg shadow-lg border pointer-events-none opacity-0 transition-opacity';
    document.body.appendChild(tooltip);
  };

  const showTooltip = (e, index) => {
    if (!tooltip) createTooltip();
    if (index < 0 || index >= data.length) return;

    const item = data[index];
    tooltip.innerHTML = `
      <div class="font-medium">${item.label}</div>
      <div class="text-muted-foreground">${item.value.toLocaleString()} (${item.percentage.toFixed(1)}%)</div>
    `;

    tooltip.style.left = `${e.clientX + 10}px`;
    tooltip.style.top = `${e.clientY + 10}px`;
    tooltip.style.opacity = '1';
  };

  const hideTooltip = () => {
    if (tooltip) {
      tooltip.style.opacity = '0';
    }
  };

  const handleMouseMove = (e) => {
    const slice = e.target.closest('.pie-slice');
    if (slice) {
      const index = parseInt(slice.getAttribute('data-index'), 10);
      showTooltip(e, index);
    } else {
      hideTooltip();
    }
  };

  const handleMouseLeave = () => {
    hideTooltip();
  };

  container.addEventListener('mousemove', handleMouseMove);
  container.addEventListener('mouseleave', handleMouseLeave);

  return () => {
    container.removeEventListener('mousemove', handleMouseMove);
    container.removeEventListener('mouseleave', handleMouseLeave);
    if (tooltip) tooltip.remove();
  };
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                                 // hover effects
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Highlight a slice on hover
 * @param {string} containerId - Container element ID
 * @param {number} index - Slice index
 */
export const highlightSliceImpl = (containerId) => (index) => () => {
  const container = document.getElementById(containerId);
  if (!container) return;

  const slices = container.querySelectorAll('.pie-slice path');
  
  slices.forEach((path, i) => {
    if (i === index) {
      path.style.filter = 'brightness(1.1) drop-shadow(0 2px 4px rgba(0,0,0,0.2))';
      path.style.transform = 'scale(1.02)';
    } else {
      path.style.opacity = '0.6';
    }
  });
};

/**
 * Clear slice highlights
 * @param {string} containerId - Container element ID
 */
export const clearHighlightsImpl = (containerId) => () => {
  const container = document.getElementById(containerId);
  if (!container) return;

  const slices = container.querySelectorAll('.pie-slice path');
  
  slices.forEach((path) => {
    path.style.filter = '';
    path.style.transform = '';
    path.style.opacity = '';
  });
};

/**
 * Initialize hover effects
 * @param {string} containerId - Container element ID
 */
export const initHoverEffectsImpl = (containerId) => () => {
  const container = document.getElementById(containerId);
  if (!container) return () => {};

  const handleMouseEnter = (e) => {
    const slice = e.target.closest('.pie-slice');
    if (slice) {
      const index = parseInt(slice.getAttribute('data-index'), 10);
      highlightSliceImpl(containerId)(index)();
    }
  };

  const handleMouseLeave = () => {
    clearHighlightsImpl(containerId)();
  };

  container.addEventListener('mouseenter', handleMouseEnter, true);
  container.addEventListener('mouseleave', handleMouseLeave);

  return () => {
    container.removeEventListener('mouseenter', handleMouseEnter, true);
    container.removeEventListener('mouseleave', handleMouseLeave);
  };
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                                  // utilities
// ═══════════════════════════════════════════════════════════════════════════════

// NOTE: findSliceAtAngle, normalizeAngle, angleInRange, computeSliceAngles,
// and computePercentages are now pure PureScript implementations in
// Hydrogen.Chart.PieChart (no FFI required).

/**
 * Calculate slice angle from mouse position
 * BROWSER BOUNDARY: Requires getBoundingClientRect() for center calculation.
 * The atan2 calculation itself is pure, but getting the center requires DOM.
 * @param {string} containerId - Container element ID
 * @param {number} mouseX - Mouse X position
 * @param {number} mouseY - Mouse Y position
 * @returns {number} - Angle in radians
 */
export const getAngleFromMouseImpl = (containerId) => (mouseX) => (mouseY) => () => {
  const container = document.getElementById(containerId);
  if (!container) return 0;

  const svg = container.querySelector('svg');
  if (!svg) return 0;

  const rect = svg.getBoundingClientRect();
  const centerX = rect.left + rect.width / 2;
  const centerY = rect.top + rect.height / 2;

  return Math.atan2(mouseY - centerY, mouseX - centerX);
};
