// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//                                                      // hydrogen // clipboard
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

export const copyToClipboardImpl = (text) => (onError) => (onSuccess) => () => {
  // Try modern Clipboard API first
  if (navigator.clipboard && navigator.clipboard.writeText) {
    navigator.clipboard.writeText(text)
      .then(() => onSuccess())
      .catch((err) => onError(new Error(err.message || "Failed to copy")));
    return;
  }
  
  // Fallback to execCommand
  try {
    const textarea = document.createElement("textarea");
    textarea.value = text;
    textarea.style.position = "fixed";
    textarea.style.left = "-9999px";
    textarea.style.top = "-9999px";
    document.body.appendChild(textarea);
    textarea.select();
    textarea.setSelectionRange(0, textarea.value.length);
    
    const success = document.execCommand("copy");
    document.body.removeChild(textarea);
    
    if (success) {
      onSuccess();
    } else {
      onError(new Error("execCommand copy failed"))();
    }
  } catch (err) {
    onError(err)();
  }
};

export const readFromClipboardImpl = (onError) => (onSuccess) => () => {
  if (navigator.clipboard && navigator.clipboard.readText) {
    navigator.clipboard.readText()
      .then((text) => onSuccess(text)())
      .catch((err) => onError(new Error(err.message || "Failed to read clipboard"))());
    return;
  }
  
  onError(new Error("Clipboard API not supported"))();
};

export const getClipboardData = (event) => () => {
  const data = event.clipboardData;
  if (data) {
    const text = data.getData("text/plain");
    return text || null;
  }
  return null;
};

// Result reference for synchronous-style API
export const newResultRef = () => {
  return { value: null };
};

export const writeResultRef = (ref) => (value) => () => {
  ref.value = value;
};

export const readResultRef = (ref) => () => {
  return ref.value;
};
