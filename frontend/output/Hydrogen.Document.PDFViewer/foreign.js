// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//                                                      // hydrogen // pdfviewer
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

// PDF Viewer FFI for PDF.js integration, canvas rendering,
// text extraction, search, and touch gestures.

// ═══════════════════════════════════════════════════════════════════════════════
//                                                         // pdf.js integration
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Load a PDF document from URL or ArrayBuffer
 * @param {string} source - URL or data URI of the PDF
 * @param {Object} callbacks - Progress and password callbacks
 * @returns {Promise<PDFDocument>}
 */
export const loadDocumentImpl = (source) => (callbacks) => async () => {
  // This would use pdf.js in production:
  // const pdfjsLib = await import('pdfjs-dist');
  // pdfjsLib.GlobalWorkerOptions.workerSrc = '/pdf.worker.js';
  
  const loadingTask = {
    promise: Promise.resolve({
      numPages: 10,
      getPage: async (num) => ({
        getViewport: (opts) => ({ width: 612, height: 792, scale: opts.scale }),
        render: (ctx) => ({ promise: Promise.resolve() }),
        getTextContent: async () => ({ items: [] }),
      }),
      getOutline: async () => [],
      getData: async () => new Uint8Array(),
      destroy: () => {},
    }),
    onProgress: (progress) => {
      if (callbacks.onProgress) {
        callbacks.onProgress({
          loaded: progress.loaded,
          total: progress.total,
          percent: (progress.loaded / progress.total) * 100,
        })();
      }
    },
  };

  try {
    const pdf = await loadingTask.promise;
    return {
      pdf,
      numPages: pdf.numPages,
      currentScale: 1.0,
      rotation: 0,
    };
  } catch (error) {
    if (error.name === 'PasswordException') {
      const password = await callbacks.onPassword()();
      // Retry with password
      throw error;
    }
    throw error;
  }
};

/**
 * Render a PDF page to a canvas element
 * @param {Object} doc - PDF document handle
 * @param {number} pageNum - Page number (1-indexed)
 * @param {Object} options - Render options
 */
export const renderPageImpl = (doc) => (pageNum) => (options) => async () => {
  const { canvas, scale, rotation } = options;
  
  try {
    const page = await doc.pdf.getPage(pageNum);
    const viewport = page.getViewport({ 
      scale: scale / 100, 
      rotation: rotation 
    });
    
    const ctx = canvas.getContext('2d');
    canvas.width = viewport.width;
    canvas.height = viewport.height;
    
    // Clear canvas
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    
    // Render page
    await page.render({
      canvasContext: ctx,
      viewport: viewport,
    }).promise;
  } catch (error) {
    console.error('Failed to render page:', error);
    throw error;
  }
};

/**
 * Get text content from a PDF page
 * @param {Object} doc - PDF document handle
 * @param {number} pageNum - Page number (1-indexed)
 * @returns {Promise<string>}
 */
export const getPageTextImpl = (doc) => (pageNum) => async () => {
  try {
    const page = await doc.pdf.getPage(pageNum);
    const textContent = await page.getTextContent();
    
    return textContent.items
      .map(item => item.str)
      .join(' ');
  } catch (error) {
    console.error('Failed to get page text:', error);
    return '';
  }
};

/**
 * Search for text in the document
 * @param {Object} doc - PDF document handle
 * @param {string} query - Search query
 * @returns {Promise<Array>}
 */
export const searchTextImpl = (doc) => (query) => async () => {
  if (!query || query.trim() === '') {
    return [];
  }
  
  const results = [];
  const queryLower = query.toLowerCase();
  
  for (let pageNum = 1; pageNum <= doc.numPages; pageNum++) {
    try {
      const page = await doc.pdf.getPage(pageNum);
      const textContent = await page.getTextContent();
      const viewport = page.getViewport({ scale: 1.0 });
      
      const pageMatches = [];
      
      textContent.items.forEach((item, index) => {
        const text = item.str.toLowerCase();
        let startIndex = 0;
        let foundIndex = text.indexOf(queryLower, startIndex);
        
        while (foundIndex !== -1) {
          startIndex = foundIndex;
          // Calculate position as percentage
          const transform = item.transform;
          const x = (transform[4] / viewport.width) * 100;
          const y = ((viewport.height - transform[5]) / viewport.height) * 100;
          
          pageMatches.push({
            text: item.str.substring(startIndex, startIndex + query.length),
            rect: {
              x,
              y,
              width: (item.width / viewport.width) * 100,
              height: (item.height / viewport.height) * 100,
            },
          });
          
          startIndex += query.length;
          foundIndex = text.indexOf(queryLower, startIndex);
        }
      });
      
      if (pageMatches.length > 0) {
        results.push({
          page: pageNum,
          matches: pageMatches,
        });
      }
    } catch (error) {
      console.warn(`Failed to search page ${pageNum}:`, error);
    }
  }
  
  return results;
};

