// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//                                                       // hydrogen // debounce
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

export const debounceImpl = (wait) => (leading) => (trailing) => (fn) => () => {
  let timerId = null;
  let lastArgs = null;
  let lastThis = null;
  let result = null;
  let lastCallTime = null;
  let lastInvokeTime = 0;
  
  const invokeFunc = (time) => {
    const args = lastArgs;
    const thisArg = lastThis;
    
    lastArgs = null;
    lastThis = null;
    lastInvokeTime = time;
    result = fn(args)();
    return result;
  };
  
  const remainingWait = (time) => {
    const timeSinceLastCall = time - lastCallTime;
    const timeWaiting = wait - timeSinceLastCall;
    return timeWaiting;
  };
  
  const shouldInvoke = (time) => {
    const timeSinceLastCall = time - lastCallTime;
    const timeSinceLastInvoke = time - lastInvokeTime;
    
    return (
      lastCallTime === null ||
      timeSinceLastCall >= wait ||
      timeSinceLastCall < 0
    );
  };
  
  const timerExpired = () => {
    const time = Date.now();
    if (shouldInvoke(time)) {
      return trailingEdge(time);
    }
    timerId = setTimeout(timerExpired, remainingWait(time));
  };
  
  const trailingEdge = (time) => {
    timerId = null;
    
    if (trailing && lastArgs) {
      return invokeFunc(time);
    }
    lastArgs = null;
    lastThis = null;
    return result;
  };
  
  const leadingEdge = (time) => {
    lastInvokeTime = time;
    timerId = setTimeout(timerExpired, wait);
    return leading ? invokeFunc(time) : result;
  };
  
  const cancel = () => {
    if (timerId !== null) {
      clearTimeout(timerId);
    }
    lastInvokeTime = 0;
    lastArgs = null;
    lastCallTime = null;
    lastThis = null;
    timerId = null;
  };
  
  const flush = () => {
    if (timerId === null) {
      return result;
    }
    return trailingEdge(Date.now());
  };
  
  const debounced = (args) => () => {
    const time = Date.now();
    const isInvoking = shouldInvoke(time);
    
    lastArgs = args;
    lastThis = this;
    lastCallTime = time;
    
    if (isInvoking) {
      if (timerId === null) {
        return leadingEdge(lastCallTime);
      }
    }
    
    if (timerId === null) {
      timerId = setTimeout(timerExpired, wait);
    }
    
    return result;
  };
  
  return {
    call: debounced,
    cancel: cancel,
    flush: flush
  };
};

export const throttleImpl = (wait) => (leading) => (trailing) => (fn) => () => {
  let lastArgs = null;
  let lastThis = null;
  let result = null;
  let timerId = null;
  let lastInvokeTime = 0;
  
  const invokeFunc = () => {
    const args = lastArgs;
    lastArgs = null;
    lastThis = null;
    lastInvokeTime = Date.now();
    result = fn(args)();
    return result;
  };
  
  const startTimer = () => {
    timerId = setTimeout(() => {
      timerId = null;
      if (trailing && lastArgs) {
        invokeFunc();
        startTimer();
      }
    }, wait);
  };
  
  const cancel = () => {
    if (timerId !== null) {
      clearTimeout(timerId);
      timerId = null;
    }
    lastInvokeTime = 0;
    lastArgs = null;
    lastThis = null;
  };
  
  const flush = () => {
    if (lastArgs) {
      return invokeFunc();
    }
    return result;
  };
  
  const throttled = (args) => () => {
    const time = Date.now();
    const elapsed = time - lastInvokeTime;
    
    lastArgs = args;
    lastThis = this;
    
    if (elapsed >= wait) {
      if (leading) {
        invokeFunc();
      }
      if (timerId === null) {
        startTimer();
      }
    } else if (timerId === null) {
      startTimer();
    }
    
    return result;
  };
  
  return {
    call: throttled,
    cancel: cancel,
    flush: flush
  };
};
