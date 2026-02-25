// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//                                                     // hydrogen // fileupload
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

// File upload system with drag-drop, chunked uploads, and progress tracking

// ═══════════════════════════════════════════════════════════════════════════════
//                                                                   // state
// ═══════════════════════════════════════════════════════════════════════════════

let uploadControllers = new Map();
let fileIdCounter = 0;

// ═══════════════════════════════════════════════════════════════════════════════
//                                                            // file upload init
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Initialize file upload with drag-drop and paste support
 * @param {Element} container - Container element
 * @param {Object} callbacks - Event callbacks
 * @param {Object} options - Configuration options
 * @returns {Object} Upload controller
 */
export const initFileUploadImpl = (container) => (callbacks) => (options) => () => {
  const { accept, maxSize, maxFiles, multiple, directory } = options;
  
  const dropZone = container.querySelector('[data-drop-zone]');
  const input = container.querySelector('input[type="file"]');
  
  if (!dropZone || !input) {
    console.warn('FileUpload: Missing drop zone or input element');
    return { destroy: () => {} };
  }
  
  // Configure input
  if (accept && accept.length > 0) {
    input.accept = accept.join(',');
  }
  if (multiple) {
    input.multiple = true;
  }
  if (directory) {
    input.webkitdirectory = true;
  }
  
  // Drag counter to handle nested elements
  let dragCounter = 0;
  
  /**
   * Handle drag enter
   */
  const handleDragEnter = (e) => {
    e.preventDefault();
    e.stopPropagation();
    dragCounter++;
    
    if (dragCounter === 1) {
      dropZone.setAttribute('data-drag-over', 'true');
      callbacks.onDragEnter();
    }
  };
  
  /**
   * Handle drag leave
   */
  const handleDragLeave = (e) => {
    e.preventDefault();
    e.stopPropagation();
    dragCounter--;
    
    if (dragCounter === 0) {
      dropZone.removeAttribute('data-drag-over');
      callbacks.onDragLeave();
    }
  };
  
  /**
   * Handle drag over
   */
  const handleDragOver = (e) => {
    e.preventDefault();
    e.stopPropagation();
    e.dataTransfer.dropEffect = 'copy';
  };
  
  /**
   * Handle drop
   */
  const handleDrop = (e) => {
    e.preventDefault();
    e.stopPropagation();
    dragCounter = 0;
    dropZone.removeAttribute('data-drag-over');
    
    const files = Array.from(e.dataTransfer.files);
    if (files.length > 0) {
      const validFiles = filterFiles(files, accept, maxSize, maxFiles);
      callbacks.onDrop(validFiles)();
    }
    
    callbacks.onDragLeave();
  };
  
  /**
   * Handle file input change
   */
  const handleInputChange = (e) => {
    const files = Array.from(e.target.files);
    if (files.length > 0) {
      const validFiles = filterFiles(files, accept, maxSize, maxFiles);
      callbacks.onFileSelect(validFiles)();
    }
    // Reset input so same file can be selected again
    input.value = '';
  };
  
  /**
   * Handle paste event
   */
  const handlePaste = (e) => {
    const items = e.clipboardData?.items;
    if (!items) return;
    
    const files = [];
    for (let i = 0; i < items.length; i++) {
      const item = items[i];
      if (item.kind === 'file') {
        const file = item.getAsFile();
        if (file) {
          files.push(file);
        }
      }
    }
    
    if (files.length > 0) {
      e.preventDefault();
      const validFiles = filterFiles(files, accept, maxSize, maxFiles);
      callbacks.onPaste(validFiles)();
    }
  };
  
  /**
   * Handle keyboard activation
   */
  const handleKeyDown = (e) => {
    if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault();
      input.click();
    }
  };
  
  // Attach event listeners
  dropZone.addEventListener('dragenter', handleDragEnter);
  dropZone.addEventListener('dragleave', handleDragLeave);
  dropZone.addEventListener('dragover', handleDragOver);
  dropZone.addEventListener('drop', handleDrop);
  dropZone.addEventListener('keydown', handleKeyDown);
  input.addEventListener('change', handleInputChange);
  container.addEventListener('paste', handlePaste);
  
  return {
    container,
    destroy: () => {
      dropZone.removeEventListener('dragenter', handleDragEnter);
      dropZone.removeEventListener('dragleave', handleDragLeave);
      dropZone.removeEventListener('dragover', handleDragOver);
      dropZone.removeEventListener('drop', handleDrop);
      dropZone.removeEventListener('keydown', handleKeyDown);
      input.removeEventListener('change', handleInputChange);
      container.removeEventListener('paste', handlePaste);
    }
  };
};

/**
 * Filter files based on accept, size, and count restrictions
 */
