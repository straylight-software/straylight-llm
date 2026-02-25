// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//                                                      // hydrogen // eventbus
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

// | Log an event to console for debugging
// | This is FFI because event type may not have Show instance
// | JavaScript console.log can display any value natively
export const logEvent = (maybeName) => (event) => () => {
  // maybeName is a PureScript Maybe - check for Just constructor
  const busName = maybeName && maybeName.value0 
    ? `[${maybeName.value0}]` 
    : "[EventBus]";
  console.log(`${busName} Event:`, event);
};

// Typed channel support for heterogeneous events
// This uses JavaScript Symbols which have no PureScript equivalent
// Symbols provide runtime type safety for heterogeneous event buses

const eventTypeKey = Symbol("hydrogen.event.type");

// | Wrap an event with its type identifier
// | Used to create heterogeneous events that can be distinguished at runtime
export const wrapEvent = (typeName) => (event) => {
  return { [eventTypeKey]: typeName, payload: event };
};

// | Unwrap an event if it matches the expected type
// | Takes Just and Nothing constructors for proper Maybe encoding
export const unwrapEventImpl = (just) => (nothing) => (typeName) => (anyEvent) => {
  if (anyEvent && anyEvent[eventTypeKey] === typeName) {
    return just(anyEvent.payload);
  }
  return nothing;
};
