// Error Boundary FFI for Hydrogen

export const reportErrorImpl = (report) => () => {
  console.error("[Hydrogen Error]", report);
  
  // If you have an error tracking service, send it here
  // e.g., Sentry.captureException(new Error(report.error));
};

export const getTimestamp = () => {
  return new Date().toISOString();
};

export const getUserAgent = () => {
  return typeof navigator !== 'undefined' ? navigator.userAgent : 'unknown';
};

export const getUrl = () => {
  return typeof window !== 'undefined' ? window.location.href : 'unknown';
};

export const getStack = (error) => {
  if (error && error.stack) {
    return error.stack;
  }
  return null;
};
