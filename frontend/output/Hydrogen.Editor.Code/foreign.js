// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//                                                     // hydrogen // code-editor
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//
// JavaScript FFI for the code editor component:
// - Text buffer management
// - Tokenization/lexing for syntax highlighting
// - Selection management with multiple cursors
// - Viewport virtualization for large files
// - Undo/redo stack
// - Keyboard command handling

// ═══════════════════════════════════════════════════════════════════════════════
//                                                             // array utilities
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Get array length
 */
export const arrayLength = (arr) => arr.length;

/**
 * Unsafe array index access
 */
export const unsafeIndex = (arr) => (idx) => arr[idx];

/**
 * Generate integer range
 */
export const rangeImpl = (start) => (end) => {
  const result = [];
  for (let i = start; i <= end; i++) {
    result.push(i);
  }
  return result;
};

/**
 * Map over array
 */
export const mapImpl = (f) => (arr) => arr.map(f);

// ═══════════════════════════════════════════════════════════════════════════════
//                                                              // text buffer
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Text buffer class for efficient text manipulation
 * Uses piece table approach for O(1) insertions
 */
class TextBuffer {
  constructor(initialText = '') {
    this.original = initialText;
    this.added = '';
    this.pieces = [{ type: 'original', start: 0, length: initialText.length }];
    this.lineStarts = this._computeLineStarts(initialText);
    this.version = 0;
  }

  /**
   * Get full text content
   */
  getText() {
    let result = '';
    for (const piece of this.pieces) {
      const source = piece.type === 'original' ? this.original : this.added;
      result += source.substring(piece.start, piece.start + piece.length);
    }
    return result;
  }

  /**
   * Set entire text content
   */
  setText(text) {
    this.original = text;
    this.added = '';
    this.pieces = [{ type: 'original', start: 0, length: text.length }];
    this.lineStarts = this._computeLineStarts(text);
    this.version++;
  }

  /**
   * Insert text at offset
   */
  insert(offset, text) {
    if (text.length === 0) return;

    const addedStart = this.added.length;
    this.added += text;

    const newPiece = { type: 'added', start: addedStart, length: text.length };
    this._splitAndInsert(offset, newPiece);
    
    this.lineStarts = this._computeLineStarts(this.getText());
    this.version++;
  }

  /**
   * Delete text from offset with given length
   */
  delete(offset, length) {
    if (length === 0) return;

    this._deleteRange(offset, length);
    this.lineStarts = this._computeLineStarts(this.getText());
    this.version++;
  }

  /**
   * Replace text at offset
   */
  replace(offset, length, newText) {
    this.delete(offset, length);
    this.insert(offset, newText);
  }

  /**
   * Get line at index (0-based)
   */
  getLine(lineIndex) {
    const text = this.getText();
    if (lineIndex < 0 || lineIndex >= this.lineStarts.length) return '';
    
    const start = this.lineStarts[lineIndex];
    const end = lineIndex + 1 < this.lineStarts.length 
      ? this.lineStarts[lineIndex + 1] - 1 
      : text.length;
    
    return text.substring(start, end);
  }

  /**
   * Get line count
   */
  getLineCount() {
    return this.lineStarts.length;
  }

  /**
   * Convert offset to line/column
   */
  offsetToPosition(offset) {
    const text = this.getText();
    offset = Math.max(0, Math.min(offset, text.length));
    
    let line = 0;
    for (let i = 0; i < this.lineStarts.length; i++) {
      if (this.lineStarts[i] <= offset) {
        line = i;
      } else {
        break;
      }
    }
    
    const column = offset - this.lineStarts[line];
    return { line: line + 1, column: column + 1 };  // 1-based
  }

  /**
   * Convert line/column to offset
   */
  positionToOffset(line, column) {
    // Convert to 0-based
    line = Math.max(0, line - 1);
    column = Math.max(0, column - 1);
    
    if (line >= this.lineStarts.length) {
      return this.getText().length;
    }
    
    const lineStart = this.lineStarts[line];
    const lineEnd = line + 1 < this.lineStarts.length 
      ? this.lineStarts[line + 1] - 1 
      : this.getText().length;
    
    return Math.min(lineStart + column, lineEnd);
  }

  /**
   * Compute line start offsets
   */
  _computeLineStarts(text) {
    const starts = [0];
    for (let i = 0; i < text.length; i++) {
      if (text[i] === '\n') {
        starts.push(i + 1);
      }
    }
    return starts;
  }

  /**
   * Split piece at offset and insert new piece
   */
  _splitAndInsert(offset, newPiece) {
    let currentOffset = 0;
    
    for (let i = 0; i < this.pieces.length; i++) {
      const piece = this.pieces[i];
      
      if (currentOffset + piece.length >= offset) {
        const splitPoint = offset - currentOffset;
        
        if (splitPoint === 0) {
          // Insert at beginning of piece
          this.pieces.splice(i, 0, newPiece);
        } else if (splitPoint === piece.length) {
          // Insert at end of piece
          this.pieces.splice(i + 1, 0, newPiece);
        } else {
          // Split the piece
          const first = { ...piece, length: splitPoint };
          const second = { ...piece, start: piece.start + splitPoint, length: piece.length - splitPoint };
          this.pieces.splice(i, 1, first, newPiece, second);
        }
        return;
      }
      
      currentOffset += piece.length;
    }
    
    // Append at end
    this.pieces.push(newPiece);
  }