function filterFiles(files, accept, maxSize, maxFiles) {
  let filtered = files;
  
  // Filter by type
  if (accept && accept.length > 0) {
    filtered = filtered.filter(file => {
      return accept.some(pattern => {
        if (pattern.startsWith('.')) {
          // Extension pattern
          return file.name.toLowerCase().endsWith(pattern.toLowerCase());
        } else if (pattern.endsWith('/*')) {
          // MIME type wildcard
          const type = pattern.slice(0, -2);
          return file.type.startsWith(type + '/');
        } else {
          // Exact MIME type
          return file.type === pattern;
        }
      });
    });
  }
  
  // Filter by size
  if (maxSize > 0) {
    filtered = filtered.filter(file => file.size <= maxSize);
  }
  
  // Limit count
  if (maxFiles > 0 && filtered.length > maxFiles) {
    filtered = filtered.slice(0, maxFiles);
  }
  
  return filtered;
}

/**
 * Destroy file upload instance
 */
export const destroyFileUploadImpl = (uploadEl) => () => {
  if (uploadEl && uploadEl.destroy) {
    uploadEl.destroy();
  }
  
  // Cancel any pending uploads
  uploadControllers.forEach((controller) => {
    controller.abort();
  });
  uploadControllers.clear();
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                               // upload control
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Start uploading a file
 */
export const startUploadImpl = (uploadEl) => (fileInfo) => (callbacks) => () => {
  const controller = new AbortController();
  uploadControllers.set(fileInfo.id, controller);
  
  const formData = new FormData();
  formData.append('file', fileInfo.file);
  
  const xhr = new XMLHttpRequest();
  
  xhr.upload.addEventListener('progress', (e) => {
    if (e.lengthComputable) {
      const percent = (e.loaded / e.total) * 100;
      callbacks.onProgress({
        fileId: fileInfo.id,
        loaded: e.loaded,
        total: e.total,
        percent: percent
      })();
    }
  });
  
  xhr.addEventListener('load', () => {
    uploadControllers.delete(fileInfo.id);
    
    if (xhr.status >= 200 && xhr.status < 300) {
      let response;
      try {
        response = JSON.parse(xhr.responseText);
      } catch {
        response = xhr.responseText;
      }
      
      callbacks.onComplete({
        fileId: fileInfo.id,
        response: response
      })();
    } else {
      callbacks.onError({
        fileId: fileInfo.id,
        error: {
          tag: 'ServerError',
          status: xhr.status,
          message: xhr.statusText
        }
      })();
    }
  });
  
  xhr.addEventListener('error', () => {
    uploadControllers.delete(fileInfo.id);
    callbacks.onError({
      fileId: fileInfo.id,
      error: { tag: 'NetworkError', message: 'Network error occurred' }
    })();
  });
  
  xhr.addEventListener('abort', () => {
    uploadControllers.delete(fileInfo.id);
    callbacks.onError({
      fileId: fileInfo.id,
      error: { tag: 'AbortedError' }
    })();
  });
  
  // Abort when signal fires
  controller.signal.addEventListener('abort', () => {
    xhr.abort();
  });
  
  xhr.open('POST', uploadEl.uploadUrl || '/upload');
  
  // Add custom headers
  if (uploadEl.headers) {
    uploadEl.headers.forEach(h => {
      xhr.setRequestHeader(h.key, h.value);
    });
  }
  
  if (uploadEl.withCredentials) {
    xhr.withCredentials = true;
  }
  
  xhr.send(formData);
};

/**
 * Cancel an upload
 */
export const cancelUploadImpl = (uploadEl) => (fileId) => () => {
  const controller = uploadControllers.get(fileId);
  if (controller) {
    controller.abort();
    uploadControllers.delete(fileId);
  }
};

/**
 * Retry a failed upload
 */
export const retryUploadImpl = (uploadEl) => (fileId) => () => {
  // This would typically be called with the file info from state
  console.log('Retry upload:', fileId);
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                              // chunked upload
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Upload file in chunks
 */
export const uploadChunkedImpl = (uploadEl) => (fileInfo) => (options) => () => {
  const { chunkSize, onChunkComplete, onProgress, onComplete, onError } = options;
  const file = fileInfo.file;
  const totalChunks = Math.ceil(file.size / chunkSize);
  
  let currentChunk = 0;
  let uploadedBytes = 0;
  
  const controller = new AbortController();
  uploadControllers.set(fileInfo.id, controller);
  
  const uploadNextChunk = async () => {
    if (controller.signal.aborted) {
      return;
    }
    
    if (currentChunk >= totalChunks) {
      // All chunks uploaded
      uploadControllers.delete(fileInfo.id);
      onComplete({
        fileId: fileInfo.id,
        response: { chunks: totalChunks }
      })();
      return;
    }
    
    const start = currentChunk * chunkSize;
    const end = Math.min(start + chunkSize, file.size);
    const chunk = file.slice(start, end);
    
    const formData = new FormData();
    formData.append('chunk', chunk);
    formData.append('chunkIndex', currentChunk.toString());
    formData.append('totalChunks', totalChunks.toString());
    formData.append('fileId', fileInfo.id);
    formData.append('fileName', fileInfo.name);
    
    try {
      const response = await fetch(uploadEl.uploadUrl || '/upload/chunk', {
        method: 'POST',
        body: formData,
        signal: controller.signal,
        credentials: uploadEl.withCredentials ? 'include' : 'same-origin'
      });
      
      if (!response.ok) {
        throw new Error(`Server error: ${response.status}`);
      }
      
      uploadedBytes += (end - start);
      currentChunk++;
      
      onChunkComplete(currentChunk)();
      onProgress({
        fileId: fileInfo.id,
        loaded: uploadedBytes,
        total: file.size,
        percent: (uploadedBytes / file.size) * 100
      })();
      
      // Upload next chunk
      uploadNextChunk();
      
    } catch (err) {
      uploadControllers.delete(fileInfo.id);
      
      if (err.name === 'AbortError') {
        onError({
          fileId: fileInfo.id,
          error: { tag: 'AbortedError' }
        })();
      } else {
        onError({
          fileId: fileInfo.id,
          error: { tag: 'NetworkError', message: err.message }
        })();
      }
    }
  };
  
  uploadNextChunk();
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                               // file reading
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Create image preview
 */
export const createImagePreviewImpl = (file) => (onComplete) => () => {
  if (!file.type.startsWith('image/')) {
    onComplete(null)();
    return;
  }
  
  const reader = new FileReader();
  reader.onload = (e) => {
    onComplete(e.target.result)();
  };
  reader.onerror = () => {
    onComplete(null)();
  };
  reader.readAsDataURL(file);
};

/**
 * Read file as data URL
 */
export const readFileAsDataUrlImpl = (file) => (onComplete) => () => {
  const reader = new FileReader();
  reader.onload = (e) => {
    onComplete(e.target.result)();
  };
  reader.onerror = () => {
    onComplete(null)();
  };
  reader.readAsDataURL(file);
};

/**
 * Read file as ArrayBuffer
 */
export const readFileAsArrayBufferImpl = (file) => (onComplete) => () => {
  const reader = new FileReader();
  reader.onload = (e) => {
    onComplete(e.target.result)();
  };
  reader.onerror = () => {
    onComplete(null)();
  };
  reader.readAsArrayBuffer(file);
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                                   // utilities
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Unsafe upload element placeholder
 */
export const unsafeUploadElement = {
  container: null,
  uploadUrl: '/upload',
  headers: [],
  withCredentials: false,
  destroy: () => {}
};

/**
 * Join array with separator
 */
export const joinWithImpl = (sep) => (arr) => arr.join(sep);

/**
 * Format file size to human readable string
 */
export const formatFileSizeImpl = (bytes) => {
  if (bytes === 0) return '0 B';
  
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  const i = Math.floor(Math.log(bytes) / Math.log(1024));
  const size = bytes / Math.pow(1024, i);
  
  return size.toFixed(i > 0 ? 1 : 0) + ' ' + units[i];
};

/**
 * Get file extension
 */
export const getFileExtensionImpl = (filename) => {
  const parts = filename.split('.');
  if (parts.length < 2) return '';
  return parts[parts.length - 1].toUpperCase();
};

/**
 * Convert Number to Int
 */
export const toIntImpl = (n) => Math.round(n);

/**
 * Generate unique file ID
 */
export const generateFileIdImpl = () => {
  fileIdCounter++;
  return `file-${Date.now()}-${fileIdCounter}`;
};

/**
 * Validate file against restrictions
 */
export const validateFileImpl = (file) => (restrictions) => () => {
  const { accept, maxSize } = restrictions;
  
  // Check size
  if (maxSize > 0 && file.size > maxSize) {
    return `File too large (${formatFileSizeImpl(file.size)} > ${formatFileSizeImpl(maxSize)})`;
  }
  
  // Check type
  if (accept && accept.length > 0) {
    const valid = accept.some(pattern => {
      if (pattern.startsWith('.')) {
        return file.name.toLowerCase().endsWith(pattern.toLowerCase());
      } else if (pattern.endsWith('/*')) {
        const type = pattern.slice(0, -2);
        return file.type.startsWith(type + '/');
      } else {
        return file.type === pattern;
      }
    });
    
    if (!valid) {
      return `Invalid file type: ${file.type || 'unknown'}`;
    }
  }
  
  return null;
};
