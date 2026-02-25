// Session storage FFI for Hydrogen

export const getStorageItem = (storageType) => (key) => () => {
  if (storageType === "memory") {
    return window.__hydrogenMemoryStorage?.[key] ?? null;
  }
  const storage = storageType === "localStorage" ? localStorage : sessionStorage;
  const value = storage.getItem(key);
  return value;
};

export const setStorageItem = (storageType) => (key) => (value) => () => {
  if (storageType === "memory") {
    window.__hydrogenMemoryStorage = window.__hydrogenMemoryStorage || {};
    window.__hydrogenMemoryStorage[key] = value;
    return;
  }
  const storage = storageType === "localStorage" ? localStorage : sessionStorage;
  storage.setItem(key, value);
};

export const removeStorageItem = (storageType) => (key) => () => {
  if (storageType === "memory") {
    if (window.__hydrogenMemoryStorage) {
      delete window.__hydrogenMemoryStorage[key];
    }
    return;
  }
  const storage = storageType === "localStorage" ? localStorage : sessionStorage;
  storage.removeItem(key);
};
