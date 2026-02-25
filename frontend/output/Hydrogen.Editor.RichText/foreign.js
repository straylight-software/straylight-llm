// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//                                                       // hydrogen // richtext
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

// Rich Text Editor JavaScript FFI
//
// Provides:
// - Contenteditable management
// - Selection/range handling
// - Keyboard shortcuts
// - Undo/redo stack
// - Clipboard handling
// - Drag and drop
// - execCommand wrappers
// - Bubble menu positioning
// - Slash command handling
// - Mention handling

// ═══════════════════════════════════════════════════════════════════════════════
//                                                               // editor state
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Editor state container
 * @typedef {Object} EditorState
 * @property {Element} container - The editor container element
 * @property {Element} contentEl - The contenteditable element
 * @property {Array} undoStack - Undo history
 * @property {Array} redoStack - Redo history
 * @property {Object} options - Editor options
 * @property {Function} onChange - Change callback
 * @property {Object} shortcuts - Registered shortcuts cleanup
 * @property {Object} menus - Menu elements
 */

// Store editor instances by element
const editorInstances = new WeakMap();

// ═══════════════════════════════════════════════════════════════════════════════
//                                                           // editor lifecycle
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Initialize editor on a DOM element
 *
 * @param {Element} container - Editor container element
 * @param {Object} options - Editor configuration options
 * @param {Function} onChange - Callback for content changes
 * @returns {EditorState} Editor state object
 */
export const initEditorImpl = (container, options, onChange) => {
  const contentEl = container.querySelector('[contenteditable="true"]');
  if (!contentEl) {
    throw new Error("RichText: No contenteditable element found in container");
  }

  const state = {
    container,
    contentEl,
    undoStack: [],
    redoStack: [],
    options: options || {},
    onChange,
    shortcuts: null,
    menus: {
      bubble: null,
      slash: null,
      mention: null,
    },
    lastContent: "",
    characterLimit: options?.characterLimit || null,
    isComposing: false,
  };

  // Store instance
  editorInstances.set(container, state);

  // Initialize content
  if (options?.initialContent) {
    contentEl.innerHTML = options.initialContent;
    state.lastContent = contentEl.innerHTML;
    saveToUndoStack(state);
  }

  // Setup event listeners
  setupEventListeners(state);

  // Setup placeholder
  setupPlaceholder(state);

  // Setup menus
  setupMenus(state);

  // Autofocus if requested
  if (options?.autofocus) {
    requestAnimationFrame(() => {
      contentEl.focus();
      // Move cursor to end
      const range = document.createRange();
      range.selectNodeContents(contentEl);
      range.collapse(false);
      const selection = window.getSelection();
      selection.removeAllRanges();
      selection.addRange(range);
    });
  }

  return state;
};

/**
 * Destroy editor and cleanup
 *
 * @param {EditorState} state - Editor state object
 */
