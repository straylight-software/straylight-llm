// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//                                                   // hydrogen // localstorage
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

export const getItemImpl = (key) => () => {
  try {
    const value = localStorage.getItem(key);
    return value;
  } catch (e) {
    return null;
  }
};

export const setItemImpl = (key) => (value) => () => {
  try {
    localStorage.setItem(key, value);
  } catch (e) {
    console.warn("localStorage.setItem failed:", e);
  }
};

export const removeItemImpl = (key) => () => {
  try {
    localStorage.removeItem(key);
  } catch (e) {
    console.warn("localStorage.removeItem failed:", e);
  }
};

export const clearImpl = () => {
  try {
    localStorage.clear();
  } catch (e) {
    console.warn("localStorage.clear failed:", e);
  }
};

export const keysImpl = () => {
  try {
    const keys = [];
    for (let i = 0; i < localStorage.length; i++) {
      keys.push(localStorage.key(i));
    }
    return keys;
  } catch (e) {
    return [];
  }
};

export const lengthImpl = () => {
  try {
    return localStorage.length;
  } catch (e) {
    return 0;
  }
};

export const onChangeImpl = (key) => (callback) => () => {
  const handler = (event) => {
    if (event.key === key || event.key === null) {
      callback(event.newValue)();
    }
  };
  
  window.addEventListener("storage", handler);
  
  return () => {
    window.removeEventListener("storage", handler);
  };
};

export const onAnyChangeImpl = (callback) => () => {
  const handler = (event) => {
    if (event.key !== null) {
      callback(event.key)(event.newValue)();
    }
  };
  
  window.addEventListener("storage", handler);
  
  return () => {
    window.removeEventListener("storage", handler);
  };
};

// Array and string helpers
export const filterImpl = (predicate) => (arr) => {
  return arr.filter(predicate);
};

export const traverseImpl = (f) => (arr) => () => {
  const results = [];
  for (let i = 0; i < arr.length; i++) {
    results.push(f(arr[i])());
  }
  return results;
};

export const take = (n) => (str) => {
  return str.substring(0, n);
};

export const strLength = (str) => {
  return str.length;
};
