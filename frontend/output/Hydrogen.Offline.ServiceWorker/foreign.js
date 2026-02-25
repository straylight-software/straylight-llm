// Service Worker FFI for Hydrogen

export const isSupportedImpl = () => {
  return 'serviceWorker' in navigator;
};

export const registerImpl = (scriptUrl) => (onError) => (onSuccess) => () => {
  if (!('serviceWorker' in navigator)) {
    onError(new Error("Service workers not supported"))();
    return;
  }
  
  navigator.serviceWorker.register(scriptUrl)
    .then(registration => onSuccess(registration)())
    .catch(error => onError(error)());
};

export const unregisterImpl = (registration) => (onError) => (onSuccess) => () => {
  registration.unregister()
    .then(success => onSuccess(success)())
    .catch(error => onError(error)());
};

export const getRegistrationImpl = (onError) => (onSuccess) => (onNotFound) => () => {
  if (!('serviceWorker' in navigator)) {
    onNotFound();
    return;
  }
  
  navigator.serviceWorker.getRegistration()
    .then(registration => {
      if (registration) {
        onSuccess(registration)();
      } else {
        onNotFound();
      }
    })
    .catch(error => onError(error)());
};

export const updateImpl = (registration) => (onError) => (onSuccess) => () => {
  registration.update()
    .then(() => onSuccess())
    .catch(error => onError(error)());
};

export const onUpdateFoundImpl = (registration) => (callback) => () => {
  registration.addEventListener('updatefound', () => callback());
};

export const onStateChangeImpl = (registration) => (callback) => () => {
  const worker = registration.installing || registration.waiting || registration.active;
  if (worker) {
    worker.addEventListener('statechange', () => {
      callback(worker.state)();
    });
  }
};

export const postMessageImpl = (registration) => (message) => () => {
  const worker = registration.active;
  if (worker) {
    worker.postMessage(message);
  }
};

export const onMessageImpl = (callback) => () => {
  navigator.serviceWorker.addEventListener('message', event => {
    callback(JSON.stringify(event.data))();
  });
};

export const isControlledImpl = () => {
  return !!navigator.serviceWorker.controller;
};

export const skipWaitingImpl = (registration) => () => {
  const waiting = registration.waiting;
  if (waiting) {
    waiting.postMessage({ type: 'SKIP_WAITING' });
  }
};
