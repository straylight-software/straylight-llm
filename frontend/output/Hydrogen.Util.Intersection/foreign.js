// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//                                                   // hydrogen // intersection
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

const convertEntry = (entry) => ({
  isIntersecting: entry.isIntersecting,
  intersectionRatio: entry.intersectionRatio,
  boundingClientRect: {
    top: entry.boundingClientRect.top,
    right: entry.boundingClientRect.right,
    bottom: entry.boundingClientRect.bottom,
    left: entry.boundingClientRect.left,
    width: entry.boundingClientRect.width,
    height: entry.boundingClientRect.height
  },
  time: entry.time
});

export const observeImpl = (element) => (config) => (callback) => () => {
  if (typeof IntersectionObserver === "undefined") {
    // Fallback: assume visible
    callback({
      isIntersecting: true,
      intersectionRatio: 1.0,
      boundingClientRect: { top: 0, right: 0, bottom: 0, left: 0, width: 0, height: 0 },
      time: Date.now()
    })();
    return () => {};
  }
  
  const observer = new IntersectionObserver((entries) => {
    entries.forEach((entry) => {
      callback(convertEntry(entry))();
    });
  }, {
    threshold: config.threshold,
    rootMargin: config.rootMargin,
    root: config.root || null
  });
  
  observer.observe(element);
  
  // Return unobserve function
  return () => {
    observer.unobserve(element);
    observer.disconnect();
  };
};

export const observeOnceImpl = (element) => (config) => (callback) => () => {
  if (typeof IntersectionObserver === "undefined") {
    callback({
      isIntersecting: true,
      intersectionRatio: 1.0,
      boundingClientRect: { top: 0, right: 0, bottom: 0, left: 0, width: 0, height: 0 },
      time: Date.now()
    })();
    return () => {};
  }
  
  let observer;
  
  observer = new IntersectionObserver((entries) => {
    entries.forEach((entry) => {
      if (entry.isIntersecting) {
        callback(convertEntry(entry))();
        observer.unobserve(element);
        observer.disconnect();
      }
    });
  }, {
    threshold: config.threshold,
    rootMargin: config.rootMargin,
    root: config.root || null
  });
  
  observer.observe(element);
  
  return () => {
    observer.unobserve(element);
    observer.disconnect();
  };
};

// Simple boolean reference for tracking state
export const newBoolRef = (initial) => () => {
  return { value: initial };
};

export const readBoolRef = (ref) => () => {
  return ref.value;
};

export const writeBoolRef = (ref) => (value) => () => {
  ref.value = value;
};
