// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//                                                    // hydrogen // mediaquery
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

export const matchMediaImpl = (query) => () => {
  if (typeof window === "undefined" || !window.matchMedia) {
    return false;
  }
  return window.matchMedia(query).matches;
};

export const onMediaChangeImpl = (query) => (callback) => () => {
  if (typeof window === "undefined" || !window.matchMedia) {
    return () => {};
  }
  
  const mql = window.matchMedia(query);
  
  // Modern API uses addEventListener
  const handler = (event) => {
    callback(event.matches)();
  };
  
  // Try modern API first, fallback to deprecated addListener
  if (mql.addEventListener) {
    mql.addEventListener("change", handler);
    
    // Return unsubscribe function
    return () => {
      mql.removeEventListener("change", handler);
    };
  } else if (mql.addListener) {
    // Deprecated but needed for older browsers
    mql.addListener(handler);
    
    return () => {
      mql.removeListener(handler);
    };
  }
  
  return () => {};
};
