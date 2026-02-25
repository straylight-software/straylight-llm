// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//                                                    // hydrogen // filebrowser
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

// File browser system with tree view, grid/list views, and file operations

// ═══════════════════════════════════════════════════════════════════════════════
//                                                                // browser init
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Initialize file browser
 * @param {Element} container - Container element
 * @param {Object} callbacks - Event callbacks
 * @returns {Object} Browser controller
 */
export const initBrowserImpl = (container) => (callbacks) => () => {
  let selectedFiles = new Set();
  let draggedFiles = [];
  
  /**
   * Handle context menu
   */
  const handleContextMenu = (e) => {
    e.preventDefault();
    
    const fileEl = e.target.closest('[data-file-id]');
    const fileId = fileEl ? fileEl.dataset.fileId : null;
    
    callbacks.onContextMenu({
      x: e.clientX,
      y: e.clientY,
      fileId: fileId
    })();
  };
  
  /**
   * Handle keyboard shortcuts
   */
  const handleKeyDown = (e) => {
    // Only handle when browser is focused
    if (!container.contains(document.activeElement)) return;
    
    let key = '';
    
    if (e.ctrlKey || e.metaKey) {
      switch (e.key.toLowerCase()) {
        case 'a':
          e.preventDefault();
          key = 'selectAll';
          break;
        case 'c':
          e.preventDefault();
          key = 'copy';
          break;
        case 'x':
          e.preventDefault();
          key = 'cut';
          break;
        case 'v':
          e.preventDefault();
          key = 'paste';
          break;
      }
    } else {
      switch (e.key) {
        case 'Delete':
        case 'Backspace':
          e.preventDefault();
          key = 'delete';
          break;
        case 'F2':
          e.preventDefault();
          key = 'rename';
          break;
        case 'Enter':
          e.preventDefault();
          key = 'open';
          break;
        case 'Escape':
          e.preventDefault();
          key = 'deselect';
          break;
      }
    }
    
    if (key) {
      callbacks.onKeyDown(key)();
    }
  };
  
  /**
   * Handle drag start
   */
  const handleDragStart = (e) => {
    const fileEl = e.target.closest('[data-file-id]');
    if (!fileEl) return;
    
    const fileId = fileEl.dataset.fileId;
    
    // If dragging a selected file, drag all selected
    // Otherwise, just drag this file
    if (selectedFiles.has(fileId)) {
      draggedFiles = Array.from(selectedFiles);
    } else {
      draggedFiles = [fileId];
    }
    
    e.dataTransfer.setData('text/plain', JSON.stringify(draggedFiles));
    e.dataTransfer.effectAllowed = 'copyMove';
    
    callbacks.onDragStart(draggedFiles)();
  };
  
  /**
   * Handle drag over
   */
  const handleDragOver = (e) => {
    e.preventDefault();
    e.dataTransfer.dropEffect = e.ctrlKey ? 'copy' : 'move';
    
    const dropTarget = e.target.closest('[data-file-id]');
    if (dropTarget) {
      dropTarget.classList.add('drag-over');
    }
  };
  
  /**
   * Handle drag leave
   */
  const handleDragLeave = (e) => {
    const dropTarget = e.target.closest('[data-file-id]');
    if (dropTarget) {
      dropTarget.classList.remove('drag-over');
    }
  };
  
  /**
   * Handle drop
   */
  const handleDrop = (e) => {
    e.preventDefault();
    
    const dropTarget = e.target.closest('[data-file-id]');
    if (dropTarget) {
      dropTarget.classList.remove('drag-over');
      
      const targetId = dropTarget.dataset.fileId;
      callbacks.onDrop(targetId)(draggedFiles)();
    }
    
    draggedFiles = [];
  };
  
  /**
   * Handle file click for selection
   */
  const handleClick = (e) => {
    const fileEl = e.target.closest('[data-file-id]');
    if (!fileEl) {
      // Click on empty space - deselect all
      if (!e.ctrlKey && !e.metaKey && !e.shiftKey) {
        selectedFiles.clear();
        updateSelectionUI();
      }
      return;
    }
    
    const fileId = fileEl.dataset.fileId;
    
    if (e.ctrlKey || e.metaKey) {
      // Toggle selection
      if (selectedFiles.has(fileId)) {
        selectedFiles.delete(fileId);
      } else {
        selectedFiles.add(fileId);
      }
    } else if (e.shiftKey) {
      // Range selection - simplified for now
      selectedFiles.add(fileId);
    } else {
      // Single selection
      selectedFiles.clear();
      selectedFiles.add(fileId);
    }
    
    updateSelectionUI();
  };
  
  /**
   * Update selection visual state
   */
  const updateSelectionUI = () => {
    const allFiles = container.querySelectorAll('[data-file-id]');
    allFiles.forEach(el => {
      if (selectedFiles.has(el.dataset.fileId)) {
        el.classList.add('selected');
      } else {
        el.classList.remove('selected');
      }
    });
  };
  
  // Attach event listeners
  container.addEventListener('contextmenu', handleContextMenu);
  container.addEventListener('keydown', handleKeyDown);
  container.addEventListener('dragstart', handleDragStart);
  container.addEventListener('dragover', handleDragOver);
  container.addEventListener('dragleave', handleDragLeave);
  container.addEventListener('drop', handleDrop);
  container.addEventListener('click', handleClick);
  
  return {
    container,
    getSelectedFiles: () => Array.from(selectedFiles),
    setSelectedFiles: (files) => {
      selectedFiles = new Set(files);
      updateSelectionUI();
    },
    selectAll: () => {
      const allFiles = container.querySelectorAll('[data-file-id]');
      allFiles.forEach(el => {
        selectedFiles.add(el.dataset.fileId);
      });
      updateSelectionUI();
      return Array.from(selectedFiles);
    },
    selectNone: () => {
      selectedFiles.clear();
      updateSelectionUI();
    },
    invertSelection: () => {
      const allFiles = container.querySelectorAll('[data-file-id]');
      const newSelection = new Set();
      allFiles.forEach(el => {
        if (!selectedFiles.has(el.dataset.fileId)) {
          newSelection.add(el.dataset.fileId);
        }
      });
      selectedFiles = newSelection;
      updateSelectionUI();
      return Array.from(selectedFiles);
    },
    destroy: () => {
      container.removeEventListener('contextmenu', handleContextMenu);
      container.removeEventListener('keydown', handleKeyDown);
      container.removeEventListener('dragstart', handleDragStart);
      container.removeEventListener('dragover', handleDragOver);
      container.removeEventListener('dragleave', handleDragLeave);
      container.removeEventListener('drop', handleDrop);
      container.removeEventListener('click', handleClick);
    }
  };
};

