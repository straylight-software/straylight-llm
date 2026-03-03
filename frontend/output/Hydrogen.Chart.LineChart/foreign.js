// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//                                                      // hydrogen // linechart
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

// Line Chart animation and interactivity FFI

// ═══════════════════════════════════════════════════════════════════════════════
//                                                              // line animation
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Animate line drawing from start to end
 * @param {string} containerId - Container element ID
 * @param {number} duration - Animation duration in ms
 */
export const animateLineImpl = (containerId) => (duration) => () => {
  const container = document.getElementById(containerId);
  if (!container) return;

  const paths = container.querySelectorAll('path[data-animate="true"]');
  
  paths.forEach((path) => {
    const length = path.getTotalLength();
    
    // Set up initial state
    path.style.strokeDasharray = length;
    path.style.strokeDashoffset = length;
    
    // Trigger animation
    path.style.transition = `stroke-dashoffset ${duration}ms ease-out`;
    
    // Force reflow
    path.getBoundingClientRect();
    
    // Animate
    path.style.strokeDashoffset = '0';
  });
};

/**
 * Reset line animation
 * @param {string} containerId - Container element ID
 */
export const resetLineImpl = (containerId) => () => {
  const container = document.getElementById(containerId);
  if (!container) return;

  const paths = container.querySelectorAll('path[data-animate="true"]');
  
  paths.forEach((path) => {
    const length = path.getTotalLength();
    path.style.transition = 'none';
    path.style.strokeDasharray = length;
    path.style.strokeDashoffset = length;
  });
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                                   // crosshair
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Initialize crosshair for line chart
 * @param {string} containerId - Container element ID
 * @param {object} padding - Chart padding { top, right, bottom, left }
 * @param {function} onMove - Callback with cursor position
 */
export const initCrosshairImpl = (containerId) => (padding) => (onMove) => () => {
  const container = document.getElementById(containerId);
  if (!container) return () => {};

  const svg = container.querySelector('svg');
  if (!svg) return () => {};

  // Create crosshair elements
  const vLine = document.createElementNS('http://www.w3.org/2000/svg', 'line');
  vLine.setAttribute('stroke', 'currentColor');
  vLine.setAttribute('stroke-width', '1');
  vLine.setAttribute('stroke-dasharray', '4,4');
  vLine.setAttribute('class', 'text-muted-foreground/50');
  vLine.style.display = 'none';
  svg.appendChild(vLine);

  const hLine = document.createElementNS('http://www.w3.org/2000/svg', 'line');
  hLine.setAttribute('stroke', 'currentColor');
  hLine.setAttribute('stroke-width', '1');
  hLine.setAttribute('stroke-dasharray', '4,4');
  hLine.setAttribute('class', 'text-muted-foreground/50');
  hLine.style.display = 'none';
  svg.appendChild(hLine);

  const handleMouseMove = (e) => {
    const rect = svg.getBoundingClientRect();
    const x = e.clientX - rect.left;
    const y = e.clientY - rect.top;

    // Convert to SVG coordinates
    const viewBox = svg.viewBox.baseVal;
    const scaleX = viewBox.width / rect.width;
    const scaleY = viewBox.height / rect.height;
    const svgX = x * scaleX;
    const svgY = y * scaleY;

    // Check if within chart area
    if (svgX >= padding.left && svgX <= viewBox.width - padding.right &&
        svgY >= padding.top && svgY <= viewBox.height - padding.bottom) {
      
      vLine.style.display = '';
      vLine.setAttribute('x1', svgX);
      vLine.setAttribute('y1', padding.top);
      vLine.setAttribute('x2', svgX);
      vLine.setAttribute('y2', viewBox.height - padding.bottom);

      hLine.style.display = '';
      hLine.setAttribute('x1', padding.left);
      hLine.setAttribute('y1', svgY);
      hLine.setAttribute('x2', viewBox.width - padding.right);
      hLine.setAttribute('y2', svgY);

      onMove({ x: svgX, y: svgY, visible: true })();
    } else {
      vLine.style.display = 'none';
      hLine.style.display = 'none';
      onMove({ x: 0, y: 0, visible: false })();
    }
  };

  const handleMouseLeave = () => {
    vLine.style.display = 'none';
    hLine.style.display = 'none';
    onMove({ x: 0, y: 0, visible: false })();
  };

  svg.addEventListener('mousemove', handleMouseMove);
  svg.addEventListener('mouseleave', handleMouseLeave);

  return () => {
    svg.removeEventListener('mousemove', handleMouseMove);
    svg.removeEventListener('mouseleave', handleMouseLeave);
    vLine.remove();
    hLine.remove();
  };
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                           // nearest point
// ═══════════════════════════════════════════════════════════════════════════════

// NOTE: findNearestPoint and findNearestPointX are now pure PureScript
// implementations in Hydrogen.Chart.LineChart (no FFI required).
// See: distanceEuclidean, distanceX, findNearestPoint, findNearestPointX

// ═══════════════════════════════════════════════════════════════════════════════
//                                                                    // tooltips
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Show tooltip at position
 * @param {string} containerId - Container element ID
 * @param {number} x - X position in pixels
 * @param {number} y - Y position in pixels
 * @param {string} content - Tooltip HTML content
 */
export const showTooltipImpl = (containerId) => (x) => (y) => (content) => () => {
  let tooltip = document.getElementById(containerId + '-tooltip');
  
  if (!tooltip) {
    tooltip = document.createElement('div');
    tooltip.id = containerId + '-tooltip';
    tooltip.className = 'absolute z-50 px-3 py-2 text-sm bg-popover text-popover-foreground rounded-lg shadow-lg border pointer-events-none';
    document.body.appendChild(tooltip);
  }
  
  tooltip.innerHTML = content;
  
  // Position tooltip
  const rect = tooltip.getBoundingClientRect();
  let left = x - rect.width / 2;
  let top = y - rect.height - 10;
  
  // Ensure tooltip stays in viewport
  if (left < 10) left = 10;
  if (top < 10) top = y + 10;
  
  tooltip.style.left = `${left}px`;
  tooltip.style.top = `${top}px`;
  tooltip.style.opacity = '1';
  tooltip.style.visibility = 'visible';
  tooltip.style.transform = 'translateY(0)';
  tooltip.style.transition = 'opacity 150ms, transform 150ms';
};

/**
 * Hide tooltip
 * @param {string} containerId - Container element ID
 */
export const hideTooltipImpl = (containerId) => () => {
  const tooltip = document.getElementById(containerId + '-tooltip');
  if (tooltip) {
    tooltip.style.opacity = '0';
    tooltip.style.visibility = 'hidden';
    tooltip.style.transform = 'translateY(4px)';
  }
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                                // highlight dot
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Highlight a data point dot
 * @param {string} containerId - Container element ID
 * @param {number} index - Dot index to highlight
 */
export const highlightDotImpl = (containerId) => (index) => () => {
  const container = document.getElementById(containerId);
  if (!container) return;

  const dots = container.querySelectorAll('circle');
  
  dots.forEach((dot, i) => {
    if (i === index) {
      dot.setAttribute('r', String(parseFloat(dot.getAttribute('r')) * 1.5));
      dot.style.filter = 'drop-shadow(0 0 4px currentColor)';
    }
  });
};

/**
 * Clear dot highlights
 * @param {string} containerId - Container element ID
 * @param {number} originalRadius - Original dot radius
 */
export const clearDotHighlightsImpl = (containerId) => (originalRadius) => () => {
  const container = document.getElementById(containerId);
  if (!container) return;

  const dots = container.querySelectorAll('circle');
  
  dots.forEach((dot) => {
    dot.setAttribute('r', String(originalRadius));
    dot.style.filter = '';
  });
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                               // path utilities
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Get total length of an SVG path
 * @param {string} pathId - Path element ID
 * @returns {number} - Total length
 */
export const getPathLengthImpl = (pathId) => () => {
  const path = document.getElementById(pathId);
  if (!path || typeof path.getTotalLength !== 'function') return 0;
  return path.getTotalLength();
};

/**
 * Get point at length along path
 * @param {string} pathId - Path element ID
 * @param {number} length - Distance along path
 * @returns {{x: number, y: number}}
 */
export const getPointAtLengthImpl = (pathId) => (length) => () => {
  const path = document.getElementById(pathId);
  if (!path || typeof path.getPointAtLength !== 'function') {
    return { x: 0, y: 0 };
  }
  const point = path.getPointAtLength(length);
  return { x: point.x, y: point.y };
};
