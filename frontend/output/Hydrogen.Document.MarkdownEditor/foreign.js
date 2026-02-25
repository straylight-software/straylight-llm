// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//                                                  // hydrogen // markdowneditor
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

// Markdown Editor FFI for syntax highlighting, key bindings,
// markdown parsing, and editor functionality.

// ═══════════════════════════════════════════════════════════════════════════════
//                                                         // editor initialization
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Initialize the markdown editor with syntax highlighting
 * @param {HTMLElement} element - Textarea element
 * @param {Object} callbacks - Editor callbacks
 * @returns {Object} Editor handle
 */
export const initEditorImpl = (element) => (callbacks) => () => {
  const handle = {
    element,
    undoStack: [],
    redoStack: [],
    lastValue: element.value,
  };

  // Handle input changes
  const handleInput = (e) => {
    const newValue = e.target.value;
    
    // Save to undo stack
    handle.undoStack.push(handle.lastValue);
    handle.redoStack = [];
    handle.lastValue = newValue;
    
    callbacks.onChange(newValue)();
  };

  // Handle key events
  const handleKeyDown = (e) => {
    const key = e.key;
    const ctrl = e.ctrlKey || e.metaKey;
    const shift = e.shiftKey;
    const alt = e.altKey;

    // Let callback handle the key
    const handled = callbacks.onKeyDown(key)(ctrl)(shift)(alt)();
    
    if (handled) {
      e.preventDefault();
      return;
    }

    // Built-in shortcuts
    if (ctrl) {
      switch (key.toLowerCase()) {
        case 'b':
          e.preventDefault();
          wrapSelectionImpl(handle)('**')('**')();
          break;
        case 'i':
          e.preventDefault();
          wrapSelectionImpl(handle)('*')('*')();
          break;
        case 'k':
          e.preventDefault();
          insertLinkAtCursor(handle);
          break;
        case 'z':
          e.preventDefault();
          if (shift) {
            redo(handle);
          } else {
            undo(handle);
          }
          break;
        case 'y':
          e.preventDefault();
          redo(handle);
          break;
      }
    }

    // Tab handling
    if (key === 'Tab') {
      e.preventDefault();
      const tabStr = '  '; // 2 spaces
      insertTextImpl(handle)(tabStr)();
    }
  };

  // Handle paste for images
  const handlePaste = async (e) => {
    const items = e.clipboardData?.items;
    if (!items) return;

    for (const item of items) {
      if (item.type.startsWith('image/')) {
        e.preventDefault();
        // In production, upload image and insert markdown
        const placeholder = '![Uploading image...]()\n';
        insertTextImpl(handle)(placeholder)();
        break;
      }
    }
  };

  // Handle drop for images
  const handleDrop = async (e) => {
    const files = e.dataTransfer?.files;
    if (!files || files.length === 0) return;

    const file = files[0];
    if (file.type.startsWith('image/')) {
      e.preventDefault();
      const placeholder = `![Uploading ${file.name}...]()\n`;
      insertTextImpl(handle)(placeholder)();
    }
  };

  element.addEventListener('input', handleInput);
  element.addEventListener('keydown', handleKeyDown);
  element.addEventListener('paste', handlePaste);
  element.addEventListener('drop', handleDrop);

  handle.cleanup = () => {
    element.removeEventListener('input', handleInput);
    element.removeEventListener('keydown', handleKeyDown);
    element.removeEventListener('paste', handlePaste);
    element.removeEventListener('drop', handleDrop);
  };

  return handle;
};

/**
 * Destroy editor and cleanup
 * @param {Object} handle - Editor handle
 */
