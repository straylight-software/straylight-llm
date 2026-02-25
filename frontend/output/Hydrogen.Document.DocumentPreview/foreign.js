// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//                                                 // hydrogen // documentpreview
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

// Document Preview FFI for file loading, type detection,
// content fetching, and preview rendering.

// ═══════════════════════════════════════════════════════════════════════════════
//                                                              // file loading
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Load file info from URL via HEAD request
 * @param {string} url - File URL
 * @returns {Promise<FileInfo>}
 */
export const loadFileInfoImpl = (url) => async () => {
  try {
    const response = await fetch(url, { method: 'HEAD' });
    
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}: ${response.statusText}`);
    }
    
    const contentLength = response.headers.get('content-length');
    const contentType = response.headers.get('content-type');
    const lastModified = response.headers.get('last-modified');
    
    // Extract filename from URL or Content-Disposition
    const contentDisposition = response.headers.get('content-disposition');
    let name = '';
    
    if (contentDisposition) {
      const match = contentDisposition.match(/filename[^;=\n]*=((['"]).*?\2|[^;\n]*)/);
      if (match) {
        name = match[1].replace(/['"]/g, '');
      }
    }
    
    if (!name) {
      const urlPath = new URL(url).pathname;
      name = urlPath.substring(urlPath.lastIndexOf('/') + 1) || 'unknown';
    }
    
    return {
      name,
      size: contentLength ? parseInt(contentLength, 10) : 0,
      type: contentType || '',
      lastModified: lastModified || null,
    };
  } catch (error) {
    console.error('Failed to load file info:', error);
    throw error;
  }
};

/**
 * Load file content as text
 * @param {string} url - File URL
 * @returns {Promise<string>}
 */
export const loadTextContentImpl = (url) => async () => {
  try {
    const response = await fetch(url);
    
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}: ${response.statusText}`);
    }
    
    return await response.text();
  } catch (error) {
    console.error('Failed to load text content:', error);
    throw error;
  }
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                           // download/open
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Download file with given filename
 * @param {string} url - File URL
 * @param {string} filename - Download filename
 */
export const downloadFileImpl = (url) => (filename) => () => {
  const link = document.createElement('a');
  link.href = url;
  link.download = filename;
  link.style.display = 'none';
  
  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
};

/**
 * Open URL in new tab
 * @param {string} url - URL to open
 */
