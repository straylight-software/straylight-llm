// FFI for Server-Sent Events (SSE) streaming
// Provides browser EventSource bindings for PureScript

"use strict";

// Create an EventSource connection with event handlers
export const createEventSource = (url) => (onMessage) => (onOpen) => (onError) => (onClose) => () => {
  const eventSource = new EventSource(url);
  
  // Track if we've received an open event
  let isOpen = false;
  
  // Handle connection open
  eventSource.onopen = () => {
    isOpen = true;
    onOpen();
  };
  
  // Handle errors
  eventSource.onerror = (event) => {
    // EventSource errors don't provide detailed messages
    // We infer the error type from the connection state
    const errorMsg = eventSource.readyState === EventSource.CLOSED 
      ? "Connection closed" 
      : "Connection error";
    
    if (eventSource.readyState === EventSource.CLOSED) {
      onClose();
    } else {
      onError(errorMsg)();
    }
  };
  
  // Handle generic messages (event type = "message")
  eventSource.onmessage = (event) => {
    onMessage("message")(event.data)();
  };
  
  // Register handlers for specific event types
  const eventTypes = [
    "request.started",
    "request.completed", 
    "proof.generated",
    "provider.status",
    "metrics.update"
  ];
  
  eventTypes.forEach((eventType) => {
    eventSource.addEventListener(eventType, (event) => {
      onMessage(eventType)(event.data)();
    });
  });
  
  return eventSource;
};

// Close an EventSource connection
export const closeEventSource = (eventSource) => () => {
  eventSource.close();
};