/**
 * Destroy browser instance
 */
export const destroyBrowserImpl = (browser) => () => {
  if (browser && browser.destroy) {
    browser.destroy();
  }
};

/**
 * Select all files
 */
export const selectAllImpl = (browser) => () => {
  if (browser && browser.selectAll) {
    return browser.selectAll();
  }
  return [];
};

/**
 * Deselect all files
 */
export const selectNoneImpl = (browser) => () => {
  if (browser && browser.selectNone) {
    browser.selectNone();
  }
};

/**
 * Invert selection
 */
export const invertSelectionImpl = (browser) => () => {
  if (browser && browser.invertSelection) {
    return browser.invertSelection();
  }
  return [];
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                                   // utilities
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Unsafe browser element placeholder
 */
export const unsafeBrowserElement = {
  container: null,
  getSelectedFiles: () => [],
  setSelectedFiles: () => {},
  selectAll: () => [],
  selectNone: () => {},
  invertSelection: () => [],
  destroy: () => {}
};

/**
 * Filter array
 */
export const filterImpl = (pred) => (arr) => arr.filter(pred);

/**
 * Check if string contains substring
 */
export const containsImpl = (str) => (substr) => str.includes(substr);

/**
 * Convert string to lowercase
 */
export const toLowerImpl = (str) => str.toLowerCase();

/**
 * Split path into segments
 */
export const splitPathImpl = (path) => {
  const segments = path.split('/').filter(s => s.length > 0);
  return segments.length > 0 ? ['/', ...segments] : ['/'];
};

/**
 * Join path segments
 */
export const joinPathImpl = (segments) => {
  if (segments.length === 0) return '/';
  if (segments.length === 1 && segments[0] === '/') return '/';
  return segments.filter(s => s !== '/').join('/');
};

/**
 * Take first n elements
 */
export const takeImpl = (n) => (arr) => arr.slice(0, n);

/**
 * Map with index
 */
export const mapWithIndexImpl = (fn) => (arr) => arr.map((item, idx) => fn(idx)(item));

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
 * Get file type from extension
 */
export const getFileTypeFromExtension = (filename) => {
  const ext = filename.split('.').pop()?.toLowerCase() || '';
  
  const imageExts = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'svg', 'bmp', 'ico'];
  const videoExts = ['mp4', 'webm', 'avi', 'mov', 'mkv', 'flv', 'wmv'];
  const audioExts = ['mp3', 'wav', 'ogg', 'flac', 'aac', 'm4a'];
  const docExts = ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'rtf'];
  const archiveExts = ['zip', 'rar', '7z', 'tar', 'gz', 'bz2'];
  const codeExts = ['js', 'ts', 'jsx', 'tsx', 'html', 'css', 'json', 'py', 'rb', 'go', 'rs', 'java', 'c', 'cpp', 'h', 'hpp'];
  
  if (imageExts.includes(ext)) return 'Image';
  if (videoExts.includes(ext)) return 'Video';
  if (audioExts.includes(ext)) return 'Audio';
  if (docExts.includes(ext)) return 'Document';
  if (archiveExts.includes(ext)) return 'Archive';
  if (codeExts.includes(ext)) return 'Code';
  return 'Other';
};

