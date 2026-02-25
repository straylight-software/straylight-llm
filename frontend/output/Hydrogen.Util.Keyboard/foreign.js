// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//                                                       // hydrogen // keyboard
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

// Global storage for registered shortcuts and scopes
const shortcutRegistry = [];
let activeScopes = ["global"];

export const registerShortcutImpl = (config) => (callback) => () => {
  const handler = (event) => {
    // Check if we should ignore (input focused)
    if (config.ignoreInputs && isInputFocused()) {
      return;
    }
    
    // Check modifiers
    const ctrlMatch = config.ctrl === (event.ctrlKey || event.metaKey && !isMac());
    const altMatch = config.alt === event.altKey;
    const shiftMatch = config.shift === event.shiftKey;
    const metaMatch = config.meta === event.metaKey;
    
    // Normalize key comparison
    const keyMatch = event.key.toLowerCase() === config.key.toLowerCase() ||
                     event.code.toLowerCase() === `key${config.key.toLowerCase()}`;
    
    if (keyMatch && ctrlMatch && altMatch && shiftMatch && metaMatch) {
      if (config.preventDefault) {
        event.preventDefault();
      }
      if (config.stopPropagation) {
        event.stopPropagation();
      }
      callback();
    }
  };
  
  document.addEventListener("keydown", handler);
  
  // Return unregister function
  return () => {
    document.removeEventListener("keydown", handler);
  };
};

// Key sequence tracking
let sequenceBuffer = [];
let sequenceTimer = null;

export const registerSequenceImpl = (keys) => (timeout) => (callback) => () => {
  const handler = (event) => {
    // Don't track in inputs
    if (isInputFocused()) {
      sequenceBuffer = [];
      return;
    }
    
    // Add key to buffer
    sequenceBuffer.push(event.key.toLowerCase());
    
    // Reset timer
    if (sequenceTimer) {
      clearTimeout(sequenceTimer);
    }
    
    sequenceTimer = setTimeout(() => {
      sequenceBuffer = [];
    }, timeout);
    
    // Check if buffer matches sequence
    const keysLower = keys.map(k => k.toLowerCase());
    const bufferStr = sequenceBuffer.join(",");
    const sequenceStr = keysLower.join(",");
    
    if (bufferStr === sequenceStr) {
      event.preventDefault();
      sequenceBuffer = [];
      clearTimeout(sequenceTimer);
      callback();
    } else if (!sequenceStr.startsWith(bufferStr)) {
      // Reset if doesn't match prefix
      sequenceBuffer = [];
    }
  };
  
  document.addEventListener("keydown", handler);
  
  return () => {
    document.removeEventListener("keydown", handler);
  };
};

export const isInputFocusedImpl = () => {
  const active = document.activeElement;
  if (!active) return false;
  
  const tagName = active.tagName.toLowerCase();
  return tagName === "input" || 
         tagName === "textarea" || 
         tagName === "select" ||
         active.isContentEditable;
};

const isMac = () => {
  if (typeof navigator === "undefined") return false;
  return /Mac|iPod|iPhone|iPad/.test(navigator.platform);
};

export const isMacPlatformImpl = () => isMac();

const isInputFocused = () => {
  const active = document.activeElement;
  if (!active) return false;
  
  const tagName = active.tagName.toLowerCase();
  return tagName === "input" || 
         tagName === "textarea" || 
         tagName === "select" ||
         active.isContentEditable;
};

// Shortcut registry for help display
export const addToShortcutRegistry = (info) => () => {
  shortcutRegistry.push(info);
};

export const getShortcutRegistry = () => {
  return shortcutRegistry.slice();
};

export const clearShortcutRegistry = () => {
  shortcutRegistry.length = 0;
};

// Scope management
let _activeScopesRef = null;

export const activeScopesRef = () => {
  if (!_activeScopesRef) {
    _activeScopesRef = { value: ["global"] };
  }
  return _activeScopesRef;
};