export const destroyEditorImpl = (state) => {
  if (!state) return;

  // Remove event listeners
  if (state.contentEl) {
    state.contentEl.removeEventListener("input", state._handleInput);
    state.contentEl.removeEventListener("keydown", state._handleKeyDown);
    state.contentEl.removeEventListener("paste", state._handlePaste);
    state.contentEl.removeEventListener("drop", state._handleDrop);
    state.contentEl.removeEventListener("focus", state._handleFocus);
    state.contentEl.removeEventListener("blur", state._handleBlur);
    state.contentEl.removeEventListener(
      "compositionstart",
      state._handleCompositionStart
    );
    state.contentEl.removeEventListener(
      "compositionend",
      state._handleCompositionEnd
    );
  }

  // Remove selection listener
  document.removeEventListener("selectionchange", state._handleSelectionChange);

  // Cleanup shortcuts
  if (state.shortcuts) {
    state.shortcuts();
    state.shortcuts = null;
  }

  // Remove from instances
  if (state.container) {
    editorInstances.delete(state.container);
  }
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                           // event listeners
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Setup all event listeners
 */
function setupEventListeners(state) {
  const { contentEl } = state;

  // Input handling
  state._handleInput = (e) => handleInput(state, e);
  contentEl.addEventListener("input", state._handleInput);

  // Keyboard handling
  state._handleKeyDown = (e) => handleKeyDown(state, e);
  contentEl.addEventListener("keydown", state._handleKeyDown);

  // Clipboard handling
  state._handlePaste = (e) => handlePaste(state, e);
  contentEl.addEventListener("paste", state._handlePaste);

  // Drag and drop
  state._handleDrop = (e) => handleDrop(state, e);
  contentEl.addEventListener("drop", state._handleDrop);

  // Focus/blur
  state._handleFocus = (e) => handleFocus(state, e);
  state._handleBlur = (e) => handleBlur(state, e);
  contentEl.addEventListener("focus", state._handleFocus);
  contentEl.addEventListener("blur", state._handleBlur);

  // IME composition
  state._handleCompositionStart = () => {
    state.isComposing = true;
  };
  state._handleCompositionEnd = () => {
    state.isComposing = false;
  };
  contentEl.addEventListener("compositionstart", state._handleCompositionStart);
  contentEl.addEventListener("compositionend", state._handleCompositionEnd);

  // Selection change for bubble menu
  state._handleSelectionChange = () => handleSelectionChange(state);
  document.addEventListener("selectionchange", state._handleSelectionChange);
}

/**
 * Handle input events
 */
function handleInput(state, e) {
  const { contentEl, onChange, characterLimit, lastContent } = state;

  // Check character limit
  if (characterLimit) {
    const text = contentEl.textContent || "";
    if (text.length > characterLimit) {
      // Truncate to limit
      contentEl.innerHTML = lastContent;
      return;
    }
  }

  // Update last content
  state.lastContent = contentEl.innerHTML;

  // Update counts display
  updateCounts(state);

  // Save to undo stack (debounced)
  debouncedSaveUndo(state);

  // Notify change
  if (onChange) {
    onChange({ type: "html", content: contentEl.innerHTML })();
  }
}

/**
 * Handle keyboard events
 */
function handleKeyDown(state, e) {
  const { contentEl, options } = state;

  // Don't handle during IME composition
  if (state.isComposing) return;

  // Get modifier state
  const isMac = navigator.platform.toUpperCase().indexOf("MAC") >= 0;
  const mod = isMac ? e.metaKey : e.ctrlKey;
  const shift = e.shiftKey;

  // ═══════════════════════════════════════════════════════════════════════════
  // Formatting shortcuts
  // ═══════════════════════════════════════════════════════════════════════════

  // Bold: Ctrl+B / Cmd+B
  if (mod && e.key === "b") {
    e.preventDefault();
    execCommand("bold");
    return;
  }

  // Italic: Ctrl+I / Cmd+I
  if (mod && e.key === "i") {
    e.preventDefault();
    execCommand("italic");
    return;
  }

  // Underline: Ctrl+U / Cmd+U
  if (mod && e.key === "u") {
    e.preventDefault();
    execCommand("underline");
    return;
  }

  // Strikethrough: Ctrl+Shift+S
  if (mod && shift && e.key === "S") {
    e.preventDefault();
    execCommand("strikeThrough");
    return;
  }

  // Code: Ctrl+E / Cmd+E
  if (mod && e.key === "e") {
    e.preventDefault();
    toggleInlineCode(state);
    return;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Block shortcuts
  // ═══════════════════════════════════════════════════════════════════════════

  // Heading 1: Ctrl+Shift+1
  if (mod && shift && e.key === "1") {
    e.preventDefault();
    formatBlock("h1");
    return;
  }

  // Heading 2: Ctrl+Shift+2
  if (mod && shift && e.key === "2") {
    e.preventDefault();
    formatBlock("h2");
    return;
  }

  // Heading 3: Ctrl+Shift+3
  if (mod && shift && e.key === "3") {
    e.preventDefault();
    formatBlock("h3");
    return;
  }

  // Paragraph: Ctrl+Shift+0
  if (mod && shift && e.key === "0") {
    e.preventDefault();
    formatBlock("p");
    return;
  }

  // Bullet list: Ctrl+Shift+8
  if (mod && shift && e.key === "8") {
    e.preventDefault();
    execCommand("insertUnorderedList");
    return;
  }

  // Numbered list: Ctrl+Shift+7
  if (mod && shift && e.key === "7") {
    e.preventDefault();
    execCommand("insertOrderedList");
    return;
  }

  // Task list: Ctrl+Shift+9
  if (mod && shift && e.key === "9") {
    e.preventDefault();
    insertTaskList(state);
    return;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Other shortcuts
  // ═══════════════════════════════════════════════════════════════════════════

  // Link: Ctrl+K / Cmd+K
  if (mod && e.key === "k") {
    e.preventDefault();
    promptInsertLink(state);
    return;
  }

  // Undo: Ctrl+Z / Cmd+Z
  if (mod && !shift && e.key === "z") {
    e.preventDefault();
    performUndo(state);
    return;
  }

  // Redo: Ctrl+Shift+Z / Cmd+Shift+Z or Ctrl+Y
  if ((mod && shift && e.key === "Z") || (mod && e.key === "y")) {
    e.preventDefault();
    performRedo(state);
    return;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Slash commands
  // ═══════════════════════════════════════════════════════════════════════════

  if (e.key === "/" && options?.enableSlashCommands !== false) {
    // Check if at start of line or after whitespace
    const selection = window.getSelection();
    if (selection.rangeCount > 0) {
      const range = selection.getRangeAt(0);
      const text = range.startContainer.textContent || "";
      const offset = range.startOffset;

      // At start or after whitespace/newline
      if (offset === 0 || /\s/.test(text[offset - 1])) {
        showSlashMenu(state);
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Mentions
  // ═══════════════════════════════════════════════════════════════════════════

  if (e.key === "@" && options?.enableMentions !== false) {
    showMentionMenu(state);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Tab handling
  // ═══════════════════════════════════════════════════════════════════════════

  if (e.key === "Tab") {
    // In lists, indent/outdent
    const selection = window.getSelection();
    if (selection.rangeCount > 0) {
      const node = selection.anchorNode;
      const listItem = node?.parentElement?.closest("li");
      if (listItem) {
        e.preventDefault();
        if (shift) {
          execCommand("outdent");
        } else {
          execCommand("indent");
        }
        return;
      }
    }
    // Otherwise, allow default tab behavior or insert spaces
    if (!options?.allowTab) {
      e.preventDefault();
      execCommand("insertText", "    ");
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Enter key handling
  // ═══════════════════════════════════════════════════════════════════════════

  if (e.key === "Enter") {
    // Check for code block - insert plain newline
    const selection = window.getSelection();
    if (selection.rangeCount > 0) {
      const node = selection.anchorNode;
      const codeBlock = node?.parentElement?.closest("pre");
      if (codeBlock) {
        e.preventDefault();
        execCommand("insertText", "\n");
        return;
      }
    }

    // Shift+Enter for soft break
    if (shift) {
      e.preventDefault();
      execCommand("insertLineBreak");
      return;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Escape key - close menus
  // ═══════════════════════════════════════════════════════════════════════════

  if (e.key === "Escape") {
    hideSlashMenu(state);
    hideMentionMenu(state);
    hideBubbleMenu(state);
  }
}

/**
 * Handle paste events
 */
function handlePaste(state, e) {
  const { options } = state;

  // Get clipboard data
  const clipboardData = e.clipboardData || window.clipboardData;

  // Check for files (images)
  if (clipboardData.files && clipboardData.files.length > 0) {
    const file = clipboardData.files[0];
    if (file.type.startsWith("image/") && options?.enableImages !== false) {
      e.preventDefault();
      handleImageUpload(state, file);
      return;
    }
  }

  // Check for HTML content
  const html = clipboardData.getData("text/html");
  const text = clipboardData.getData("text/plain");

  // If we have HTML and rich paste is enabled
  if (html && options?.pasteAsRich !== false) {
    e.preventDefault();
    // Sanitize HTML before inserting
    const sanitized = sanitizeHtml(html);
    execCommand("insertHTML", sanitized);
    return;
  }

  // Plain text paste
  if (text) {
    e.preventDefault();
    execCommand("insertText", text);
  }
}

/**
 * Handle drop events
 */
function handleDrop(state, e) {
  const { options } = state;

  // Check for files
  if (e.dataTransfer.files && e.dataTransfer.files.length > 0) {
    const file = e.dataTransfer.files[0];
    if (file.type.startsWith("image/") && options?.enableImages !== false) {
      e.preventDefault();
      handleImageUpload(state, file);
      return;
    }
  }

  // Check for text/HTML
  const html = e.dataTransfer.getData("text/html");
  const text = e.dataTransfer.getData("text/plain");

  if (html) {
    e.preventDefault();
    const sanitized = sanitizeHtml(html);
    execCommand("insertHTML", sanitized);
  } else if (text) {
    e.preventDefault();
    execCommand("insertText", text);
  }
}

/**
 * Handle focus events
 */
function handleFocus(state, e) {
  state.container.setAttribute("data-focused", "true");
}

/**
 * Handle blur events
 */
function handleBlur(state, e) {
  state.container.removeAttribute("data-focused");

  // Hide menus on blur (with delay to allow clicking on menu items)
  setTimeout(() => {
    if (!state.container.contains(document.activeElement)) {
      hideBubbleMenu(state);
      hideSlashMenu(state);
      hideMentionMenu(state);
    }
  }, 150);
}

/**
 * Handle selection change for bubble menu
 */
function handleSelectionChange(state) {
  const { contentEl, options } = state;

  if (options?.enableBubbleMenu === false) return;

  const selection = window.getSelection();
  if (!selection || selection.rangeCount === 0) return;

  const range = selection.getRangeAt(0);

  // Check if selection is within our editor
  if (!contentEl.contains(range.commonAncestorContainer)) {
    hideBubbleMenu(state);
    return;
  }

  // Show bubble menu if there's a selection
  if (!selection.isCollapsed) {
    showBubbleMenu(state);
  } else {
    hideBubbleMenu(state);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//                                                               // undo/redo
// ═══════════════════════════════════════════════════════════════════════════════

const MAX_UNDO_STACK = 100;

/**
 * Save current state to undo stack
 */
function saveToUndoStack(state) {
  const { contentEl, undoStack, redoStack } = state;
  const html = contentEl.innerHTML;

  // Don't save if same as last entry
  if (undoStack.length > 0 && undoStack[undoStack.length - 1] === html) {
    return;
  }

  undoStack.push(html);

  // Limit stack size
  if (undoStack.length > MAX_UNDO_STACK) {
    undoStack.shift();
  }

  // Clear redo stack on new edit
  redoStack.length = 0;
}

// Debounced undo save
let undoTimeout = null;
function debouncedSaveUndo(state) {
  if (undoTimeout) clearTimeout(undoTimeout);
  undoTimeout = setTimeout(() => {
    saveToUndoStack(state);
  }, 300);
}

/**
 * Perform undo operation
 */
function performUndo(state) {
  const { contentEl, undoStack, redoStack, onChange } = state;

  if (undoStack.length <= 1) return; // Keep at least one state

  // Save current state to redo
  redoStack.push(contentEl.innerHTML);

  // Pop and apply previous state
  undoStack.pop(); // Remove current
  const previousState = undoStack[undoStack.length - 1];

  if (previousState !== undefined) {
    contentEl.innerHTML = previousState;
    state.lastContent = previousState;
    updateCounts(state);

    if (onChange) {
      onChange({ type: "html", content: previousState })();
    }
  }
}

/**
 * Perform redo operation
 */
function performRedo(state) {
  const { contentEl, undoStack, redoStack, onChange } = state;

  if (redoStack.length === 0) return;

  const nextState = redoStack.pop();

  if (nextState !== undefined) {
    undoStack.push(nextState);
    contentEl.innerHTML = nextState;
    state.lastContent = nextState;
    updateCounts(state);

    if (onChange) {
      onChange({ type: "html", content: nextState })();
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//                                                             // exec commands
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Execute document.execCommand with fallback
 */
function execCommand(command, value = null) {
  try {
    document.execCommand(command, false, value);
  } catch (e) {
    console.warn(`execCommand '${command}' failed:`, e);
    // Fallback implementations for deprecated commands could go here
  }
}

/**
 * Format block element (heading, paragraph)
 */
function formatBlock(tag) {
  execCommand("formatBlock", `<${tag}>`);
}

/**
 * Toggle inline code formatting
 */
function toggleInlineCode(state) {
  const selection = window.getSelection();
  if (!selection || selection.rangeCount === 0) return;

  const range = selection.getRangeAt(0);

  // Check if already in code element
  const codeEl = range.commonAncestorContainer?.parentElement?.closest("code");

  if (codeEl && !codeEl.closest("pre")) {
    // Remove code formatting
    const text = codeEl.textContent;
    const textNode = document.createTextNode(text);
    codeEl.parentNode.replaceChild(textNode, codeEl);

    // Restore selection
    const newRange = document.createRange();
    newRange.selectNodeContents(textNode);
    selection.removeAllRanges();
    selection.addRange(newRange);
  } else {
    // Add code formatting
    const selectedText = range.toString();
    if (selectedText) {
      const code = document.createElement("code");
      code.className =
        "px-1.5 py-0.5 rounded bg-muted font-mono text-sm text-foreground";
      code.textContent = selectedText;
      range.deleteContents();
      range.insertNode(code);

      // Move cursor after code element
      const newRange = document.createRange();
      newRange.setStartAfter(code);
      newRange.collapse(true);
      selection.removeAllRanges();
      selection.addRange(newRange);
    }
  }
}

/**
 * Insert task list
 */
function insertTaskList(state) {
  const selection = window.getSelection();
  if (!selection || selection.rangeCount === 0) return;

  // Check if already in a list
  const range = selection.getRangeAt(0);
  const listItem = range.commonAncestorContainer?.parentElement?.closest("li");

  if (listItem) {
    // Convert existing list to task list
    const list = listItem.closest("ul, ol");
    if (list) {
      list.setAttribute("data-type", "taskList");
      list.querySelectorAll("li").forEach((li) => {
        if (!li.querySelector('input[type="checkbox"]')) {
          const checkbox = document.createElement("input");
          checkbox.type = "checkbox";
          checkbox.className = "mr-2 h-4 w-4 rounded border-input";
          li.insertBefore(checkbox, li.firstChild);
        }
      });
    }
  } else {
    // Create new task list
    const ul = document.createElement("ul");
    ul.setAttribute("data-type", "taskList");
    ul.className = "list-none space-y-1";

    const li = document.createElement("li");
    li.className = "flex items-start gap-2";

    const checkbox = document.createElement("input");
    checkbox.type = "checkbox";
    checkbox.className =
      "mt-1 h-4 w-4 rounded border-input ring-offset-background focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring";

    const span = document.createElement("span");
    span.contentEditable = "true";
    span.textContent = range.toString() || "";

    li.appendChild(checkbox);
    li.appendChild(span);
    ul.appendChild(li);

    range.deleteContents();
    range.insertNode(ul);

    // Focus the text span
    span.focus();
  }
}

/**
 * Prompt and insert link
 */
function promptInsertLink(state) {
  const selection = window.getSelection();
  if (!selection || selection.rangeCount === 0) return;

  const range = selection.getRangeAt(0);
  const existingLink =
    range.commonAncestorContainer?.parentElement?.closest("a");

  // Get current URL if editing existing link
  const currentUrl = existingLink?.href || "";
  const url = prompt("Enter URL:", currentUrl);

  if (url === null) return; // Cancelled

  if (url === "") {
    // Remove link
    if (existingLink) {
      const text = existingLink.textContent;
      const textNode = document.createTextNode(text);
      existingLink.parentNode.replaceChild(textNode, existingLink);
    }
  } else {
    // Insert or update link
    execCommand("createLink", url);
  }
}

/**
 * Insert image (placeholder for upload)
 */
function handleImageUpload(state, file) {
  // Create FileReader to get data URL
  const reader = new FileReader();
  reader.onload = (e) => {
    const dataUrl = e.target.result;
    insertImage(state, dataUrl, file.name);
  };
  reader.readAsDataURL(file);
}

/**
 * Insert image element
 */
function insertImage(state, src, alt = "") {
  const img = document.createElement("img");
  img.src = src;
  img.alt = alt;
  img.className = "max-w-full h-auto rounded-lg my-4";

  const selection = window.getSelection();
  if (selection && selection.rangeCount > 0) {
    const range = selection.getRangeAt(0);
    range.deleteContents();
    range.insertNode(img);

    // Move cursor after image
    const newRange = document.createRange();
    newRange.setStartAfter(img);
    newRange.collapse(true);
    selection.removeAllRanges();
    selection.addRange(newRange);
  }
}

/**
 * Insert table
 */
function insertTable(state, rows = 3, cols = 3) {
  const table = document.createElement("table");
  table.className =
    "w-full border-collapse border border-border my-4 text-sm";

  for (let i = 0; i < rows; i++) {
    const tr = document.createElement("tr");
    for (let j = 0; j < cols; j++) {
      const cell = i === 0 ? document.createElement("th") : document.createElement("td");
      cell.className = "border border-border p-2";
      cell.contentEditable = "true";
      cell.innerHTML = "&nbsp;";
      tr.appendChild(cell);
    }
    table.appendChild(tr);
  }

  const selection = window.getSelection();
  if (selection && selection.rangeCount > 0) {
    const range = selection.getRangeAt(0);
    range.deleteContents();
    range.insertNode(table);

    // Focus first cell
    const firstCell = table.querySelector("th, td");
    if (firstCell) {
      const newRange = document.createRange();
      newRange.selectNodeContents(firstCell);
      newRange.collapse(true);
      selection.removeAllRanges();
      selection.addRange(newRange);
    }
  }
}

/**
 * Insert code block
 */
function insertCodeBlock(state, language = "") {
  const pre = document.createElement("pre");
  pre.className =
    "bg-muted p-4 rounded-lg overflow-x-auto my-4 font-mono text-sm";
  if (language) {
    pre.setAttribute("data-language", language);
  }

  const code = document.createElement("code");
  code.className = language ? `language-${language}` : "";
  code.contentEditable = "true";
  code.textContent = "\n";

  pre.appendChild(code);

  const selection = window.getSelection();
  if (selection && selection.rangeCount > 0) {
    const range = selection.getRangeAt(0);
    range.deleteContents();
    range.insertNode(pre);

    // Focus code element
    const newRange = document.createRange();
    newRange.selectNodeContents(code);
    newRange.collapse(true);
    selection.removeAllRanges();
    selection.addRange(newRange);
  }
}

/**
 * Insert blockquote
 */
function insertBlockquote(state) {
  const selection = window.getSelection();
  if (!selection || selection.rangeCount === 0) return;

  const range = selection.getRangeAt(0);
  const selectedText = range.toString();

  const blockquote = document.createElement("blockquote");
  blockquote.className =
    "border-l-4 border-border pl-4 my-4 italic text-muted-foreground";

  const p = document.createElement("p");
  p.textContent = selectedText || "";

  blockquote.appendChild(p);

  range.deleteContents();
  range.insertNode(blockquote);

  // Focus the paragraph
  const newRange = document.createRange();
  newRange.selectNodeContents(p);
  newRange.collapse(false);
  selection.removeAllRanges();
  selection.addRange(newRange);
}

/**
 * Insert horizontal rule
 */
function insertHorizontalRule(state) {
  execCommand("insertHorizontalRule");
}

// ═══════════════════════════════════════════════════════════════════════════════
//                                                                     // menus
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Setup menu elements
 */
function setupMenus(state) {
  const { container } = state;

  // Find or create menu elements
  state.menus.bubble = container.querySelector("[data-bubble-menu]");
  state.menus.slash = container.querySelector("[data-slash-menu]");
  state.menus.mention = container.querySelector("[data-mention-menu]");
}

/**
 * Show bubble menu at selection
 */
export const showBubbleMenuImpl = (state, menuEl) => {
  if (!menuEl) menuEl = state.menus.bubble;
  if (!menuEl) return;

  const selection = window.getSelection();
  if (!selection || selection.rangeCount === 0) return;

  const range = selection.getRangeAt(0);
  const rect = range.getBoundingClientRect();
  const containerRect = state.container.getBoundingClientRect();

  // Position above selection
  const top = rect.top - containerRect.top - menuEl.offsetHeight - 8;
  const left =
    rect.left - containerRect.left + rect.width / 2 - menuEl.offsetWidth / 2;

  menuEl.style.top = `${Math.max(0, top)}px`;
  menuEl.style.left = `${Math.max(0, left)}px`;
  menuEl.classList.remove("hidden");
  menuEl.classList.add("flex");

  // Update active states on buttons
  updateToolbarActiveStates(state, menuEl);
};

function showBubbleMenu(state) {
  showBubbleMenuImpl(state, state.menus.bubble);
}

/**
 * Hide bubble menu
 */
export const hideBubbleMenuImpl = (state) => {
  if (state.menus.bubble) {
    state.menus.bubble.classList.add("hidden");
    state.menus.bubble.classList.remove("flex");
  }
};

function hideBubbleMenu(state) {
  hideBubbleMenuImpl(state);
}

/**
 * Show slash command menu
 */
export const showSlashMenuImpl = (state, menuEl) => {
  if (!menuEl) menuEl = state.menus.slash;
  if (!menuEl) return;

  const selection = window.getSelection();
  if (!selection || selection.rangeCount === 0) return;

  const range = selection.getRangeAt(0);
  const rect = range.getBoundingClientRect();
  const containerRect = state.container.getBoundingClientRect();

  // Position below cursor
  const top = rect.bottom - containerRect.top + 4;
  const left = rect.left - containerRect.left;

  menuEl.style.top = `${top}px`;
  menuEl.style.left = `${left}px`;
  menuEl.classList.remove("hidden");

  // Focus first item
  const firstItem = menuEl.querySelector("[data-command-id]");
  if (firstItem) {
    firstItem.setAttribute("aria-selected", "true");
  }
};

function showSlashMenu(state) {
  showSlashMenuImpl(state, state.menus.slash);
}

/**
 * Hide slash command menu
 */
export const hideSlashMenuImpl = (state) => {
  if (state.menus.slash) {
    state.menus.slash.classList.add("hidden");
    // Clear selection states
    state.menus.slash.querySelectorAll("[aria-selected]").forEach((el) => {
      el.removeAttribute("aria-selected");
    });
  }
};

function hideSlashMenu(state) {
  hideSlashMenuImpl(state);
}

/**
 * Show mention menu
 */
export const showMentionMenuImpl = (state, menuEl) => {
  if (!menuEl) menuEl = state.menus.mention;
  if (!menuEl) return;

  const selection = window.getSelection();
  if (!selection || selection.rangeCount === 0) return;

  const range = selection.getRangeAt(0);
  const rect = range.getBoundingClientRect();
  const containerRect = state.container.getBoundingClientRect();

  // Position below cursor
  const top = rect.bottom - containerRect.top + 4;
  const left = rect.left - containerRect.left;

  menuEl.style.top = `${top}px`;
  menuEl.style.left = `${left}px`;
  menuEl.classList.remove("hidden");
};

function showMentionMenu(state) {
  showMentionMenuImpl(state, state.menus.mention);
}

/**
 * Hide mention menu
 */
export const hideMentionMenuImpl = (state) => {
  if (state.menus.mention) {
    state.menus.mention.classList.add("hidden");
  }
};

function hideMentionMenu(state) {
  hideMentionMenuImpl(state);
}

// ═══════════════════════════════════════════════════════════════════════════════
//                                                              // toolbar state
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Get current toolbar/formatting state
 */
export const getToolbarStateImpl = (state) => {
  const selection = window.getSelection();
  if (!selection || selection.rangeCount === 0) {
    return {
      bold: false,
      italic: false,
      underline: false,
      strikethrough: false,
      code: false,
      heading: null,
      alignment: "left",
      bulletList: false,
      orderedList: false,
      taskList: false,
      link: null,
      canUndo: state.undoStack.length > 1,
      canRedo: state.redoStack.length > 0,
    };
  }

  const range = selection.getRangeAt(0);
  const node = range.commonAncestorContainer;
  const el = node.nodeType === Node.TEXT_NODE ? node.parentElement : node;

  // Check formatting
  const computedStyle = window.getComputedStyle(el);

  return {
    bold:
      document.queryCommandState("bold") ||
      computedStyle.fontWeight >= 600,
    italic:
      document.queryCommandState("italic") ||
      computedStyle.fontStyle === "italic",
    underline:
      document.queryCommandState("underline") ||
      computedStyle.textDecoration.includes("underline"),
    strikethrough:
      document.queryCommandState("strikeThrough") ||
      computedStyle.textDecoration.includes("line-through"),
    code: !!el.closest("code"),
    heading: getHeadingLevel(el),
    alignment: getTextAlignment(el),
    bulletList: !!el.closest("ul:not([data-type])"),
    orderedList: !!el.closest("ol"),
    taskList: !!el.closest('[data-type="taskList"]'),
    link: el.closest("a")?.href || null,
    canUndo: state.undoStack.length > 1,
    canRedo: state.redoStack.length > 0,
  };
};

/**
 * Get heading level of element
 */
function getHeadingLevel(el) {
  const heading = el.closest("h1, h2, h3, h4, h5, h6");
  if (!heading) return null;
  return heading.tagName.toLowerCase();
}

/**
 * Get text alignment of element
 */
function getTextAlignment(el) {
  const block = el.closest("p, h1, h2, h3, h4, h5, h6, div, li");
  if (!block) return "left";

  const style = window.getComputedStyle(block);
  return style.textAlign || "left";
}

/**
 * Update toolbar button active states
 */
function updateToolbarActiveStates(state, toolbar) {
  const toolbarState = getToolbarStateImpl(state);

  // Update data-active attributes
  toolbar.querySelectorAll("[data-command]").forEach((btn) => {
    const command = btn.getAttribute("data-command");
    let isActive = false;

    switch (command) {
      case "bold":
        isActive = toolbarState.bold;
        break;
      case "italic":
        isActive = toolbarState.italic;
        break;
      case "underline":
        isActive = toolbarState.underline;
        break;
      case "strikethrough":
        isActive = toolbarState.strikethrough;
        break;
      case "code":
        isActive = toolbarState.code;
        break;
      case "heading1":
        isActive = toolbarState.heading === "h1";
        break;
      case "heading2":
        isActive = toolbarState.heading === "h2";
        break;
      case "heading3":
        isActive = toolbarState.heading === "h3";
        break;
      case "bulletList":
        isActive = toolbarState.bulletList;
        break;
      case "orderedList":
        isActive = toolbarState.orderedList;
        break;
      case "taskList":
        isActive = toolbarState.taskList;
        break;
      case "alignLeft":
        isActive = toolbarState.alignment === "left";
        break;
      case "alignCenter":
        isActive = toolbarState.alignment === "center";
        break;
      case "alignRight":
        isActive = toolbarState.alignment === "right";
        break;
      case "alignJustify":
        isActive = toolbarState.alignment === "justify";
        break;
      case "link":
        isActive = toolbarState.link !== null;
        break;
    }

    btn.setAttribute("data-active", isActive ? "true" : "false");
  });
}

// ═══════════════════════════════════════════════════════════════════════════════
//                                                              // content access
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Get HTML content from editor
 */
export const getHtmlImpl = (state) => {
  return state.contentEl?.innerHTML || "";
};

/**
 * Set HTML content in editor
 */
export const setHtmlImpl = (state, html) => {
  if (state.contentEl) {
    state.contentEl.innerHTML = html;
    state.lastContent = html;
    saveToUndoStack(state);
    updateCounts(state);
  }
};

/**
 * Get JSON content from editor
 */
export const getJsonImpl = (state) => {
  const html = state.contentEl?.innerHTML || "";
  return htmlToJson(html);
};

/**
 * Set JSON content in editor
 */
export const setJsonImpl = (state, json) => {
  if (state.contentEl) {
    const html = jsonToHtml(json);
    state.contentEl.innerHTML = html;
    state.lastContent = html;
    saveToUndoStack(state);
    updateCounts(state);
  }
};

/**
 * Convert HTML to JSON document structure
 */
function htmlToJson(html) {
  const doc = new DOMParser().parseFromString(html, "text/html");
  return parseNode(doc.body);
}

/**
 * Parse DOM node to JSON
 */
function parseNode(node) {
  if (node.nodeType === Node.TEXT_NODE) {
    return {
      type: "text",
      text: node.textContent,
      marks: [],
    };
  }

  if (node.nodeType !== Node.ELEMENT_NODE) {
    return null;
  }

  const tag = node.tagName.toLowerCase();
  const children = Array.from(node.childNodes)
    .map(parseNode)
    .filter((n) => n !== null);

  switch (tag) {
    case "p":
      return { type: "paragraph", content: children };
    case "h1":
      return { type: "heading", level: 1, content: children };
    case "h2":
      return { type: "heading", level: 2, content: children };
    case "h3":
      return { type: "heading", level: 3, content: children };
    case "ul":
      return { type: "bulletList", content: children };
    case "ol":
      return { type: "orderedList", content: children };
    case "li":
      return { type: "listItem", content: children };
    case "blockquote":
      return { type: "blockquote", content: children };
    case "pre":
      return {
        type: "codeBlock",
        language: node.getAttribute("data-language") || null,
        content: children,
      };
    case "code":
      return { type: "code", content: children };
    case "a":
      return { type: "link", href: node.href, content: children };
    case "img":
      return { type: "image", src: node.src, alt: node.alt };
    case "hr":
      return { type: "horizontalRule" };
    case "table":
      return { type: "table", content: children };
    case "tr":
      return { type: "tableRow", content: children };
    case "td":
    case "th":
      return { type: "tableCell", header: tag === "th", content: children };
    case "strong":
    case "b":
      return { type: "bold", content: children };
    case "em":
    case "i":
      return { type: "italic", content: children };
    case "u":
      return { type: "underline", content: children };
    case "s":
    case "strike":
      return { type: "strikethrough", content: children };
    case "br":
      return { type: "hardBreak" };
    default:
      return { type: "unknown", tag, content: children };
  }
}

/**
 * Convert JSON document to HTML
 */
function jsonToHtml(json) {
  if (!json) return "";
  if (Array.isArray(json)) {
    return json.map(jsonToHtml).join("");
  }

  switch (json.type) {
    case "text":
      return escapeHtml(json.text || "");
    case "paragraph":
      return `<p>${jsonToHtml(json.content)}</p>`;
    case "heading":
      return `<h${json.level}>${jsonToHtml(json.content)}</h${json.level}>`;
    case "bulletList":
      return `<ul>${jsonToHtml(json.content)}</ul>`;
    case "orderedList":
      return `<ol>${jsonToHtml(json.content)}</ol>`;
    case "listItem":
      return `<li>${jsonToHtml(json.content)}</li>`;
    case "blockquote":
      return `<blockquote>${jsonToHtml(json.content)}</blockquote>`;
    case "codeBlock": {
      const lang = json.language ? ` data-language="${json.language}"` : "";
      return `<pre${lang}><code>${jsonToHtml(json.content)}</code></pre>`;
    }
    case "code":
      return `<code>${jsonToHtml(json.content)}</code>`;
    case "link":
      return `<a href="${escapeHtml(json.href)}">${jsonToHtml(json.content)}</a>`;
    case "image":
      return `<img src="${escapeHtml(json.src)}" alt="${escapeHtml(json.alt || "")}">`;
    case "horizontalRule":
      return "<hr>";
    case "table":
      return `<table>${jsonToHtml(json.content)}</table>`;
    case "tableRow":
      return `<tr>${jsonToHtml(json.content)}</tr>`;
    case "tableCell": {
      const cellTag = json.header ? "th" : "td";
      return `<${cellTag}>${jsonToHtml(json.content)}</${cellTag}>`;
    }
    case "bold":
      return `<strong>${jsonToHtml(json.content)}</strong>`;
    case "italic":
      return `<em>${jsonToHtml(json.content)}</em>`;
    case "underline":
      return `<u>${jsonToHtml(json.content)}</u>`;
    case "strikethrough":
      return `<s>${jsonToHtml(json.content)}</s>`;
    case "hardBreak":
      return "<br>";
    default:
      return jsonToHtml(json.content);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//                                                                   // selection
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Get current selection state
 */
export const getSelectionImpl = (state) => {
  const selection = window.getSelection();
  if (!selection || selection.rangeCount === 0) {
    return { from: 0, to: 0, empty: true };
  }

  const range = selection.getRangeAt(0);

  // Calculate character offsets
  const preRange = document.createRange();
  preRange.selectNodeContents(state.contentEl);
  preRange.setEnd(range.startContainer, range.startOffset);
  const from = preRange.toString().length;

  preRange.setEnd(range.endContainer, range.endOffset);
  const to = preRange.toString().length;

  return {
    from,
    to,
    empty: selection.isCollapsed,
  };
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                                    // commands
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Execute editor command
 */
export const executeCommandImpl = (state, command) => {
  if (!state.contentEl) return;

  // Focus editor first
  state.contentEl.focus();

  switch (command.type) {
    case "bold":
      execCommand("bold");
      break;
    case "italic":
      execCommand("italic");
      break;
    case "underline":
      execCommand("underline");
      break;
    case "strikethrough":
      execCommand("strikeThrough");
      break;
    case "code":
      toggleInlineCode(state);
      break;
    case "heading":
      formatBlock(`h${command.level}`);
      break;
    case "paragraph":
      formatBlock("p");
      break;
    case "bulletList":
      execCommand("insertUnorderedList");
      break;
    case "orderedList":
      execCommand("insertOrderedList");
      break;
    case "taskList":
      insertTaskList(state);
      break;
    case "alignLeft":
      execCommand("justifyLeft");
      break;
    case "alignCenter":
      execCommand("justifyCenter");
      break;
    case "alignRight":
      execCommand("justifyRight");
      break;
    case "alignJustify":
      execCommand("justifyFull");
      break;
    case "link":
      if (command.url) {
        execCommand("createLink", command.url);
      } else {
        promptInsertLink(state);
      }
      break;
    case "image":
      insertImage(state, command.src, command.alt);
      break;
    case "table":
      insertTable(state, command.rows || 3, command.cols || 3);
      break;
    case "codeBlock":
      insertCodeBlock(state, command.language);
      break;
    case "blockquote":
      insertBlockquote(state);
      break;
    case "horizontalRule":
      insertHorizontalRule(state);
      break;
    case "undo":
      performUndo(state);
      break;
    case "redo":
      performRedo(state);
      break;
    case "focus":
      state.contentEl.focus();
      break;
    case "blur":
      state.contentEl.blur();
      break;
  }

  // Save to undo stack after command
  saveToUndoStack(state);
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                                     // counts
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Get character count
 */
export const getCharacterCountImpl = (state) => {
  const text = state.contentEl?.textContent || "";
  return text.length;
};

/**
 * Get word count
 */
export const getWordCountImpl = (state) => {
  const text = state.contentEl?.textContent || "";
  if (!text.trim()) return 0;
  return text.trim().split(/\s+/).length;
};

/**
 * Update displayed counts
 */
function updateCounts(state) {
  const { container, options } = state;

  const charCount = getCharacterCountImpl(state);
  const wordCount = getWordCountImpl(state);

  // Update character count display
  const charEl = container.querySelector("[data-character-count]");
  if (charEl) {
    if (options?.characterLimit) {
      charEl.textContent = `${charCount} / ${options.characterLimit}`;
      // Add warning class if near limit
      if (charCount > options.characterLimit * 0.9) {
        charEl.classList.add("text-destructive");
      } else {
        charEl.classList.remove("text-destructive");
      }
    } else {
      charEl.textContent = `${charCount} characters`;
    }
  }

  // Update word count display
  const wordEl = container.querySelector("[data-word-count]");
  if (wordEl) {
    wordEl.textContent = `${wordCount} ${wordCount === 1 ? "word" : "words"}`;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//                                                                   // shortcuts
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Register keyboard shortcuts
 */
export const registerShortcutsImpl = (state, callback) => {
  // Keyboard handling is already done in handleKeyDown
  // This is for external shortcut registration if needed
  const handler = (e) => {
    const isMac = navigator.platform.toUpperCase().indexOf("MAC") >= 0;
    const mod = isMac ? e.metaKey : e.ctrlKey;

    if (!mod) return;

    // Map shortcuts to commands
    let command = null;

    if (e.key === "b") command = { type: "bold" };
    else if (e.key === "i") command = { type: "italic" };
    else if (e.key === "u") command = { type: "underline" };
    else if (e.key === "k") command = { type: "link" };
    else if (e.key === "z" && !e.shiftKey) command = { type: "undo" };
    else if ((e.key === "z" && e.shiftKey) || e.key === "y")
      command = { type: "redo" };

    if (command) {
      callback(command)();
    }
  };

  document.addEventListener("keydown", handler);
  state.shortcuts = () => document.removeEventListener("keydown", handler);

  return state.shortcuts;
};

/**
 * Unregister keyboard shortcuts
 */
export const unregisterShortcutsImpl = (cleanup) => {
  if (typeof cleanup === "function") {
    cleanup();
  }
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                                  // focus/blur
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Focus the editor
 */
export const focusEditorImpl = (state) => {
  if (state.contentEl) {
    state.contentEl.focus();
  }
};

/**
 * Blur the editor
 */
export const blurEditorImpl = (state) => {
  if (state.contentEl) {
    state.contentEl.blur();
  }
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                                  // placeholder
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Setup placeholder handling
 */
function setupPlaceholder(state) {
  const { contentEl } = state;

  const updatePlaceholder = () => {
    const isEmpty =
      !contentEl.textContent?.trim() &&
      !contentEl.querySelector("img, hr, table");

    if (isEmpty) {
      contentEl.classList.add("is-empty");
    } else {
      contentEl.classList.remove("is-empty");
    }
  };

  // Add CSS for placeholder
  const style = document.createElement("style");
  style.textContent = `
    [contenteditable].is-empty:before {
      content: attr(data-placeholder);
      color: var(--muted-foreground, #9ca3af);
      pointer-events: none;
      position: absolute;
    }
  `;
  document.head.appendChild(style);

  // Initial check
  updatePlaceholder();

  // Update on input
  const originalHandler = state._handleInput;
  state._handleInput = (e) => {
    updatePlaceholder();
    if (originalHandler) originalHandler(e);
  };
  contentEl.removeEventListener("input", originalHandler);
  contentEl.addEventListener("input", state._handleInput);
}

// ═══════════════════════════════════════════════════════════════════════════════
//                                                                     // helpers
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Sanitize HTML to prevent XSS
 */
function sanitizeHtml(html) {
  // Create a temporary element
  const temp = document.createElement("div");
  temp.innerHTML = html;

  // Remove script tags
  temp.querySelectorAll("script").forEach((el) => {
    el.remove();
  });

  // Remove event handlers
  temp.querySelectorAll("*").forEach((el) => {
    Array.from(el.attributes).forEach((attr) => {
      if (attr.name.startsWith("on")) {
        el.removeAttribute(attr.name);
      }
    });
  });

  // Remove dangerous elements
  temp.querySelectorAll("iframe, object, embed, form").forEach((el) => {
    el.remove();
  });

  return temp.innerHTML;
}

/**
 * Escape HTML entities
 */
function escapeHtml(str) {
  const div = document.createElement("div");
  div.textContent = str;
  return div.innerHTML;
}