/**
 * Get icon for file type
 */
export const getFileIcon = (fileType) => {
  const icons = {
    'Folder': 'folder',
    'Image': 'image',
    'Video': 'video',
    'Audio': 'music',
    'Document': 'file-text',
    'Archive': 'archive',
    'Code': 'code',
    'Other': 'file'
  };
  return icons[fileType] || 'file';
};

/**
 * Sort files
 */
export const sortFiles = (files) => (field) => (order) => {
  const sorted = [...files].sort((a, b) => {
    // Folders first
    if (a.type_ === 'Folder' && b.type_ !== 'Folder') return -1;
    if (a.type_ !== 'Folder' && b.type_ === 'Folder') return 1;
    
    let cmp = 0;
    switch (field) {
      case 'name':
        cmp = a.name.localeCompare(b.name);
        break;
      case 'date':
        cmp = new Date(a.modified) - new Date(b.modified);
        break;
      case 'size':
        cmp = a.size - b.size;
        break;
      case 'type':
        cmp = (a.type_ || '').localeCompare(b.type_ || '');
        break;
      default:
        cmp = a.name.localeCompare(b.name);
    }
    
    return order === 'desc' ? -cmp : cmp;
  });
  
  return sorted;
};

/**
 * Filter files by search query
 */
export const filterFilesByQuery = (files) => (query) => {
  if (!query) return files;
  
  const lowerQuery = query.toLowerCase();
  return files.filter(f => f.name.toLowerCase().includes(lowerQuery));
};

/**
 * Build breadcrumb segments from path
 */
export const buildBreadcrumbs = (path) => {
  const segments = path.split('/').filter(s => s.length > 0);
  
  const breadcrumbs = [{
    label: 'Home',
    path: '/'
  }];
  
  let currentPath = '';
  for (const segment of segments) {
    currentPath += '/' + segment;
    breadcrumbs.push({
      label: segment,
      path: currentPath
    });
  }
  
  return breadcrumbs;
};