/**
 * Print the PDF document
 * @param {Object} doc - PDF document handle
 */
export const printDocumentImpl = (doc) => () => {
  // Create an iframe for printing
  const iframe = document.createElement('iframe');
  iframe.style.display = 'none';
  document.body.appendChild(iframe);
  
  // In production, render all pages to the iframe and print
  // For now, trigger browser print dialog
  window.print();
  
  setTimeout(() => {
    document.body.removeChild(iframe);
  }, 1000);
};

/**
 * Download the PDF document
 * @param {Object} doc - PDF document handle
 * @param {string} filename - Download filename
 */
export const downloadDocumentImpl = (doc) => (filename) => async () => {
  try {
    const data = await doc.pdf.getData();
    const blob = new Blob([data], { type: 'application/pdf' });
    const url = URL.createObjectURL(blob);
    
    const link = document.createElement('a');
    link.href = url;
    link.download = filename || 'document.pdf';
    link.style.display = 'none';
    
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    
    URL.revokeObjectURL(url);
  } catch (error) {
    console.error('Failed to download document:', error);
  }
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                            // pinch-to-zoom
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Initialize pinch-to-zoom gesture handling
 * @param {HTMLElement} container - Container element
 * @param {Object} callbacks - Zoom callback
 * @returns {Object} Controller with destroy method
 */
export const initPinchZoomImpl = (container) => (callbacks) => () => {
  let initialDistance = 0;
  let initialScale = 1;
  let currentScale = 1;
  
  const getDistance = (touches) => {
    const dx = touches[0].clientX - touches[1].clientX;
    const dy = touches[0].clientY - touches[1].clientY;
    return Math.sqrt(dx * dx + dy * dy);
  };
  
  const handleTouchStart = (e) => {
    if (e.touches.length === 2) {
      e.preventDefault();
      initialDistance = getDistance(e.touches);
      initialScale = currentScale;
    }
  };
  
  const handleTouchMove = (e) => {
    if (e.touches.length === 2) {
      e.preventDefault();
      const currentDistance = getDistance(e.touches);
      const scaleFactor = currentDistance / initialDistance;
      currentScale = Math.min(4, Math.max(0.25, initialScale * scaleFactor));
      
      callbacks.onZoom(currentScale * 100)();
    }
  };
  
  const handleTouchEnd = (e) => {
    if (e.touches.length < 2) {
      initialDistance = 0;
    }
  };
  
  // Mouse wheel zoom
  const handleWheel = (e) => {
    if (e.ctrlKey) {
      e.preventDefault();
      const delta = e.deltaY > 0 ? -10 : 10;
      currentScale = Math.min(4, Math.max(0.25, currentScale + delta / 100));
      callbacks.onZoom(currentScale * 100)();
    }
  };
  
  container.addEventListener('touchstart', handleTouchStart, { passive: false });
  container.addEventListener('touchmove', handleTouchMove, { passive: false });
  container.addEventListener('touchend', handleTouchEnd);
  container.addEventListener('wheel', handleWheel, { passive: false });
  
  return {
    destroy: () => {
      container.removeEventListener('touchstart', handleTouchStart);
      container.removeEventListener('touchmove', handleTouchMove);
      container.removeEventListener('touchend', handleTouchEnd);
      container.removeEventListener('wheel', handleWheel);
    },
    setScale: (scale) => {
      currentScale = scale / 100;
    },
  };
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                        // keyboard shortcuts
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Initialize keyboard shortcuts for PDF viewer
 * @param {HTMLElement} container - Viewer container
 * @param {Object} handlers - Keyboard action handlers
 * @returns {function} Cleanup function
 */
export const initKeyboardShortcutsImpl = (container) => (handlers) => () => {
  const handleKeyDown = (e) => {
    // Ignore if focus is in an input
    if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA') {
      return;
    }
    
    switch (e.key) {
      case 'ArrowLeft':
      case 'ArrowUp':
      case 'PageUp':
        e.preventDefault();
        handlers.previousPage();
        break;
        
      case 'ArrowRight':
      case 'ArrowDown':
      case 'PageDown':
      case ' ':
        e.preventDefault();
        handlers.nextPage();
        break;
        
      case 'Home':
        e.preventDefault();
        handlers.firstPage();
        break;
        
      case 'End':
        e.preventDefault();
        handlers.lastPage();
        break;
        
      case '+':
      case '=':
        if (e.ctrlKey || e.metaKey) {
          e.preventDefault();
          handlers.zoomIn();
        }
        break;
        
      case '-':
        if (e.ctrlKey || e.metaKey) {
          e.preventDefault();
          handlers.zoomOut();
        }
        break;
        
      case '0':
        if (e.ctrlKey || e.metaKey) {
          e.preventDefault();
          handlers.zoomReset();
        }
        break;
        
      case 'f':
        if (e.ctrlKey || e.metaKey) {
          e.preventDefault();
          handlers.toggleSearch();
        }
        break;
        
      case 'p':
        if (e.ctrlKey || e.metaKey) {
          e.preventDefault();
          handlers.print();
        }
        break;
        
      case 'r':
        if (!e.ctrlKey && !e.metaKey) {
          e.preventDefault();
          handlers.rotate();
        }
        break;
        
      case 'Escape':
        e.preventDefault();
        handlers.escape();
        break;
        
      case 'F11':
        e.preventDefault();
        handlers.toggleFullscreen();
        break;
    }
  };
  
  container.addEventListener('keydown', handleKeyDown);
  container.setAttribute('tabindex', '0');
  
  return () => {
    container.removeEventListener('keydown', handleKeyDown);
  };
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                          // text selection
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Enable text selection on PDF text layer
 * @param {HTMLElement} textLayer - Text layer element
 * @param {function} onSelect - Selection callback
 * @returns {function} Cleanup function
 */
export const enableTextSelectionImpl = (textLayer) => (onSelect) => () => {
  const handleMouseUp = () => {
    const selection = window.getSelection();
    if (selection && selection.toString().trim()) {
      onSelect(selection.toString())();
    }
  };
  
  textLayer.addEventListener('mouseup', handleMouseUp);
  textLayer.style.userSelect = 'text';
  
  return () => {
    textLayer.removeEventListener('mouseup', handleMouseUp);
  };
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                             // annotations
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Initialize annotation drawing mode
 * @param {HTMLElement} container - Annotation layer container
 * @param {string} mode - Annotation mode (highlight, underline, comment)
 * @param {function} onAnnotation - Annotation created callback
 * @returns {function} Cleanup function
 */
export const initAnnotationModeImpl = (container) => (mode) => (onAnnotation) => () => {
  let isDrawing = false;
  let startX = 0;
  let startY = 0;
  let currentRect = null;
  
  const getRelativePosition = (e) => {
    const rect = container.getBoundingClientRect();
    return {
      x: ((e.clientX - rect.left) / rect.width) * 100,
      y: ((e.clientY - rect.top) / rect.height) * 100,
    };
  };
  
  const handleMouseDown = (e) => {
    if (mode === 'none') return;
    
    isDrawing = true;
    const pos = getRelativePosition(e);
    startX = pos.x;
    startY = pos.y;
    
    currentRect = document.createElement('div');
    currentRect.className = 'absolute border-2 border-dashed border-primary bg-primary/10';
    currentRect.style.left = `${startX}%`;
    currentRect.style.top = `${startY}%`;
    container.appendChild(currentRect);
  };
  
  const handleMouseMove = (e) => {
    if (!isDrawing || !currentRect) return;
    
    const pos = getRelativePosition(e);
    const width = pos.x - startX;
    const height = pos.y - startY;
    
    currentRect.style.width = `${Math.abs(width)}%`;
    currentRect.style.height = `${Math.abs(height)}%`;
    
    if (width < 0) {
      currentRect.style.left = `${pos.x}%`;
    }
    if (height < 0) {
      currentRect.style.top = `${pos.y}%`;
    }
  };
  
  const handleMouseUp = (e) => {
    if (!isDrawing || !currentRect) return;
    
    isDrawing = false;
    const pos = getRelativePosition(e);
    
    const rect = {
      x: Math.min(startX, pos.x),
      y: Math.min(startY, pos.y),
      width: Math.abs(pos.x - startX),
      height: Math.abs(pos.y - startY),
    };
    
    // Remove temporary rect
    container.removeChild(currentRect);
    currentRect = null;
    
    // Only create annotation if rect is large enough
    if (rect.width > 1 && rect.height > 0.5) {
      const annotation = {
        id: `ann-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`,
        type: mode,
        rect,
        color: mode === 'highlight' ? '#ffeb3b' : mode === 'underline' ? '#f44336' : '#2196f3',
        content: null,
        timestamp: new Date().toISOString(),
      };
      
      onAnnotation(annotation)();
    }
  };
  
  container.addEventListener('mousedown', handleMouseDown);
  container.addEventListener('mousemove', handleMouseMove);
  container.addEventListener('mouseup', handleMouseUp);
  container.style.pointerEvents = mode === 'none' ? 'none' : 'auto';
  
  return () => {
    container.removeEventListener('mousedown', handleMouseDown);
    container.removeEventListener('mousemove', handleMouseMove);
    container.removeEventListener('mouseup', handleMouseUp);
  };
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                              // fullscreen
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Toggle fullscreen mode
 * @param {HTMLElement} container - Container to fullscreen
 * @param {function} onChange - Fullscreen change callback
 */
export const toggleFullscreenImpl = (container) => (onChange) => async () => {
  try {
    if (document.fullscreenElement) {
      await document.exitFullscreen();
      onChange(false)();
    } else {
      await container.requestFullscreen();
      onChange(true)();
    }
  } catch (error) {
    console.error('Fullscreen error:', error);
  }
};

/**
 * Listen for fullscreen changes
 * @param {function} onChange - Callback
 * @returns {function} Cleanup function
 */
export const onFullscreenChangeImpl = (onChange) => () => {
  const handler = () => {
    onChange(!!document.fullscreenElement)();
  };
  
  document.addEventListener('fullscreenchange', handler);
  
  return () => {
    document.removeEventListener('fullscreenchange', handler);
  };
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                              // scroll sync
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Synchronize scroll position to current page
 * @param {HTMLElement} scrollContainer - Scroll container
 * @param {function} onPageChange - Page change callback
 * @returns {function} Cleanup function
 */
export const initScrollSyncImpl = (scrollContainer) => (onPageChange) => () => {
  let currentPage = 1;
  
  const handleScroll = () => {
    const pages = scrollContainer.querySelectorAll('[data-page-number]');
    const containerRect = scrollContainer.getBoundingClientRect();
    const containerCenter = containerRect.top + containerRect.height / 2;
    
    let closestPage = 1;
    let closestDistance = Infinity;
    
    pages.forEach((page) => {
      const pageRect = page.getBoundingClientRect();
      const pageCenter = pageRect.top + pageRect.height / 2;
      const distance = Math.abs(pageCenter - containerCenter);
      
      if (distance < closestDistance) {
        closestDistance = distance;
        closestPage = parseInt(page.dataset.pageNumber, 10);
      }
    });
    
    if (closestPage !== currentPage) {
      currentPage = closestPage;
      onPageChange(currentPage)();
    }
  };
  
  scrollContainer.addEventListener('scroll', handleScroll, { passive: true });
  
  return () => {
    scrollContainer.removeEventListener('scroll', handleScroll);
  };
};

/**
 * Scroll to a specific page
 * @param {HTMLElement} scrollContainer - Scroll container
 * @param {number} pageNum - Page number to scroll to
 */
export const scrollToPageImpl = (scrollContainer) => (pageNum) => () => {
  const page = scrollContainer.querySelector(`[data-page-number="${pageNum}"]`);
  if (page) {
    page.scrollIntoView({ behavior: 'smooth', block: 'start' });
  }
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                                  // cleanup
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Destroy PDF viewer and cleanup resources
 * @param {Object} doc - PDF document handle
 */
export const destroyViewerImpl = (doc) => () => {
  if (doc && doc.pdf && typeof doc.pdf.destroy === 'function') {
    doc.pdf.destroy();
  }
};

/**
 * Placeholder for unsafe PDF document
 */
export const unsafePDFDocument = {
  pdf: null,
  numPages: 0,
  currentScale: 1.0,
  rotation: 0,
};