export const destroyEditorImpl = (handle) => () => {
  if (handle && handle.cleanup) {
    handle.cleanup();
  }
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                          // text manipulation
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Insert text at cursor position
 * @param {Object} handle - Editor handle
 * @param {string} text - Text to insert
 */
export const insertTextImpl = (handle) => (text) => () => {
  const el = handle.element;
  const start = el.selectionStart;
  const end = el.selectionEnd;
  const before = el.value.substring(0, start);
  const after = el.value.substring(end);
  
  el.value = before + text + after;
  el.selectionStart = el.selectionEnd = start + text.length;
  
  // Trigger input event
  el.dispatchEvent(new Event('input', { bubbles: true }));
};

/**
 * Wrap selection with prefix and suffix
 * @param {Object} handle - Editor handle
 * @param {string} prefix - Text before selection
 * @param {string} suffix - Text after selection
 */
export const wrapSelectionImpl = (handle) => (prefix) => (suffix) => () => {
  const el = handle.element;
  const start = el.selectionStart;
  const end = el.selectionEnd;
  const selectedText = el.value.substring(start, end);
  const before = el.value.substring(0, start);
  const after = el.value.substring(end);
  
  const newText = prefix + selectedText + suffix;
  el.value = before + newText + after;
  
  // Select the wrapped text (without prefix/suffix)
  el.selectionStart = start + prefix.length;
  el.selectionEnd = start + prefix.length + selectedText.length;
  
  el.dispatchEvent(new Event('input', { bubbles: true }));
};

/**
 * Get current selection
 * @param {Object} handle - Editor handle
 * @returns {Object} Selection info
 */
export const getSelectionImpl = (handle) => () => {
  const el = handle.element;
  return {
    start: el.selectionStart,
    end: el.selectionEnd,
    text: el.value.substring(el.selectionStart, el.selectionEnd),
  };
};

/**
 * Set selection range
 * @param {Object} handle - Editor handle
 * @param {number} start - Start position
 * @param {number} end - End position
 */
export const setSelectionImpl = (handle) => (start) => (end) => () => {
  const el = handle.element;
  el.selectionStart = start;
  el.selectionEnd = end;
  el.focus();
};

/**
 * Scroll to specific line
 * @param {Object} handle - Editor handle
 * @param {number} line - Line number (1-indexed)
 */
export const scrollToLineImpl = (handle) => (line) => () => {
  const el = handle.element;
  const lineHeight = parseInt(getComputedStyle(el).lineHeight) || 20;
  el.scrollTop = (line - 1) * lineHeight;
};

/**
 * Focus the editor
 * @param {Object} handle - Editor handle
 */
export const focusImpl = (handle) => () => {
  handle.element.focus();
};

/**
 * Blur the editor
 * @param {Object} handle - Editor handle
 */
export const blurImpl = (handle) => () => {
  handle.element.blur();
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                              // undo/redo
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Undo last change
 * @param {Object} handle - Editor handle
 */
function undo(handle) {
  if (handle.undoStack.length === 0) return;
  
  const el = handle.element;
  handle.redoStack.push(el.value);
  el.value = handle.undoStack.pop();
  handle.lastValue = el.value;
  
  el.dispatchEvent(new Event('input', { bubbles: true }));
}

/**
 * Redo last undone change
 * @param {Object} handle - Editor handle
 */
function redo(handle) {
  if (handle.redoStack.length === 0) return;
  
  const el = handle.element;
  handle.undoStack.push(el.value);
  el.value = handle.redoStack.pop();
  handle.lastValue = el.value;
  
  el.dispatchEvent(new Event('input', { bubbles: true }));
}

// ═══════════════════════════════════════════════════════════════════════════════
//                                                         // markdown rendering
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Render markdown to HTML
 * @param {string} markdown - Markdown content
 * @param {Object} options - Render options
 * @returns {string} HTML content
 */
export const renderMarkdownImpl = (markdown) => (options) => () => {
  // In production, use a library like marked or markdown-it
  // This is a simplified implementation
  
  let html = markdown;
  
  // Escape HTML
  html = html
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
  
  // Headers
  html = html.replace(/^### (.+)$/gm, '<h3>$1</h3>');
  html = html.replace(/^## (.+)$/gm, '<h2>$1</h2>');
  html = html.replace(/^# (.+)$/gm, '<h1>$1</h1>');
  
  // Bold and italic
  html = html.replace(/\*\*\*(.+?)\*\*\*/g, '<strong><em>$1</em></strong>');
  html = html.replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>');
  html = html.replace(/\*(.+?)\*/g, '<em>$1</em>');
  
  // Strikethrough (GFM)
  if (options.gfm) {
    html = html.replace(/~~(.+?)~~/g, '<del>$1</del>');
  }
  
  // Code blocks
  html = html.replace(/```(\w*)\n([\s\S]*?)```/g, (match, lang, code) => {
    return `<pre><code class="language-${lang}">${code.trim()}</code></pre>`;
  });
  
  // Inline code
  html = html.replace(/`([^`]+)`/g, '<code>$1</code>');
  
  // Links
  html = html.replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2">$1</a>');
  
  // Images
  html = html.replace(/!\[([^\]]*)\]\(([^)]+)\)/g, '<img src="$2" alt="$1">');
  
  // Blockquotes
  html = html.replace(/^&gt; (.+)$/gm, '<blockquote>$1</blockquote>');
  
  // Horizontal rules
  html = html.replace(/^---$/gm, '<hr>');
  html = html.replace(/^\*\*\*$/gm, '<hr>');
  
  // Unordered lists
  html = html.replace(/^[\*\-] (.+)$/gm, '<li>$1</li>');
  html = html.replace(/(<li>.*<\/li>\n?)+/g, '<ul>$&</ul>');
  
  // Ordered lists
  html = html.replace(/^\d+\. (.+)$/gm, '<li>$1</li>');
  
  // Task lists (GFM)
  if (options.gfm) {
    html = html.replace(/^- \[x\] (.+)$/gm, '<li><input type="checkbox" checked disabled> $1</li>');
    html = html.replace(/^- \[ \] (.+)$/gm, '<li><input type="checkbox" disabled> $1</li>');
  }
  
  // Line breaks
  if (options.breaks) {
    html = html.replace(/\n/g, '<br>\n');
  }
  
  // Paragraphs
  html = html.replace(/\n\n+/g, '</p><p>');
  html = '<p>' + html + '</p>';
  html = html.replace(/<p><\/p>/g, '');
  
  return html;
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                         // toolbar actions
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Execute toolbar action
 * @param {Object} handle - Editor handle
 * @param {string} action - Action name
 */
export const executeActionImpl = (handle) => (action) => () => {
  switch (action) {
    case 'bold':
      wrapSelectionImpl(handle)('**')('**')();
      break;
    case 'italic':
      wrapSelectionImpl(handle)('*')('*')();
      break;
    case 'strikethrough':
      wrapSelectionImpl(handle)('~~')('~~')();
      break;
    case 'heading1':
      insertAtLineStart(handle, '# ');
      break;
    case 'heading2':
      insertAtLineStart(handle, '## ');
      break;
    case 'heading3':
      insertAtLineStart(handle, '### ');
      break;
    case 'bulletList':
      insertAtLineStart(handle, '- ');
      break;
    case 'numberedList':
      insertAtLineStart(handle, '1. ');
      break;
    case 'taskList':
      insertAtLineStart(handle, '- [ ] ');
      break;
    case 'blockquote':
      insertAtLineStart(handle, '> ');
      break;
    case 'codeBlock':
      wrapSelectionImpl(handle)('```\n')('\n```')();
      break;
    case 'inlineCode':
      wrapSelectionImpl(handle)('`')('`')();
      break;
    case 'link':
      insertLinkAtCursor(handle);
      break;
    case 'image':
      insertImageAtCursor(handle);
      break;
    case 'table':
      insertTable(handle);
      break;
    case 'horizontalRule':
      insertTextImpl(handle)('\n---\n')();
      break;
  }
};

/**
 * Insert text at the start of the current line
 * @param {Object} handle - Editor handle
 * @param {string} text - Text to insert
 */
function insertAtLineStart(handle, text) {
  const el = handle.element;
  const start = el.selectionStart;
  const value = el.value;
  
  // Find start of current line
  let lineStart = start;
  while (lineStart > 0 && value[lineStart - 1] !== '\n') {
    lineStart--;
  }
  
  const before = value.substring(0, lineStart);
  const after = value.substring(lineStart);
  
  el.value = before + text + after;
  el.selectionStart = el.selectionEnd = start + text.length;
  
  el.dispatchEvent(new Event('input', { bubbles: true }));
}

/**
 * Insert link at cursor
 * @param {Object} handle - Editor handle
 */
function insertLinkAtCursor(handle) {
  const selection = getSelectionImpl(handle)();
  const linkText = selection.text || 'link text';
  const markdown = `[${linkText}](url)`;
  
  insertTextImpl(handle)(markdown)();
  
  // Select the URL placeholder
  const el = handle.element;
  const urlStart = el.selectionEnd - 4; // length of "url)"
  const urlEnd = el.selectionEnd - 1;   // before ")"
  el.selectionStart = urlStart;
  el.selectionEnd = urlEnd;
}

/**
 * Insert image at cursor
 * @param {Object} handle - Editor handle
 */
function insertImageAtCursor(handle) {
  const selection = getSelectionImpl(handle)();
  const altText = selection.text || 'image';
  const markdown = `![${altText}](url)`;
  
  insertTextImpl(handle)(markdown)();
}

/**
 * Insert table template
 * @param {Object} handle - Editor handle
 */
function insertTable(handle) {
  const table = `
| Header 1 | Header 2 | Header 3 |
|----------|----------|----------|
| Cell 1   | Cell 2   | Cell 3   |
| Cell 4   | Cell 5   | Cell 6   |
`;
  insertTextImpl(handle)(table)();
}

// ═══════════════════════════════════════════════════════════════════════════════
//                                                              // vim bindings
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Initialize Vim key bindings
 * @param {Object} handle - Editor handle
 * @param {function} onModeChange - Mode change callback
 * @returns {function} Cleanup function
 */
export const initVimBindingsImpl = (handle) => (onModeChange) => () => {
  let mode = 'normal'; // normal, insert, visual
  let commandBuffer = '';
  
  const handleKeyDown = (e) => {
    // Only handle in normal mode
    if (mode === 'insert') {
      if (e.key === 'Escape') {
        mode = 'normal';
        onModeChange(mode)();
        e.preventDefault();
      }
      return;
    }
    
    e.preventDefault();
    
    switch (e.key) {
      case 'i':
        mode = 'insert';
        onModeChange(mode)();
        break;
      case 'a':
        mode = 'insert';
        handle.element.selectionStart++;
        onModeChange(mode)();
        break;
      case 'h':
        moveCursor(handle, -1);
        break;
      case 'l':
        moveCursor(handle, 1);
        break;
      case 'j':
        moveLines(handle, 1);
        break;
      case 'k':
        moveLines(handle, -1);
        break;
      case '0':
        moveToLineStart(handle);
        break;
      case '$':
        moveToLineEnd(handle);
        break;
      case 'g':
        commandBuffer += 'g';
        break;
      case 'G':
        if (commandBuffer === 'g') {
          moveToStart(handle);
          commandBuffer = '';
        } else {
          moveToEnd(handle);
        }
        break;
      default:
        commandBuffer = '';
    }
  };
  
  handle.element.addEventListener('keydown', handleKeyDown);
  
  return () => {
    handle.element.removeEventListener('keydown', handleKeyDown);
  };
};

/**
 * Move cursor by offset
 * @param {Object} handle - Editor handle
 * @param {number} offset - Character offset
 */
function moveCursor(handle, offset) {
  const el = handle.element;
  const newPos = Math.max(0, Math.min(el.value.length, el.selectionStart + offset));
  el.selectionStart = el.selectionEnd = newPos;
}

/**
 * Move cursor by lines
 * @param {Object} handle - Editor handle
 * @param {number} lines - Line offset
 */
function moveLines(handle, lines) {
  const el = handle.element;
  const value = el.value;
  const pos = el.selectionStart;
  
  // Find current line info
  let lineStart = pos;
  while (lineStart > 0 && value[lineStart - 1] !== '\n') {
    lineStart--;
  }
  const col = pos - lineStart;
  
  // Find target line
  let targetLine = lineStart;
  if (lines > 0) {
    // Move down
    for (let i = 0; i < lines; i++) {
      const nextNewline = value.indexOf('\n', targetLine);
      if (nextNewline === -1) break;
      targetLine = nextNewline + 1;
    }
  } else {
    // Move up
    for (let i = 0; i > lines; i--) {
      if (targetLine === 0) break;
      targetLine--;
      while (targetLine > 0 && value[targetLine - 1] !== '\n') {
        targetLine--;
      }
    }
  }
  
  // Find end of target line
  let targetEnd = value.indexOf('\n', targetLine);
  if (targetEnd === -1) targetEnd = value.length;
  
  // Set position with same column if possible
  const newPos = Math.min(targetLine + col, targetEnd);
  el.selectionStart = el.selectionEnd = newPos;
}

function moveToLineStart(handle) {
  const el = handle.element;
  let pos = el.selectionStart;
  while (pos > 0 && el.value[pos - 1] !== '\n') {
    pos--;
  }
  el.selectionStart = el.selectionEnd = pos;
}

function moveToLineEnd(handle) {
  const el = handle.element;
  let pos = el.selectionStart;
  while (pos < el.value.length && el.value[pos] !== '\n') {
    pos++;
  }
  el.selectionStart = el.selectionEnd = pos;
}

function moveToStart(handle) {
  const el = handle.element;
  el.selectionStart = el.selectionEnd = 0;
}

function moveToEnd(handle) {
  const el = handle.element;
  el.selectionStart = el.selectionEnd = el.value.length;
}

// ═══════════════════════════════════════════════════════════════════════════════
//                                                              // math rendering
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Render KaTeX math expressions
 * @param {HTMLElement} container - Container element
 * @returns {function} Cleanup function
 */
export const initMathRenderingImpl = (container) => () => {
  // In production, use KaTeX
  // Find all math blocks and render them
  const inlineMath = container.querySelectorAll('[data-math-inline]');
  const blockMath = container.querySelectorAll('[data-math-block]');
  
  // Would call katex.render() here
  
  return () => {
    // Cleanup if needed
  };
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                           // mermaid diagrams
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Render Mermaid diagrams
 * @param {HTMLElement} container - Container element
 * @returns {function} Cleanup function
 */
export const initMermaidRenderingImpl = (container) => () => {
  // In production, use mermaid library
  const diagrams = container.querySelectorAll('[data-mermaid]');
  
  // Would call mermaid.render() here
  
  return () => {
    // Cleanup if needed
  };
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                                  // utilities
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Count words in text
 * @param {string} text - Text content
 * @returns {number} Word count
 */
export const countWordsImpl = (text) => {
  if (!text || text.trim() === '') return 0;
  return text.trim().split(/\s+/).length;
};

/**
 * Generate array range
 * @param {number} start - Start value
 * @param {number} end - End value (inclusive)
 * @returns {number[]} Array of numbers
 */
export const rangeArrayImpl = (start) => (end) => {
  if (end < start) return [];
  const result = [];
  for (let i = start; i <= end; i++) {
    result.push(i);
  }
  return result;
};

/**
 * Export markdown as HTML file
 * @param {string} markdown - Markdown content
 * @param {string} filename - Output filename
 */
export const exportToHtmlImpl = (markdown) => (filename) => () => {
  const options = { gfm: true, breaks: true, sanitize: true };
  const html = renderMarkdownImpl(markdown)(options)();
  
  const fullHtml = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Markdown Export</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 800px; margin: 0 auto; padding: 2rem; }
    pre { background: #f4f4f4; padding: 1rem; overflow-x: auto; }
    code { background: #f4f4f4; padding: 0.2em 0.4em; border-radius: 3px; }
    blockquote { border-left: 4px solid #ddd; margin: 0; padding-left: 1rem; color: #666; }
  </style>
</head>
<body>
${html}
</body>
</html>`;
  
  const blob = new Blob([fullHtml], { type: 'text/html;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  
  const link = document.createElement('a');
  link.href = url;
  link.download = filename || 'document.html';
  link.click();
  
  URL.revokeObjectURL(url);
};

/**
 * Placeholder for unsafe editor handle
 */
export const unsafeEditorHandle = {
  element: null,
  undoStack: [],
  redoStack: [],
  lastValue: '',
  cleanup: () => {},
};