export const openInNewTabImpl = (url) => () => {
  window.open(url, '_blank', 'noopener,noreferrer');
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                           // type detection
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Detect file type from extension
 * @param {string} filename - File name
 * @returns {string} File type
 */
export const detectFileTypeImpl = (filename) => {
  const ext = filename.split('.').pop()?.toLowerCase() || '';
  
  const imageExts = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'svg', 'bmp', 'ico', 'tiff'];
  const videoExts = ['mp4', 'webm', 'mov', 'avi', 'mkv', 'flv', 'wmv'];
  const audioExts = ['mp3', 'wav', 'ogg', 'flac', 'aac', 'm4a', 'wma'];
  const codeExts = ['js', 'ts', 'jsx', 'tsx', 'json', 'py', 'rb', 'php', 'java', 'c', 'cpp', 'h', 'go', 'rs', 'swift', 'kt', 'html', 'css', 'scss', 'xml', 'yaml', 'yml', 'sh', 'sql', 'purs', 'hs'];
  const textExts = ['txt', 'log', 'cfg', 'ini', 'conf'];
  const officeExts = ['doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'odt', 'ods', 'odp'];
  const archiveExts = ['zip', 'tar', 'gz', 'rar', '7z', 'bz2', 'xz'];
  
  if (imageExts.includes(ext)) return 'image';
  if (videoExts.includes(ext)) return 'video';
  if (audioExts.includes(ext)) return 'audio';
  if (ext === 'pdf') return 'pdf';
  if (codeExts.includes(ext)) return 'code';
  if (ext === 'md' || ext === 'markdown') return 'markdown';
  if (textExts.includes(ext)) return 'text';
  if (officeExts.includes(ext)) return 'office';
  if (archiveExts.includes(ext)) return 'archive';
  
  return 'unknown';
};

/**
 * Get language from file extension for syntax highlighting
 * @param {string} filename - File name
 * @returns {string} Language identifier
 */
export const getLanguageFromExtImpl = (filename) => {
  const ext = filename.split('.').pop()?.toLowerCase() || '';
  
  const langMap = {
    'js': 'javascript',
    'jsx': 'javascript',
    'ts': 'typescript',
    'tsx': 'typescript',
    'py': 'python',
    'rb': 'ruby',
    'rs': 'rust',
    'go': 'go',
    'java': 'java',
    'kt': 'kotlin',
    'swift': 'swift',
    'c': 'c',
    'cpp': 'cpp',
    'h': 'c',
    'hpp': 'cpp',
    'cs': 'csharp',
    'php': 'php',
    'html': 'html',
    'css': 'css',
    'scss': 'scss',
    'sass': 'sass',
    'less': 'less',
    'json': 'json',
    'xml': 'xml',
    'yaml': 'yaml',
    'yml': 'yaml',
    'toml': 'toml',
    'md': 'markdown',
    'markdown': 'markdown',
    'sql': 'sql',
    'graphql': 'graphql',
    'sh': 'bash',
    'bash': 'bash',
    'zsh': 'bash',
    'purs': 'haskell',
    'hs': 'haskell',
    'elm': 'elm',
    'ex': 'elixir',
    'exs': 'elixir',
  };
  
  return langMap[ext] || 'text';
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                         // content rendering
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Initialize image preview with zoom
 * @param {HTMLElement} container - Preview container
 * @returns {function} Cleanup function
 */
export const initImagePreviewImpl = (container) => () => {
  const img = container.querySelector('img');
  if (!img) return () => {};
  
  let isZoomed = false;
  let scale = 1;
  let translateX = 0;
  let translateY = 0;
  let isDragging = false;
  let startX = 0;
  let startY = 0;
  
  const updateTransform = () => {
    img.style.transform = `scale(${scale}) translate(${translateX}px, ${translateY}px)`;
  };
  
  const handleClick = (e) => {
    if (isDragging) return;
    
    if (isZoomed) {
      scale = 1;
      translateX = 0;
      translateY = 0;
      isZoomed = false;
      img.style.cursor = 'zoom-in';
    } else {
      scale = 2;
      isZoomed = true;
      img.style.cursor = 'zoom-out';
    }
    updateTransform();
  };
  
  const handleMouseDown = (e) => {
    if (!isZoomed) return;
    isDragging = true;
    startX = e.clientX - translateX;
    startY = e.clientY - translateY;
    img.style.cursor = 'grabbing';
  };
  
  const handleMouseMove = (e) => {
    if (!isDragging) return;
    translateX = e.clientX - startX;
    translateY = e.clientY - startY;
    updateTransform();
  };
  
  const handleMouseUp = () => {
    isDragging = false;
    if (isZoomed) {
      img.style.cursor = 'zoom-out';
    }
  };
  
  const handleWheel = (e) => {
    if (!isZoomed) return;
    e.preventDefault();
    
    const delta = e.deltaY > 0 ? -0.1 : 0.1;
    scale = Math.max(0.5, Math.min(4, scale + delta));
    updateTransform();
  };
  
  img.addEventListener('click', handleClick);
  img.addEventListener('mousedown', handleMouseDown);
  img.addEventListener('mousemove', handleMouseMove);
  img.addEventListener('mouseup', handleMouseUp);
  img.addEventListener('mouseleave', handleMouseUp);
  img.addEventListener('wheel', handleWheel, { passive: false });
  
  return () => {
    img.removeEventListener('click', handleClick);
    img.removeEventListener('mousedown', handleMouseDown);
    img.removeEventListener('mousemove', handleMouseMove);
    img.removeEventListener('mouseup', handleMouseUp);
    img.removeEventListener('mouseleave', handleMouseUp);
    img.removeEventListener('wheel', handleWheel);
  };
};

/**
 * Initialize video preview
 * @param {HTMLElement} container - Preview container
 * @returns {function} Cleanup function
 */
export const initVideoPreviewImpl = (container) => () => {
  const video = container.querySelector('video');
  if (!video) return () => {};
  
  // Keyboard controls
  const handleKeyDown = (e) => {
    if (document.activeElement !== video) return;
    
    switch (e.key) {
      case ' ':
        e.preventDefault();
        if (video.paused) {
          video.play();
        } else {
          video.pause();
        }
        break;
      case 'ArrowLeft':
        e.preventDefault();
        video.currentTime -= 5;
        break;
      case 'ArrowRight':
        e.preventDefault();
        video.currentTime += 5;
        break;
      case 'ArrowUp':
        e.preventDefault();
        video.volume = Math.min(1, video.volume + 0.1);
        break;
      case 'ArrowDown':
        e.preventDefault();
        video.volume = Math.max(0, video.volume - 0.1);
        break;
      case 'm':
        video.muted = !video.muted;
        break;
      case 'f':
        if (document.fullscreenElement) {
          document.exitFullscreen();
        } else {
          video.requestFullscreen();
        }
        break;
    }
  };
  
  video.addEventListener('keydown', handleKeyDown);
  video.setAttribute('tabindex', '0');
  
  return () => {
    video.removeEventListener('keydown', handleKeyDown);
  };
};

/**
 * Initialize audio preview with waveform visualization
 * @param {HTMLElement} container - Preview container
 * @returns {function} Cleanup function
 */
export const initAudioPreviewImpl = (container) => () => {
  const audio = container.querySelector('audio');
  if (!audio) return () => {};
  
  // In production, would use Web Audio API for waveform
  // This is a simplified placeholder
  
  return () => {};
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                        // syntax highlighting
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Apply syntax highlighting to code block
 * @param {HTMLElement} codeElement - Code element
 * @param {string} language - Language identifier
 */
export const highlightCodeImpl = (codeElement) => (language) => () => {
  // In production, use Prism.js or highlight.js
  // This is a placeholder that adds basic styling
  
  codeElement.classList.add(`language-${language}`);
  
  // Basic keyword highlighting (very simplified)
  const keywords = {
    javascript: ['const', 'let', 'var', 'function', 'return', 'if', 'else', 'for', 'while', 'class', 'import', 'export', 'from', 'async', 'await'],
    typescript: ['const', 'let', 'var', 'function', 'return', 'if', 'else', 'for', 'while', 'class', 'import', 'export', 'from', 'async', 'await', 'interface', 'type'],
    python: ['def', 'class', 'if', 'else', 'elif', 'for', 'while', 'return', 'import', 'from', 'as', 'try', 'except', 'with', 'lambda'],
    rust: ['fn', 'let', 'mut', 'if', 'else', 'for', 'while', 'loop', 'match', 'impl', 'struct', 'enum', 'pub', 'use', 'mod'],
  };
  
  // Would apply actual highlighting here
};

/**
 * Render markdown content
 * @param {HTMLElement} container - Container element
 * @param {string} markdown - Markdown content
 */
export const renderMarkdownContentImpl = (container) => (markdown) => () => {
  // In production, use marked or markdown-it
  // This is a basic placeholder
  
  let html = markdown
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/^### (.+)$/gm, '<h3>$1</h3>')
    .replace(/^## (.+)$/gm, '<h2>$1</h2>')
    .replace(/^# (.+)$/gm, '<h1>$1</h1>')
    .replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>')
    .replace(/\*(.+?)\*/g, '<em>$1</em>')
    .replace(/`([^`]+)`/g, '<code>$1</code>')
    .replace(/\n\n/g, '</p><p>');
  
  container.innerHTML = `<p>${html}</p>`;
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                              // array helpers
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Safe array indexing
 * @param {Array} arr - Array to index
 * @param {number} idx - Index
 * @returns {*|null} Element or null
 */
export const indexArrayImpl = (arr) => (idx) => {
  if (idx >= 0 && idx < arr.length) {
    return { value0: arr[idx] }; // Just wrapper
  }
  return null;
};
