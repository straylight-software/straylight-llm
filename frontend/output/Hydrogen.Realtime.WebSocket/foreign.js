// WebSocket FFI for Hydrogen

export const newWebSocket = (url) => (protocols) => () => {
  return new WebSocket(url, protocols);
};

export const wsOnOpen = (ws) => (callback) => () => {
  ws.onopen = () => callback();
};

export const wsOnClose = (ws) => (callback) => () => {
  ws.onclose = () => callback();
};

export const wsOnError = (ws) => (callback) => () => {
  ws.onerror = (event) => callback(event.message || "WebSocket error")();
};

export const wsOnMessage = (ws) => (callback) => () => {
  ws.onmessage = (event) => callback(event.data)();
};

export const wsSend = (ws) => (data) => () => {
  ws.send(data);
};

export const wsClose = (ws) => () => {
  ws.close();
};

export const wsCloseWithCode = (ws) => (code) => (reason) => () => {
  ws.close(code, reason);
};

export const wsReadyState = (ws) => () => {
  return ws.readyState;
};
