// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//                                                        // hydrogen // masonry
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

// Masonry layout FFI for true horizontal-first ordering
// CSS columns provide vertical-first ordering, this JS implementation
// provides Pinterest-style horizontal ordering.

/**
 * Initialize masonry layout on elements matching selector
 * @param {string} selector - CSS selector for masonry container
 * @returns {MasonryHandle} Handle for controlling the masonry layout
 */
export const initMasonry = (selector) => {
  const container = document.querySelector(selector);
  if (!container) {
    console.warn(`Masonry: No element found for selector "${selector}"`);
    return { container: null, items: [], columnHeights: [] };
  }

  const handle = {
    container,
    items: [],
    columnHeights: [],
    resizeObserver: null,
    gap: 16
  };

  // Parse gap from container classes
  const gapMatch = container.className.match(/gap-(\d+)/);
  if (gapMatch) {
    handle.gap = parseInt(gapMatch[1], 10) * 4; // Tailwind spacing scale
  }

  // Initial layout
  layoutMasonry(handle);

  // Set up resize observer for responsive relayout
  handle.resizeObserver = new ResizeObserver(() => {
    layoutMasonry(handle);
  });
  handle.resizeObserver.observe(container);

  // Observe for new children
  const mutationObserver = new MutationObserver(() => {
    layoutMasonry(handle);
  });
  mutationObserver.observe(container, { childList: true });

  handle.mutationObserver = mutationObserver;

  return handle;
};

/**
 * Layout items in masonry grid
 * @param {MasonryHandle} handle
 */
function layoutMasonry(handle) {
  const { container, gap } = handle;
  if (!container) return;

  const items = Array.from(container.children);
  if (items.length === 0) return;

  // Calculate number of columns based on container width
  const containerWidth = container.offsetWidth;
  const computedStyle = getComputedStyle(container);
  const columnCount = parseInt(computedStyle.columnCount, 10) || 3;
  const columnWidth = (containerWidth - (gap * (columnCount - 1))) / columnCount;

  // Reset container to grid layout for JS masonry
  container.style.display = 'grid';
  container.style.gridTemplateColumns = `repeat(${columnCount}, 1fr)`;
  container.style.columnCount = 'auto';

  // Track column heights
  const columnHeights = new Array(columnCount).fill(0);

  // Position each item
  items.forEach((item, index) => {
    // Find shortest column
    const shortestColumn = columnHeights.indexOf(Math.min(...columnHeights));
    
    // Position item
    item.style.gridColumn = String(shortestColumn + 1);
    item.style.gridRow = 'auto';
    
    // Update column height
    const itemHeight = item.offsetHeight;
    columnHeights[shortestColumn] += itemHeight + gap;
  });

  handle.columnHeights = columnHeights;
  handle.items = items;
}

/**
 * Re-layout masonry after content changes
 * @param {MasonryHandle} handle
 */
export const relayoutImpl = (handle) => {
  layoutMasonry(handle);
};

/**
 * Destroy masonry instance and clean up observers
 * @param {MasonryHandle} handle
 */
export const destroyMasonry = (handle) => {
  if (handle.resizeObserver) {
    handle.resizeObserver.disconnect();
  }
  if (handle.mutationObserver) {
    handle.mutationObserver.disconnect();
  }
  
  // Reset container styles
  if (handle.container) {
    handle.container.style.display = '';
    handle.container.style.gridTemplateColumns = '';
  }
};

/**
 * Get current column heights
 * @param {MasonryHandle} handle
 * @returns {number[]}
 */
export const getColumnHeights = (handle) => {
  return handle.columnHeights;
};