  /**
   * Delete range from pieces
   */
  _deleteRange(offset, length) {
    let currentOffset = 0;
    let deleteStart = offset;
    let deleteEnd = offset + length;
    const newPieces = [];
    
    for (const piece of this.pieces) {
      const pieceStart = currentOffset;
      const pieceEnd = currentOffset + piece.length;
      
      if (pieceEnd <= deleteStart || pieceStart >= deleteEnd) {
        // Piece is outside delete range
        newPieces.push(piece);
      } else if (pieceStart >= deleteStart && pieceEnd <= deleteEnd) {
        // Piece is entirely within delete range - skip it
      } else if (pieceStart < deleteStart && pieceEnd > deleteEnd) {
        // Delete range is within piece - split it
        const firstLength = deleteStart - pieceStart;
        const secondStart = piece.start + (deleteEnd - pieceStart);
        const secondLength = pieceEnd - deleteEnd;
        
        newPieces.push({ ...piece, length: firstLength });
        newPieces.push({ ...piece, start: secondStart, length: secondLength });
      } else if (pieceStart < deleteStart) {
        // Piece starts before delete range
        const newLength = deleteStart - pieceStart;
        newPieces.push({ ...piece, length: newLength });
      } else {
        // Piece ends after delete range
        const newStart = piece.start + (deleteEnd - pieceStart);
        const newLength = pieceEnd - deleteEnd;
        newPieces.push({ ...piece, start: newStart, length: newLength });
      }
      
      currentOffset += piece.length;
    }
    
    this.pieces = newPieces;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//                                                                // undo/redo
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Undo/redo stack with operation coalescing
 */
class UndoStack {
  constructor(maxSize = 1000) {
    this.undoStack = [];
    this.redoStack = [];
    this.maxSize = maxSize;
    this.lastOperationTime = 0;
    this.coalesceTimeout = 500; // ms
  }

  /**
   * Push an operation onto the undo stack
   */
  push(operation) {
    const now = Date.now();
    
    // Coalesce rapid insertions
    if (this.undoStack.length > 0 && 
        now - this.lastOperationTime < this.coalesceTimeout &&
        operation.type === 'insert' &&
        this.undoStack[this.undoStack.length - 1].type === 'insert') {
      const last = this.undoStack[this.undoStack.length - 1];
      if (last.offset + last.text.length === operation.offset) {
        last.text += operation.text;
        this.lastOperationTime = now;
        return;
      }
    }
    
    this.undoStack.push(operation);
    this.redoStack = []; // Clear redo stack on new operation
    this.lastOperationTime = now;
    
    // Limit stack size
    if (this.undoStack.length > this.maxSize) {
      this.undoStack.shift();
    }
  }

  /**
   * Undo last operation
   */
  undo(buffer) {
    if (this.undoStack.length === 0) return null;
    
    const operation = this.undoStack.pop();
    const inverse = this._invertOperation(operation, buffer);
    this.redoStack.push(inverse);
    
    return operation;
  }

  /**
   * Redo last undone operation
   */
  redo(buffer) {
    if (this.redoStack.length === 0) return null;
    
    const operation = this.redoStack.pop();
    const inverse = this._invertOperation(operation, buffer);
    this.undoStack.push(inverse);
    
    return operation;
  }

  /**
   * Check if undo is available
   */
  canUndo() {
    return this.undoStack.length > 0;
  }

  /**
   * Check if redo is available
   */
  canRedo() {
    return this.redoStack.length > 0;
  }

  /**
   * Invert an operation for undo/redo
   */
  _invertOperation(operation, buffer) {
    switch (operation.type) {
      case 'insert':
        return {
          type: 'delete',
          offset: operation.offset,
          length: operation.text.length,
          deletedText: operation.text
        };
      case 'delete':
        return {
          type: 'insert',
          offset: operation.offset,
          text: operation.deletedText
        };
      default:
        return operation;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//                                                           // syntax tokenizer
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Token types for syntax highlighting
 */
const TokenType = {
  KEYWORD: 'keyword',
  STRING: 'string',
  NUMBER: 'number',
  COMMENT: 'comment',
  OPERATOR: 'operator',
  PUNCTUATION: 'punctuation',
  IDENTIFIER: 'identifier',
  TYPE: 'type',
  FUNCTION: 'function',
  PROPERTY: 'property',
  TAG: 'tag',
  ATTRIBUTE: 'attribute',
  TEXT: 'text'
};

/**
 * Language-specific tokenization rules
 */
const languageRules = {
  javascript: {
    keywords: ['const', 'let', 'var', 'function', 'return', 'if', 'else', 'for', 'while', 
               'do', 'switch', 'case', 'break', 'continue', 'try', 'catch', 'finally',
               'throw', 'class', 'extends', 'new', 'this', 'super', 'import', 'export',
               'from', 'default', 'async', 'await', 'yield', 'typeof', 'instanceof',
               'in', 'of', 'null', 'undefined', 'true', 'false', 'NaN', 'Infinity'],
    stringDelimiters: ["'", '"', '`'],
    lineComment: '//',
    blockComment: ['/*', '*/'],
    operators: ['+', '-', '*', '/', '%', '=', '==', '===', '!=', '!==', '<', '>', 
                '<=', '>=', '&&', '||', '!', '&', '|', '^', '~', '<<', '>>', '>>>',
                '+=', '-=', '*=', '/=', '=>', '?.', '...'],
  },
  typescript: {
    keywords: ['const', 'let', 'var', 'function', 'return', 'if', 'else', 'for', 'while',
               'do', 'switch', 'case', 'break', 'continue', 'try', 'catch', 'finally',
               'throw', 'class', 'extends', 'new', 'this', 'super', 'import', 'export',
               'from', 'default', 'async', 'await', 'yield', 'typeof', 'instanceof',
               'in', 'of', 'null', 'undefined', 'true', 'false', 'interface', 'type',
               'enum', 'implements', 'namespace', 'module', 'declare', 'abstract',
               'readonly', 'private', 'protected', 'public', 'static', 'as', 'is',
               'keyof', 'never', 'unknown', 'any', 'void', 'infer', 'satisfies'],
    types: ['string', 'number', 'boolean', 'object', 'symbol', 'bigint', 'Array',
            'Promise', 'Record', 'Partial', 'Required', 'Readonly', 'Pick', 'Omit'],
    stringDelimiters: ["'", '"', '`'],
    lineComment: '//',
    blockComment: ['/*', '*/'],
    operators: ['+', '-', '*', '/', '%', '=', '==', '===', '!=', '!==', '<', '>',
                '<=', '>=', '&&', '||', '!', '&', '|', '^', '~', '<<', '>>', '>>>',
                '+=', '-=', '*=', '/=', '=>', '?.', '...', ':'],
  },
  html: {
    tags: ['html', 'head', 'body', 'div', 'span', 'p', 'a', 'img', 'ul', 'ol', 'li',
           'table', 'tr', 'td', 'th', 'form', 'input', 'button', 'select', 'option',
           'script', 'style', 'link', 'meta', 'title', 'header', 'footer', 'nav',
           'main', 'section', 'article', 'aside', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6'],
    attributes: ['id', 'class', 'style', 'href', 'src', 'alt', 'title', 'type', 'name',
                 'value', 'placeholder', 'disabled', 'readonly', 'data-*'],
    stringDelimiters: ["'", '"'],
  },
  css: {
    properties: ['color', 'background', 'margin', 'padding', 'border', 'width', 'height',
                 'display', 'position', 'top', 'left', 'right', 'bottom', 'flex',
                 'grid', 'font', 'text', 'align', 'justify', 'transform', 'transition',
                 'animation', 'opacity', 'visibility', 'overflow', 'z-index'],
    values: ['none', 'block', 'inline', 'flex', 'grid', 'absolute', 'relative', 'fixed',
             'static', 'center', 'left', 'right', 'top', 'bottom', 'auto', 'inherit'],
    stringDelimiters: ["'", '"'],
    lineComment: null,
    blockComment: ['/*', '*/'],
  },
  json: {
    keywords: ['true', 'false', 'null'],
    stringDelimiters: ['"'],
    lineComment: null,
    blockComment: null,
  },
  markdown: {
    // Markdown uses different approach - line-based parsing
  },
  purescript: {
    keywords: ['module', 'where', 'import', 'data', 'type', 'newtype', 'class', 'instance',
               'derive', 'foreign', 'forall', 'let', 'in', 'if', 'then', 'else', 'case',
               'of', 'do', 'ado', 'true', 'false', 'infix', 'infixl', 'infixr'],
    types: ['Effect', 'Aff', 'Maybe', 'Either', 'Array', 'String', 'Int', 'Number',
            'Boolean', 'Unit', 'Void', 'Function'],
    stringDelimiters: ['"'],
    lineComment: '--',
    blockComment: ['{-', '-}'],
    operators: ['=', '::', '->', '<-', '=>', '|', '@', '\\', '.', '$', '<$>', '<*>',
                '>>=', '>>>', '<<<', '++', '+', '-', '*', '/', '==', '/=', '<', '>',
                '<=', '>=', '&&', '||'],
  },
  plaintext: {}
};

/**
 * Tokenize text for syntax highlighting
 */
function tokenize(text, language) {
  const rules = languageRules[language] || languageRules.plaintext;
  const tokens = [];
  let i = 0;
  
  while (i < text.length) {
    const remaining = text.slice(i);
    
    // Check for line comment
    if (rules.lineComment && remaining.startsWith(rules.lineComment)) {
      const endOfLine = text.indexOf('\n', i);
      const end = endOfLine === -1 ? text.length : endOfLine;
      tokens.push({
        type: TokenType.COMMENT,
        value: text.slice(i, end),
        start: i,
        end: end
      });
      i = end;
      continue;
    }
    
    // Check for block comment
    if (rules.blockComment && remaining.startsWith(rules.blockComment[0])) {
      const endMarker = rules.blockComment[1];
      const endIdx = text.indexOf(endMarker, i + rules.blockComment[0].length);
      const end = endIdx === -1 ? text.length : endIdx + endMarker.length;
      tokens.push({
        type: TokenType.COMMENT,
        value: text.slice(i, end),
        start: i,
        end: end
      });
      i = end;
      continue;
    }
    
    // Check for strings
    if (rules.stringDelimiters) {
      let matched = false;
      for (const delim of rules.stringDelimiters) {
        if (remaining.startsWith(delim)) {
          const end = findStringEnd(text, i, delim);
          tokens.push({
            type: TokenType.STRING,
            value: text.slice(i, end),
            start: i,
            end: end
          });
          i = end;
          matched = true;
          break;
        }
      }
      if (matched) continue;
    }
    
    // Check for numbers
    const numMatch = remaining.match(/^-?(?:0[xXbBoO])?[\d.]+(?:[eE][+-]?\d+)?[nfFdDlL]?/);
    if (numMatch && numMatch[0] && /\d/.test(numMatch[0])) {
      tokens.push({
        type: TokenType.NUMBER,
        value: numMatch[0],
        start: i,
        end: i + numMatch[0].length
      });
      i += numMatch[0].length;
      continue;
    }
    
    // Check for identifiers and keywords
    const idMatch = remaining.match(/^[a-zA-Z_$][\w$]*/);
    if (idMatch) {
      const word = idMatch[0];
      let type = TokenType.IDENTIFIER;
      
      if (rules.keywords && rules.keywords.includes(word)) {
        type = TokenType.KEYWORD;
      } else if (rules.types && rules.types.includes(word)) {
        type = TokenType.TYPE;
      } else if (rules.tags && rules.tags.includes(word.toLowerCase())) {
        type = TokenType.TAG;
      }
      
      // Check if followed by ( for function
      const afterWord = text.slice(i + word.length).trimStart();
      if (afterWord.startsWith('(') && type === TokenType.IDENTIFIER) {
        type = TokenType.FUNCTION;
      }
      
      tokens.push({
        type: type,
        value: word,
        start: i,
        end: i + word.length
      });
      i += word.length;
      continue;
    }
    
    // Check for operators
    if (rules.operators) {
      let matched = false;
      // Sort by length descending to match longer operators first
      const sortedOps = [...rules.operators].sort((a, b) => b.length - a.length);
      for (const op of sortedOps) {
        if (remaining.startsWith(op)) {
          tokens.push({
            type: TokenType.OPERATOR,
            value: op,
            start: i,
            end: i + op.length
          });
          i += op.length;
          matched = true;
          break;
        }
      }
      if (matched) continue;
    }
    
    // Check for punctuation
    if (/^[{}()\[\];,:]/.test(remaining[0])) {
      tokens.push({
        type: TokenType.PUNCTUATION,
        value: remaining[0],
        start: i,
        end: i + 1
      });
      i++;
      continue;
    }
    
    // Default: single character as text
    tokens.push({
      type: TokenType.TEXT,
      value: remaining[0],
      start: i,
      end: i + 1
    });
    i++;
  }
  
  return tokens;
}

/**
 * Find end of string including escape handling
 */
function findStringEnd(text, start, delimiter) {
  let i = start + delimiter.length;
  const isTemplate = delimiter === '`';
  
  while (i < text.length) {
    if (text[i] === '\\') {
      i += 2; // Skip escaped character
      continue;
    }
    
    if (isTemplate && text[i] === '$' && text[i + 1] === '{') {
      // Template literal interpolation - find matching }
      let depth = 1;
      i += 2;
      while (i < text.length && depth > 0) {
        if (text[i] === '{') depth++;
        if (text[i] === '}') depth--;
        i++;
      }
      continue;
    }
    
    if (text.slice(i).startsWith(delimiter)) {
      return i + delimiter.length;
    }
    
    // Single-quoted and double-quoted strings can't span lines
    if (!isTemplate && text[i] === '\n') {
      return i;
    }
    
    i++;
  }
  
  return text.length;
}

// ═══════════════════════════════════════════════════════════════════════════════
//                                                         // selection manager
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Selection manager for multiple cursors
 */
class SelectionManager {
  constructor() {
    this.selections = [];
    this.primaryIndex = 0;
  }

  /**
   * Set single selection
   */
  setSelection(selection) {
    this.selections = [this._normalizeSelection(selection)];
    this.primaryIndex = 0;
  }

  /**
   * Add a new selection (multiple cursors)
   */
  addSelection(selection) {
    const normalized = this._normalizeSelection(selection);
    
    // Check for overlapping selections
    for (let i = 0; i < this.selections.length; i++) {
      if (this._selectionsOverlap(this.selections[i], normalized)) {
        // Merge selections
        this.selections[i] = this._mergeSelections(this.selections[i], normalized);
        return;
      }
    }
    
    this.selections.push(normalized);
    this.primaryIndex = this.selections.length - 1;
    this._sortSelections();
  }

  /**
   * Get primary selection
   */
  getPrimary() {
    return this.selections[this.primaryIndex] || this._emptySelection();
  }

  /**
   * Get all selections
   */
  getAll() {
    return [...this.selections];
  }

  /**
   * Clear all selections except primary
   */
  clearSecondary() {
    if (this.selections.length > 0) {
      this.selections = [this.selections[this.primaryIndex]];
      this.primaryIndex = 0;
    }
  }

  /**
   * Move all cursors
   */
  moveAll(deltaLine, deltaColumn, buffer) {
    this.selections = this.selections.map(sel => {
      const newEndLine = Math.max(1, sel.endLine + deltaLine);
      const newEndColumn = Math.max(1, sel.endColumn + deltaColumn);
      
      return {
        startLine: newEndLine,
        startColumn: newEndColumn,
        endLine: newEndLine,
        endColumn: newEndColumn
      };
    });
  }

  /**
   * Extend all selections
   */
  extendAll(deltaLine, deltaColumn, buffer) {
    this.selections = this.selections.map(sel => ({
      ...sel,
      endLine: Math.max(1, sel.endLine + deltaLine),
      endColumn: Math.max(1, sel.endColumn + deltaColumn)
    }));
  }

  /**
   * Normalize selection (ensure start <= end)
   */
  _normalizeSelection(sel) {
    if (sel.startLine > sel.endLine || 
        (sel.startLine === sel.endLine && sel.startColumn > sel.endColumn)) {
      return {
        startLine: sel.endLine,
        startColumn: sel.endColumn,
        endLine: sel.startLine,
        endColumn: sel.startColumn
      };
    }
    return { ...sel };
  }

  /**
   * Check if selections overlap
   */
  _selectionsOverlap(a, b) {
    const aStart = a.startLine * 10000 + a.startColumn;
    const aEnd = a.endLine * 10000 + a.endColumn;
    const bStart = b.startLine * 10000 + b.startColumn;
    const bEnd = b.endLine * 10000 + b.endColumn;
    
    return !(aEnd < bStart || bEnd < aStart);
  }

  /**
   * Merge two selections
   */
  _mergeSelections(a, b) {
    const aStart = a.startLine * 10000 + a.startColumn;
    const bStart = b.startLine * 10000 + b.startColumn;
    const aEnd = a.endLine * 10000 + a.endColumn;
    const bEnd = b.endLine * 10000 + b.endColumn;
    
    return {
      startLine: aStart < bStart ? a.startLine : b.startLine,
      startColumn: aStart < bStart ? a.startColumn : b.startColumn,
      endLine: aEnd > bEnd ? a.endLine : b.endLine,
      endColumn: aEnd > bEnd ? a.endColumn : b.endColumn
    };
  }

  /**
   * Sort selections by position
   */
  _sortSelections() {
    const primarySel = this.selections[this.primaryIndex];
    this.selections.sort((a, b) => {
      const aPos = a.startLine * 10000 + a.startColumn;
      const bPos = b.startLine * 10000 + b.startColumn;
      return aPos - bPos;
    });
    this.primaryIndex = this.selections.indexOf(primarySel);
  }

  /**
   * Empty selection
   */
  _emptySelection() {
    return { startLine: 1, startColumn: 1, endLine: 1, endColumn: 1 };
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//                                                              // viewport
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Viewport manager for virtualized rendering
 */
class ViewportManager {
  constructor(config = {}) {
    this.lineHeight = config.lineHeight || 20;
    this.containerHeight = config.containerHeight || 400;
    this.overscan = config.overscan || 5;
    this.scrollTop = 0;
  }

  /**
   * Set scroll position
   */
  setScrollTop(scrollTop) {
    this.scrollTop = Math.max(0, scrollTop);
  }

  /**
   * Get visible line range
   */
  getVisibleRange(totalLines) {
    const startLine = Math.max(0, Math.floor(this.scrollTop / this.lineHeight) - this.overscan);
    const visibleCount = Math.ceil(this.containerHeight / this.lineHeight);
    const endLine = Math.min(totalLines, startLine + visibleCount + this.overscan * 2);
    
    return { startLine, endLine };
  }

  /**
   * Ensure line is visible
   */
  scrollToLine(lineNumber) {
    const lineTop = (lineNumber - 1) * this.lineHeight;
    const lineBottom = lineTop + this.lineHeight;
    
    if (lineTop < this.scrollTop) {
      this.scrollTop = lineTop;
    } else if (lineBottom > this.scrollTop + this.containerHeight) {
      this.scrollTop = lineBottom - this.containerHeight;
    }
    
    return this.scrollTop;
  }

  /**
   * Update container height
   */
  setContainerHeight(height) {
    this.containerHeight = height;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//                                                               // editor core
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Main editor instance
 */
class CodeEditor {
  constructor(containerId, config) {
    this.container = document.getElementById(containerId);
    this.config = config;
    
    this.buffer = new TextBuffer(config.initialValue || '');
    this.undoStack = new UndoStack();
    this.selections = new SelectionManager();
    this.viewport = new ViewportManager({
      lineHeight: 20,
      containerHeight: parseInt(config.height) || 400,
      overscan: 5
    });
    
    this.language = config.language || 'plaintext';
    this.readOnly = config.readOnly || false;
    
    this.callbacks = {
      onChange: null,
      onCursorChange: null,
      onSelectionChange: null,
      onFocus: null,
      onBlur: null
    };
    
    this._cachedTokens = null;
    this._cachedTokensVersion = -1;
    
    // Initialize with cursor at start
    this.selections.setSelection({
      startLine: 1,
      startColumn: 1,
      endLine: 1,
      endColumn: 1
    });
  }

  /**
   * Get current text value
   */
  getValue() {
    return this.buffer.getText();
  }

  /**
   * Set text value
   */
  setValue(text) {
    const oldText = this.buffer.getText();
    this.buffer.setText(text);
    
    // Reset cursor
    this.selections.setSelection({
      startLine: 1,
      startColumn: 1,
      endLine: 1,
      endColumn: 1
    });
    
    this._invalidateTokenCache();
    this._notifyChange();
  }

  /**
   * Get cursor position
   */
  getCursorPosition() {
    const sel = this.selections.getPrimary();
    return { line: sel.endLine, column: sel.endColumn };
  }

  /**
   * Set cursor position
   */
  setCursorPosition(line, column) {
    this.selections.setSelection({
      startLine: line,
      startColumn: column,
      endLine: line,
      endColumn: column
    });
    this._notifyCursorChange();
  }

  /**
   * Get primary selection
   */
  getSelection() {
    return this.selections.getPrimary();
  }

  /**
   * Set selection
   */
  setSelection(selection) {
    this.selections.setSelection(selection);
    this._notifySelectionChange();
  }

  /**
   * Get all selections
   */
  getSelections() {
    return this.selections.getAll();
  }

  /**
   * Add selection (for multiple cursors)
   */
  addSelection(selection) {
    this.selections.addSelection(selection);
    this._notifySelectionChange();
  }

  /**
   * Insert text at current cursor(s)
   */
  insertText(text) {
    if (this.readOnly) return;
    
    const selections = this.selections.getAll();
    
    // Insert at each selection (in reverse order to maintain offsets)
    for (let i = selections.length - 1; i >= 0; i--) {
      const sel = selections[i];
      const startOffset = this.buffer.positionToOffset(sel.startLine, sel.startColumn);
      const endOffset = this.buffer.positionToOffset(sel.endLine, sel.endColumn);
      
      // Delete selection if any
      if (startOffset !== endOffset) {
        const deletedText = this.buffer.getText().substring(startOffset, endOffset);
        this.buffer.delete(startOffset, endOffset - startOffset);
        this.undoStack.push({
          type: 'delete',
          offset: startOffset,
          length: endOffset - startOffset,
          deletedText: deletedText
        });
      }
      
      // Insert text
      this.buffer.insert(startOffset, text);
      this.undoStack.push({
        type: 'insert',
        offset: startOffset,
        text: text
      });
    }
    
    this._invalidateTokenCache();
    this._notifyChange();
  }

  /**
   * Delete selected text or character before cursor
   */
  deleteBackward() {
    if (this.readOnly) return;
    
    const selections = this.selections.getAll();
    
    for (let i = selections.length - 1; i >= 0; i--) {
      const sel = selections[i];
      const startOffset = this.buffer.positionToOffset(sel.startLine, sel.startColumn);
      const endOffset = this.buffer.positionToOffset(sel.endLine, sel.endColumn);
      
      if (startOffset !== endOffset) {
        // Delete selection
        const deletedText = this.buffer.getText().substring(startOffset, endOffset);
        this.buffer.delete(startOffset, endOffset - startOffset);
        this.undoStack.push({
          type: 'delete',
          offset: startOffset,
          length: endOffset - startOffset,
          deletedText: deletedText
        });
      } else if (startOffset > 0) {
        // Delete character before cursor
        const deletedText = this.buffer.getText().substring(startOffset - 1, startOffset);
        this.buffer.delete(startOffset - 1, 1);
        this.undoStack.push({
          type: 'delete',
          offset: startOffset - 1,
          length: 1,
          deletedText: deletedText
        });
      }
    }
    
    this._invalidateTokenCache();
    this._notifyChange();
  }

  /**
   * Undo last edit
   */
  undo() {
    const operation = this.undoStack.undo(this.buffer);
    if (!operation) return;
    
    this._applyOperation(operation, true);
    this._invalidateTokenCache();
    this._notifyChange();
  }

  /**
   * Redo last undone edit
   */
  redo() {
    const operation = this.undoStack.redo(this.buffer);
    if (!operation) return;
    
    this._applyOperation(operation, false);
    this._invalidateTokenCache();
    this._notifyChange();
  }

  /**
   * Apply an operation from undo/redo
   */
  _applyOperation(operation, isUndo) {
    switch (operation.type) {
      case 'insert':
        if (isUndo) {
          this.buffer.delete(operation.offset, operation.text.length);
        } else {
          this.buffer.insert(operation.offset, operation.text);
        }
        break;
      case 'delete':
        if (isUndo) {
          this.buffer.insert(operation.offset, operation.deletedText);
        } else {
          this.buffer.delete(operation.offset, operation.length);
        }
        break;
    }
  }

  /**
   * Get tokens for syntax highlighting (cached)
   */
  getTokens() {
    if (this._cachedTokensVersion !== this.buffer.version) {
      this._cachedTokens = tokenize(this.buffer.getText(), this.language);
      this._cachedTokensVersion = this.buffer.version;
    }
    return this._cachedTokens;
  }

  /**
   * Invalidate token cache
   */
  _invalidateTokenCache() {
    this._cachedTokensVersion = -1;
  }

  /**
   * Find text
   */
  find(query, options = {}) {
    const text = this.buffer.getText();
    const flags = options.caseSensitive ? 'g' : 'gi';
    const regex = new RegExp(this._escapeRegex(query), flags);
    const matches = [];
    
    let match = regex.exec(text);
    while (match !== null) {
      const start = this.buffer.offsetToPosition(match.index);
      const end = this.buffer.offsetToPosition(match.index + match[0].length);
      matches.push({
        startLine: start.line,
        startColumn: start.column,
        endLine: end.line,
        endColumn: end.column,
        text: match[0]
      });
      match = regex.exec(text);
    }
    
    return matches;
  }

  /**
   * Replace first occurrence
   */
  replace(searchText, replaceText) {
    const matches = this.find(searchText);
    if (matches.length === 0) return false;
    
    const match = matches[0];
    const startOffset = this.buffer.positionToOffset(match.startLine, match.startColumn);
    const endOffset = this.buffer.positionToOffset(match.endLine, match.endColumn);
    
    this.buffer.replace(startOffset, endOffset - startOffset, replaceText);
    this._invalidateTokenCache();
    this._notifyChange();
    return true;
  }

  /**
   * Replace all occurrences
   */
  replaceAll(searchText, replaceText) {
    const text = this.buffer.getText();
    const regex = new RegExp(this._escapeRegex(searchText), 'gi');
    const newText = text.replace(regex, replaceText);
    
    if (newText !== text) {
      this.buffer.setText(newText);
      this._invalidateTokenCache();
      this._notifyChange();
      return true;
    }
    return false;
  }

  /**
   * Go to line
   */
  goToLine(lineNumber) {
    const lineCount = this.buffer.getLineCount();
    lineNumber = Math.max(1, Math.min(lineNumber, lineCount));
    
    this.setCursorPosition(lineNumber, 1);
    this.viewport.scrollToLine(lineNumber);
  }

  /**
   * Fold all code blocks
   */
  foldAll() {
    // Implementation would track foldable regions
    // For now, this is a placeholder
  }

  /**
   * Unfold all code blocks
   */
  unfoldAll() {
    // Implementation would expand all folded regions
  }

  /**
   * Format document
   */
  format() {
    // Basic formatting - more sophisticated would use language-specific formatters
    const text = this.buffer.getText();
    // For now, just trim trailing whitespace
    const formatted = text.split('\n').map(line => line.trimEnd()).join('\n');
    if (formatted !== text) {
      this.setValue(formatted);
    }
  }

  /**
   * Escape regex special characters
   */
  _escapeRegex(str) {
    return str.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  }

  /**
   * Notify change
   */
  _notifyChange() {
    if (this.callbacks.onChange) {
      this.callbacks.onChange(this.buffer.getText());
    }
  }

  /**
   * Notify cursor change
   */
  _notifyCursorChange() {
    if (this.callbacks.onCursorChange) {
      this.callbacks.onCursorChange(this.getCursorPosition());
    }
  }

  /**
   * Notify selection change
   */
  _notifySelectionChange() {
    if (this.callbacks.onSelectionChange) {
      this.callbacks.onSelectionChange(this.getSelections());
    }
  }

  /**
   * Destroy editor
   */
  destroy() {
    // Cleanup
    this.callbacks = {};
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//                                                                // ffi exports
// ═══════════════════════════════════════════════════════════════════════════════

// Store editor instances
const editorInstances = new Map();

/**
 * Create editor instance
 */
export const createEditorImpl = (containerId, config) => () => {
  const editor = new CodeEditor(containerId, {
    initialValue: '',
    language: config.language,
    readOnly: config.readOnly,
    height: config.height
  });
  
  const handle = { id: containerId, editor };
  editorInstances.set(containerId, editor);
  
  return handle;
};

/**
 * Destroy editor instance
 */
export const destroyEditorImpl = (handle) => () => {
  const editor = editorInstances.get(handle.id);
  if (editor) {
    editor.destroy();
    editorInstances.delete(handle.id);
  }
};

/**
 * Get editor value
 */
export const getValueImpl = (handle) => () => {
  return handle.editor.getValue();
};

/**
 * Set editor value
 */
export const setValueImpl = (handle, value) => () => {
  handle.editor.setValue(value);
};

/**
 * Get cursor position
 */
export const getCursorPositionImpl = (handle) => () => {
  return handle.editor.getCursorPosition();
};

/**
 * Set cursor position
 */
export const setCursorPositionImpl = (handle, pos) => () => {
  handle.editor.setCursorPosition(pos.line, pos.column);
};

/**
 * Get selection
 */
export const getSelectionImpl = (handle) => () => {
  return handle.editor.getSelection();
};

/**
 * Set selection
 */
export const setSelectionImpl = (handle, selection) => () => {
  handle.editor.setSelection(selection);
};

/**
 * Get all selections
 */
export const getSelectionsImpl = (handle) => () => {
  return handle.editor.getSelections();
};

/**
 * Add selection
 */
export const addSelectionImpl = (handle, selection) => () => {
  handle.editor.addSelection(selection);
};

/**
 * Focus editor
 */
export const focusEditorImpl = (handle) => () => {
  if (handle.editor.container) {
    const textarea = handle.editor.container.querySelector('[data-editor-textarea]');
    if (textarea) textarea.focus();
  }
};

/**
 * Blur editor
 */
export const blurEditorImpl = (handle) => () => {
  if (handle.editor.container) {
    const textarea = handle.editor.container.querySelector('[data-editor-textarea]');
    if (textarea) textarea.blur();
  }
};

/**
 * Undo
 */
export const undoImpl = (handle) => () => {
  handle.editor.undo();
};

/**
 * Redo
 */
export const redoImpl = (handle) => () => {
  handle.editor.redo();
};

/**
 * Format document
 */
export const formatImpl = (handle) => () => {
  handle.editor.format();
};

/**
 * Insert text
 */
export const insertTextImpl = (handle, text) => () => {
  handle.editor.insertText(text);
};

/**
 * Find text
 */
export const findImpl = (handle, query) => () => {
  handle.editor.find(query);
};

/**
 * Replace text
 */
export const replaceImpl = (handle, search, replacement) => () => {
  handle.editor.replace(search, replacement);
};

/**
 * Replace all
 */
export const replaceAllImpl = (handle, search, replacement) => () => {
  handle.editor.replaceAll(search, replacement);
};

/**
 * Go to line
 */
export const goToLineImpl = (handle, line) => () => {
  handle.editor.goToLine(line);
};

/**
 * Fold all
 */
export const foldAllImpl = (handle) => () => {
  handle.editor.foldAll();
};

/**
 * Unfold all
 */
export const unfoldAllImpl = (handle) => () => {
  handle.editor.unfoldAll();
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                         // keyboard handling
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Initialize keyboard handling for editor
 */
export const initKeyboardHandler = (handle) => (callbacks) => () => {
  const editor = handle.editor;
  if (!editor.container) return () => {};
  
  const textarea = editor.container.querySelector('[data-editor-textarea]');
  if (!textarea) return () => {};
  
  const handleKeyDown = (e) => {
    const isCtrl = e.ctrlKey || e.metaKey;
    const isShift = e.shiftKey;
    const isAlt = e.altKey;
    
    // Ctrl+Z - Undo
    if (isCtrl && !isShift && e.key === 'z') {
      e.preventDefault();
      editor.undo();
      return;
    }
    
    // Ctrl+Shift+Z or Ctrl+Y - Redo
    if ((isCtrl && isShift && e.key === 'z') || (isCtrl && e.key === 'y')) {
      e.preventDefault();
      editor.redo();
      return;
    }
    
    // Ctrl+F - Find
    if (isCtrl && e.key === 'f') {
      e.preventDefault();
      if (callbacks.onFind) callbacks.onFind()();
      return;
    }
    
    // Ctrl+H - Replace
    if (isCtrl && e.key === 'h') {
      e.preventDefault();
      if (callbacks.onReplace) callbacks.onReplace()();
      return;
    }
    
    // Ctrl+G - Go to line
    if (isCtrl && e.key === 'g') {
      e.preventDefault();
      if (callbacks.onGoToLine) callbacks.onGoToLine()();
      return;
    }
    
    // Ctrl+D - Add cursor at next occurrence
    if (isCtrl && e.key === 'd') {
      e.preventDefault();
      // Get selected text and find next occurrence
      const sel = editor.getSelection();
      if (sel.startLine !== sel.endLine || sel.startColumn !== sel.endColumn) {
        const text = editor.getValue();
        const startOffset = editor.buffer.positionToOffset(sel.startLine, sel.startColumn);
        const endOffset = editor.buffer.positionToOffset(sel.endLine, sel.endColumn);
        const selectedText = text.substring(startOffset, endOffset);
        
        // Find next occurrence
        const searchStart = endOffset;
        const nextIndex = text.indexOf(selectedText, searchStart);
        
        if (nextIndex !== -1) {
          const nextStart = editor.buffer.offsetToPosition(nextIndex);
          const nextEnd = editor.buffer.offsetToPosition(nextIndex + selectedText.length);
          editor.addSelection({
            startLine: nextStart.line,
            startColumn: nextStart.column,
            endLine: nextEnd.line,
            endColumn: nextEnd.column
          });
        }
      }
      return;
    }
    
    // Ctrl+/ - Toggle comment
    if (isCtrl && e.key === '/') {
      e.preventDefault();
      // Implementation depends on language
      return;
    }
    
    // Alt+Up - Move line up
    if (isAlt && !isShift && e.key === 'ArrowUp') {
      e.preventDefault();
      // Implementation for moving line up
      return;
    }
    
    // Alt+Down - Move line down
    if (isAlt && !isShift && e.key === 'ArrowDown') {
      e.preventDefault();
      // Implementation for moving line down
      return;
    }
    
    // Alt+Shift+Up - Copy line up
    if (isAlt && isShift && e.key === 'ArrowUp') {
      e.preventDefault();
      // Implementation for copying line up
      return;
    }
    
    // Alt+Shift+Down - Copy line down
    if (isAlt && isShift && e.key === 'ArrowDown') {
      e.preventDefault();
      // Implementation for copying line down
      return;
    }
    
    // Tab - Indent
    if (e.key === 'Tab' && !isCtrl && !isAlt) {
      e.preventDefault();
      const indent = editor.config.useTabs ? '\t' : ' '.repeat(editor.config.tabSize || 2);
      editor.insertText(indent);
      return;
    }
    
    // Escape - Clear secondary selections
    if (e.key === 'Escape') {
      editor.selections.clearSecondary();
      return;
    }
  };
  
  const handleInput = (e) => {
    const value = textarea.value;
    editor.setValue(value);
  };
  
  textarea.addEventListener('keydown', handleKeyDown);
  textarea.addEventListener('input', handleInput);
  
  return () => {
    textarea.removeEventListener('keydown', handleKeyDown);
    textarea.removeEventListener('input', handleInput);
  };
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                        // bracket matching
// ═══════════════════════════════════════════════════════════════════════════════

const bracketPairs = {
  '(': ')',
  '[': ']',
  '{': '}',
  '<': '>',
  "'": "'",
  '"': '"',
  '`': '`'
};

const closingBrackets = new Set(Object.values(bracketPairs));

/**
 * Find matching bracket
 */
export const findMatchingBracket = (text, offset) => {
  const char = text[offset];
  
  if (bracketPairs[char]) {
    // Opening bracket - search forward
    const closing = bracketPairs[char];
    let depth = 1;
    
    for (let i = offset + 1; i < text.length && depth > 0; i++) {
      if (text[i] === char && char !== closing) depth++;
      if (text[i] === closing) depth--;
      if (depth === 0) return i;
    }
  } else if (closingBrackets.has(char)) {
    // Closing bracket - search backward
    const opening = Object.keys(bracketPairs).find(k => bracketPairs[k] === char);
    if (!opening) return -1;
    
    let depth = 1;
    for (let i = offset - 1; i >= 0 && depth > 0; i--) {
      if (text[i] === char && char !== opening) depth++;
      if (text[i] === opening) depth--;
      if (depth === 0) return i;
    }
  }
  
  return -1;
};

/**
 * Auto-close bracket
 */
export const autoCloseBracket = (char) => {
  return bracketPairs[char] || null;
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                          // diff computation
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Compute diff between two texts (simple line-based diff)
 */
export const computeDiff = (original, modified) => {
  const originalLines = original.split('\n');
  const modifiedLines = modified.split('\n');
  const diff = [];
  
  // Simple diff algorithm (not optimal, but works for display)
  const maxLen = Math.max(originalLines.length, modifiedLines.length);
  
  for (let i = 0; i < maxLen; i++) {
    const origLine = originalLines[i];
    const modLine = modifiedLines[i];
    
    if (origLine === undefined) {
      diff.push({ type: 'added', line: i + 1, content: modLine });
    } else if (modLine === undefined) {
      diff.push({ type: 'removed', line: i + 1, content: origLine });
    } else if (origLine !== modLine) {
      diff.push({ type: 'removed', line: i + 1, content: origLine });
      diff.push({ type: 'added', line: i + 1, content: modLine });
    } else {
      diff.push({ type: 'unchanged', line: i + 1, content: origLine });
    }
  }
  
  return diff;
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                           // syntax themes
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Get CSS styles for syntax theme
 */
export const getSyntaxThemeStyles = (theme) => {
  const themes = {
    light: {
      keyword: '#7c3aed',      // violet
      string: '#059669',       // green
      number: '#0891b2',       // cyan
      comment: '#6b7280',      // gray
      operator: '#1f2937',     // dark gray
      punctuation: '#1f2937',
      identifier: '#111827',
      type: '#2563eb',         // blue
      function: '#d97706',     // amber
      property: '#9333ea',     // purple
      tag: '#dc2626',          // red
      attribute: '#ea580c',    // orange
      text: '#111827',
      background: '#ffffff',
      lineHighlight: '#f3f4f6',
      selection: '#bfdbfe',
      cursor: '#111827',
      lineNumber: '#9ca3af',
      lineNumberActive: '#6b7280'
    },
    dark: {
      keyword: '#c084fc',      // violet
      string: '#34d399',       // green
      number: '#22d3ee',       // cyan
      comment: '#6b7280',      // gray
      operator: '#e5e7eb',
      punctuation: '#e5e7eb',
      identifier: '#f3f4f6',
      type: '#60a5fa',         // blue
      function: '#fbbf24',     // amber
      property: '#a855f7',     // purple
      tag: '#f87171',          // red
      attribute: '#fb923c',    // orange
      text: '#f3f4f6',
      background: '#1f2937',
      lineHighlight: '#374151',
      selection: '#3b82f680',
      cursor: '#f3f4f6',
      lineNumber: '#6b7280',
      lineNumberActive: '#9ca3af'
    }
  };
  
  return themes[theme] || themes.light;
};

/**
 * Generate CSS for editor
 */
export const generateEditorCSS = (theme) => {
  const colors = getSyntaxThemeStyles(theme);
  
  return `
    .code-editor-${theme} {
      background: ${colors.background};
      color: ${colors.text};
    }
    
    .code-editor-${theme} .token-keyword { color: ${colors.keyword}; font-weight: 600; }
    .code-editor-${theme} .token-string { color: ${colors.string}; }
    .code-editor-${theme} .token-number { color: ${colors.number}; }
    .code-editor-${theme} .token-comment { color: ${colors.comment}; font-style: italic; }
    .code-editor-${theme} .token-operator { color: ${colors.operator}; }
    .code-editor-${theme} .token-punctuation { color: ${colors.punctuation}; }
    .code-editor-${theme} .token-identifier { color: ${colors.identifier}; }
    .code-editor-${theme} .token-type { color: ${colors.type}; }
    .code-editor-${theme} .token-function { color: ${colors.function}; }
    .code-editor-${theme} .token-property { color: ${colors.property}; }
    .code-editor-${theme} .token-tag { color: ${colors.tag}; }
    .code-editor-${theme} .token-attribute { color: ${colors.attribute}; }
    
    .code-editor-${theme} [data-gutter] {
      color: ${colors.lineNumber};
      background: ${colors.lineHighlight}20;
    }
    
    .code-editor-${theme} .active-line {
      background: ${colors.lineHighlight};
    }
    
    .code-editor-${theme} ::selection {
      background: ${colors.selection};
    }
  `;
};
