// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//                                                       // hydrogen // sortable
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

// Sortable lists with drag and drop reordering, keyboard support,
// and smooth animations

// ═══════════════════════════════════════════════════════════════════════════════
//                                                              // sortable state
// ═══════════════════════════════════════════════════════════════════════════════

let sortState = null;
let placeholder = null;
let animationFrame = null;

export const getSortStateImpl = () => {
  return sortState;
};

export const setSortStateImpl = (state) => () => {
  sortState = state;
};

export const clearSortStateImpl = () => {
  sortState = null;
  removePlaceholder();
  if (animationFrame) {
    cancelAnimationFrame(animationFrame);
    animationFrame = null;
  }
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                              // placeholder
// ═══════════════════════════════════════════════════════════════════════════════

export const createPlaceholderImpl = (width) => (height) => (className) => () => {
  removePlaceholder();
  
  placeholder = document.createElement("div");
  placeholder.className = className;
  placeholder.style.cssText = `
    width: ${width}px;
    height: ${height}px;
    pointer-events: none;
  `;
  placeholder.setAttribute("data-sort-placeholder", "true");
  
  return placeholder;
};

export const insertPlaceholderImpl = (container) => (index) => () => {
  if (!placeholder) return;
  
  const items = container.querySelectorAll("[data-sortable-item]:not([data-sort-placeholder])");
  
  if (index >= items.length) {
    container.appendChild(placeholder);
  } else {
    container.insertBefore(placeholder, items[index]);
  }
};

export const removePlaceholderImpl = () => {
  removePlaceholder();
};

function removePlaceholder() {
  if (placeholder && placeholder.parentNode) {
    placeholder.parentNode.removeChild(placeholder);
  }
  placeholder = null;
}

// ═══════════════════════════════════════════════════════════════════════════════
//                                                           // sortable list
// ═══════════════════════════════════════════════════════════════════════════════

export const initSortableImpl = (container) => (config) => (callbacks) => () => {
  const isHorizontal = config.direction === "horizontal";
  let draggedItem = null;
  let draggedIndex = -1;
  let currentIndex = -1;
  let startX = 0;
  let startY = 0;
  let offsetX = 0;
  let offsetY = 0;
  let ghost = null;
  
  const getItems = () => {
    return Array.from(container.querySelectorAll("[data-sortable-item]:not([data-sort-placeholder])"));
  };
  
  const getItemIndex = (item) => {
    const items = getItems();
    return items.indexOf(item);
  };
  
  const getDropIndex = (x, y) => {
    const items = getItems();
    
    for (let i = 0; i < items.length; i++) {
      const item = items[i];
      if (item === draggedItem) continue;
      
      const rect = item.getBoundingClientRect();
      const center = isHorizontal 
        ? rect.left + rect.width / 2
        : rect.top + rect.height / 2;
      const position = isHorizontal ? x : y;
      
      if (position < center) {
        return i;
      }
    }
    
    return items.length;
  };
  
  const animateItems = (excludeIndex) => {
    const items = getItems();
    
    items.forEach((item, i) => {
      if (i === excludeIndex) return;
      
      item.style.transition = "transform 200ms ease";
      
      // Reset transform after animation
      setTimeout(() => {
        item.style.transition = "";
        item.style.transform = "";
      }, 200);
    });
  };
  
  const createGhost = (item, x, y) => {
    const rect = item.getBoundingClientRect();
    ghost = item.cloneNode(true);
    
    ghost.style.cssText = `
      position: fixed;
      left: ${rect.left}px;
      top: ${rect.top}px;
      width: ${rect.width}px;
      height: ${rect.height}px;
      opacity: 0.8;
      pointer-events: none;
      z-index: 10000;
      transform: scale(1.02);
      box-shadow: 0 10px 25px rgba(0, 0, 0, 0.15);
      transition: none;
    `;
    
    ghost.setAttribute("data-sort-ghost", "true");
    document.body.appendChild(ghost);
    
    return ghost;
  };
  
  const updateGhost = (x, y) => {
    if (!ghost) return;
    ghost.style.left = `${x - offsetX}px`;
    ghost.style.top = `${y - offsetY}px`;
  };
  
  const removeGhost = () => {
    if (ghost && ghost.parentNode) {
      ghost.parentNode.removeChild(ghost);
    }
    ghost = null;
  };
  
  const handleDragStart = (item, clientX, clientY) => {
    if (item.hasAttribute("data-sortable-disabled")) return;
    
    const rect = item.getBoundingClientRect();
    draggedItem = item;
    draggedIndex = getItemIndex(item);
    currentIndex = draggedIndex;
    startX = clientX;
    startY = clientY;
    offsetX = clientX - rect.left;
    offsetY = clientY - rect.top;
    
    // Set state
    sortState = {
      container: container,
      item: item,
      fromIndex: draggedIndex,
      toIndex: currentIndex,
      listId: config.listId
    };
    
    // Visual feedback
    item.setAttribute("data-sorting", "true");
    item.style.opacity = "0.4";
    
    // Create ghost
    if (config.showGhost) {
      createGhost(item, clientX, clientY);
    }
    
    // Create placeholder
    if (config.showPlaceholder) {
      createPlaceholderImpl(rect.width)(rect.height)(config.placeholderClass)();
      insertPlaceholderImpl(container)(draggedIndex)();
    }
    
    callbacks.onSortStart({
      item: item,
      index: draggedIndex,
      listId: config.listId
    })();
  };
  
  const handleDragMove = (clientX, clientY) => {
    if (!draggedItem) return;
    
    // Update ghost position
    updateGhost(clientX, clientY);
    
    // Calculate new index
    const newIndex = getDropIndex(clientX, clientY);
    
    if (newIndex !== currentIndex) {
      currentIndex = newIndex;
      sortState.toIndex = newIndex;
      
      // Move placeholder
      if (placeholder) {
        insertPlaceholderImpl(container)(newIndex)();
      }
      
      // Animate items
      if (config.animate) {
        animateItems(draggedIndex);
      }
      
      callbacks.onSortMove({
        item: draggedItem,
        fromIndex: draggedIndex,
        toIndex: newIndex,
        listId: config.listId
      })();
    }
  };
  
  const handleDragEnd = () => {
    if (!draggedItem) return;
    
    const finalIndex = currentIndex;
    
    // Reset item
    draggedItem.removeAttribute("data-sorting");
    draggedItem.style.opacity = "";
    
    // Remove ghost and placeholder
    removeGhost();
    removePlaceholder();
    
    // Fire reorder callback if position changed
    if (finalIndex !== draggedIndex) {
      callbacks.onReorder({
        item: draggedItem,
        oldIndex: draggedIndex,
        newIndex: finalIndex > draggedIndex ? finalIndex - 1 : finalIndex,
        listId: config.listId
      })();
    }
    
    callbacks.onSortEnd({
      item: draggedItem,
      fromIndex: draggedIndex,
      toIndex: finalIndex,
      listId: config.listId
    })();
    
    // Clear state
    draggedItem = null;
    draggedIndex = -1;
    currentIndex = -1;
    clearSortStateImpl();
  };
  
  // Mouse events
  const onMouseDown = (e) => {
    const item = e.target.closest("[data-sortable-item]");
    if (!item) return;
    
    // Check for handle
    if (config.handleSelector) {
      const handle = e.target.closest(config.handleSelector);
      if (!handle) return;
    }
    
    e.preventDefault();
    handleDragStart(item, e.clientX, e.clientY);
    
    document.addEventListener("mousemove", onMouseMove);
    document.addEventListener("mouseup", onMouseUp);
  };
  
  const onMouseMove = (e) => {
    e.preventDefault();
    handleDragMove(e.clientX, e.clientY);
  };
  
  const onMouseUp = () => {
    handleDragEnd();
    document.removeEventListener("mousemove", onMouseMove);
    document.removeEventListener("mouseup", onMouseUp);
  };
  
  // Touch events
  const onTouchStart = (e) => {
    const item = e.target.closest("[data-sortable-item]");
    if (!item) return;
    
    if (config.handleSelector) {
      const handle = e.target.closest(config.handleSelector);
      if (!handle) return;
    }
    
    const touch = e.touches[0];
    handleDragStart(item, touch.clientX, touch.clientY);
  };
  
  const onTouchMove = (e) => {
    if (!draggedItem) return;
    e.preventDefault();
    const touch = e.touches[0];
    handleDragMove(touch.clientX, touch.clientY);
  };
  
  const onTouchEnd = () => {
    handleDragEnd();
  };
  
  // Keyboard events
  const onKeyDown = (e) => {
    const item = e.target.closest("[data-sortable-item]");
    if (!item) return;
    
    if (item.hasAttribute("data-sortable-disabled")) return;
    
    const items = getItems();
    const index = items.indexOf(item);
    
    // Space or Enter to grab
    if ((e.key === " " || e.key === "Enter") && !item.hasAttribute("data-keyboard-sorting")) {
      e.preventDefault();
      item.setAttribute("data-keyboard-sorting", "true");
      draggedItem = item;
      draggedIndex = index;
      currentIndex = index;
      
      sortState = {
        container: container,
        item: item,
        fromIndex: index,
        toIndex: index,
        listId: config.listId
      };
      
      callbacks.onSortStart({
        item: item,
        index: index,
        listId: config.listId
      })();
      return;
    }
    
    // If in keyboard sorting mode
    if (item.hasAttribute("data-keyboard-sorting")) {
      let newIndex = currentIndex;
      
      switch (e.key) {
        case "ArrowUp":
        case "ArrowLeft":
          e.preventDefault();
          newIndex = Math.max(0, currentIndex - 1);
          break;
        case "ArrowDown":
        case "ArrowRight":
          e.preventDefault();
          newIndex = Math.min(items.length - 1, currentIndex + 1);
          break;
        case "Home":
          e.preventDefault();
          newIndex = 0;
          break;
        case "End":
          e.preventDefault();
          newIndex = items.length - 1;
          break;
        case "Escape":
          e.preventDefault();
          item.removeAttribute("data-keyboard-sorting");
          clearSortStateImpl();
          return;
        case " ":
        case "Enter":
          e.preventDefault();
          item.removeAttribute("data-keyboard-sorting");
          
          if (currentIndex !== draggedIndex) {
            callbacks.onReorder({
              item: item,
              oldIndex: draggedIndex,
              newIndex: currentIndex,
              listId: config.listId
            })();
          }
          
          callbacks.onSortEnd({
            item: item,
            fromIndex: draggedIndex,
            toIndex: currentIndex,
            listId: config.listId
          })();
          
          clearSortStateImpl();
          return;
        default:
          return;
      }
      
      if (newIndex !== currentIndex) {
        currentIndex = newIndex;
        sortState.toIndex = newIndex;
        
        callbacks.onSortMove({
          item: item,
          fromIndex: draggedIndex,
          toIndex: newIndex,
          listId: config.listId
        })();
        
        // Move focus to new position
        if (items[newIndex]) {
          items[newIndex].focus();
        }
      }
    }
  };
  
  container.addEventListener("mousedown", onMouseDown);
  container.addEventListener("touchstart", onTouchStart, { passive: false });
  container.addEventListener("touchmove", onTouchMove, { passive: false });
  container.addEventListener("touchend", onTouchEnd);
  container.addEventListener("keydown", onKeyDown);
  
  return () => {
    container.removeEventListener("mousedown", onMouseDown);
    container.removeEventListener("touchstart", onTouchStart);
    container.removeEventListener("touchmove", onTouchMove);
    container.removeEventListener("touchend", onTouchEnd);
    container.removeEventListener("keydown", onKeyDown);
    document.removeEventListener("mousemove", onMouseMove);
    document.removeEventListener("mouseup", onMouseUp);
  };
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                    // cross-list drag support
// ═══════════════════════════════════════════════════════════════════════════════

export const addCrossListSupportImpl = (containers) => (config) => (callbacks) => () => {
  let activeContainer = null;
  
  const onMouseMove = (e) => {
    if (!sortState) return;
    
    // Find which container we're over
    for (const container of containers) {
      const rect = container.getBoundingClientRect();
      
      if (
        e.clientX >= rect.left &&
        e.clientX <= rect.right &&
        e.clientY >= rect.top &&
        e.clientY <= rect.bottom
      ) {
        if (container !== activeContainer) {
          const oldListId = sortState.listId;
          const newListId = container.getAttribute("data-sortable-list");
          
          if (oldListId !== newListId) {
            activeContainer = container;
            
            callbacks.onCrossListMove({
              item: sortState.item,
              fromListId: oldListId,
              toListId: newListId,
              fromIndex: sortState.fromIndex,
              toIndex: 0
            })();
          }
        }
        break;
      }
    }
  };
  
  document.addEventListener("mousemove", onMouseMove);
  
  return () => {
    document.removeEventListener("mousemove", onMouseMove);
  };
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                              // utilities
// ═══════════════════════════════════════════════════════════════════════════════

export const reorderArrayImpl = (arr) => (fromIndex) => (toIndex) => {
  const result = [...arr];
  const [removed] = result.splice(fromIndex, 1);
  result.splice(toIndex, 0, removed);
  return result;
};

export const getItemsImpl = (container) => () => {
  return Array.from(container.querySelectorAll("[data-sortable-item]"));
};

export const getItemIndexImpl = (container) => (item) => () => {
  const items = Array.from(container.querySelectorAll("[data-sortable-item]"));
  return items.indexOf(item);
};

export const setItemDisabledImpl = (item) => (disabled) => () => {
  if (disabled) {
    item.setAttribute("data-sortable-disabled", "true");
  } else {
    item.removeAttribute("data-sortable-disabled");
  }
};
