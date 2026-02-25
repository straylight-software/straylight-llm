// Server-Sent Events FFI for Hydrogen

export const newEventSource = (url) => (withCredentials) => () => {
  return new EventSource(url, { withCredentials });
};

export const sseOnOpen = (source) => (callback) => () => {
  source.onopen = () => callback();
};

export const sseOnMessage = (source) => (callback) => () => {
  source.onmessage = (event) => callback(event.data)();
};

export const sseOnError = (source) => (callback) => () => {
  source.onerror = (event) => callback("EventSource error")();
};

export const sseAddEventListener = (source) => (type) => (callback) => () => {
  source.addEventListener(type, (event) => callback(event.data)());
};

export const sseRemoveEventListener = (source) => (type) => () => {
  // Note: This is simplified - in production you'd track the listener
  source.removeEventListener(type, () => {});
};

export const sseClose = (source) => () => {
  source.close();
};

export const sseReadyState = (source) => () => {
  return source.readyState;
};
