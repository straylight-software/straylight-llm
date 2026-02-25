// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//                                                        // hydrogen // stagger
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

// Staggered animations for lists and groups

// ═══════════════════════════════════════════════════════════════════════════════
//                                                                   // utilities
// ═══════════════════════════════════════════════════════════════════════════════

const parseAnimation = (animation) => {
  // Parse "initial -> animate" format
  const parts = animation.split("->").map((s) => s.trim());
  if (parts.length === 2) {
    return {
      initial: parts[0].split(" ").filter(Boolean),
      animate: parts[1].split(" ").filter(Boolean),
    };
  }
  // Single value means just animate classes
  return {
    initial: [],
    animate: animation.split(" ").filter(Boolean),
  };
};

const calculateOrder = (direction, count) => {
  const indices = Array.from({ length: count }, (_, i) => i);
  
  switch (direction) {
    case "reverse":
      return indices.reverse();
    
    case "center-out": {
      const result = [];
      const mid = Math.floor(count / 2);
      for (let i = 0; i <= mid; i++) {
        if (mid - i >= 0) result.push(mid - i);
        if (mid + i < count && i !== 0) result.push(mid + i);
      }
      return result;
    }
    
    case "edges-in": {
      const result = [];
      let left = 0;
      let right = count - 1;
      while (left <= right) {
        result.push(left);
        if (left !== right) result.push(right);
        left++;
        right--;
      }
      return result;
    }
    
    case "random": {
      // Fisher-Yates shuffle with deterministic seed
      const arr = [...indices];
      for (let i = arr.length - 1; i > 0; i--) {
        const seed = Math.sin(i * 12.9898) * 43758.5453;
        const j = Math.floor((seed - Math.floor(seed)) * (i + 1));
        [arr[i], arr[j]] = [arr[j], arr[i]];
      }
      return arr;
    }
    
    default: // "forward"
      return indices;
  }
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                              // imperative api
// ═══════════════════════════════════════════════════════════════════════════════

export const staggerElementsImpl = (element) => (config) => () => {
  const children = Array.from(element.querySelectorAll(config.selector));
  const { initial, animate } = parseAnimation(config.animation);
  const order = calculateOrder(config.direction, children.length);
  
  // Set initial state
  for (const child of children) {
    for (const cls of initial) {
      child.classList.add(cls);
    }
  }
  
  // Create delay map based on order
  const delayMap = new Map();
  for (let orderIndex = 0; orderIndex < order.length; orderIndex++) {
    const childIndex = order[orderIndex];
    const delay = config.initialDelay + orderIndex * config.delayPerItem;
    delayMap.set(childIndex, delay);
  }
  
  // Animate
  const timeouts = [];
  for (let i = 0; i < children.length; i++) {
    const child = children[i];
    const delay = delayMap.get(i) || 0;
    
    const timeout = setTimeout(() => {
      for (const cls of initial) {
        child.classList.remove(cls);
      }
      for (const cls of animate) {
        child.classList.add(cls);
      }
    }, delay);
    
    timeouts.push(timeout);
  }
  
  return {
    element,
    children,
    initial,
    animate,
    config,
    timeouts,
    reset: () => {
      for (const t of timeouts) {
        clearTimeout(t);
      }
      timeouts.length = 0;
      for (const child of children) {
        for (const cls of animate) {
          child.classList.remove(cls);
        }
        for (const cls of initial) {
          child.classList.add(cls);
        }
      }
    },
    play: () => {
      const newOrder = calculateOrder(config.direction, children.length);
      for (let orderIndex = 0; orderIndex < newOrder.length; orderIndex++) {
        const childIndex = newOrder[orderIndex];
        const child = children[childIndex];
        const delay = config.initialDelay + orderIndex * config.delayPerItem;
        
        const timeout = setTimeout(() => {
          for (const cls of initial) {
            child.classList.remove(cls);
          }
          for (const cls of animate) {
            child.classList.add(cls);
          }
        }, delay);
        
        timeouts.push(timeout);
      }
    },
    reverse: () => {
      const reverseOrder = calculateOrder(config.direction, children.length).reverse();
      for (let orderIndex = 0; orderIndex < reverseOrder.length; orderIndex++) {
        const childIndex = reverseOrder[orderIndex];
        const child = children[childIndex];
        const delay = config.initialDelay + orderIndex * config.delayPerItem;
        
        const timeout = setTimeout(() => {
          for (const cls of animate) {
            child.classList.remove(cls);
          }
          for (const cls of initial) {
            child.classList.add(cls);
          }
        }, delay);
        
        timeouts.push(timeout);
      }
    },
  };
};

export const staggerWithFunctionImpl = (element) => (config) => () => {
  const children = Array.from(element.querySelectorAll(config.selector));
  const { initial, animate } = parseAnimation(config.animation);
  const total = children.length;
  
  // Set initial state
  for (const child of children) {
    for (const cls of initial) {
      child.classList.add(cls);
    }
  }
  
  // Animate with custom timing
  const timeouts = [];
  for (let i = 0; i < children.length; i++) {
    const child = children[i];
    const delay = config.staggerFn(i)(total);
    
    const timeout = setTimeout(() => {
      for (const cls of initial) {
        child.classList.remove(cls);
      }
      for (const cls of animate) {
        child.classList.add(cls);
      }
    }, delay);
    
    timeouts.push(timeout);
  }
  
  return {
    element,
    children,
    initial,
    animate,
    config,
    timeouts,
  };
};

export const resetStagger = (handle) => () => {
  if (handle && handle.reset) {
    handle.reset();
  }
};

export const playStagger = (handle) => () => {
  if (handle && handle.play) {
    handle.play();
  }
};

export const reverseStagger = (handle) => () => {
  if (handle && handle.reverse) {
    handle.reverse();
  }
};


