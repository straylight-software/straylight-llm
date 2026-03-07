{-# LANGUAGE ForeignFunctionInterface #-}
{-# LANGUAGE CApiFFI #-}

-- | FFI bindings to tokenizers-cpp
--
-- Low-level bindings to the C wrapper around tokenizers-cpp library.
-- For high-level usage, see 'Slide.Tokenizer'.
module Slide.Tokenizer.FFI
  ( -- * Tokenizer handle
    TokenizerPtr
  , nullTokenizerPtr
  
    -- * Construction / Destruction
  , c_tokenizer_from_json
  , c_tokenizer_from_sentencepiece
  , c_tokenizer_free
  
    -- * Encoding
  , c_tokenizer_encode
  , c_tokenizer_encode_alloc
  , c_tokenizer_free_ids
  
    -- * Decoding
  , c_tokenizer_decode
  , c_tokenizer_decode_alloc
  , c_tokenizer_free_text
  , c_tokenizer_id_to_token
  
    -- * Metadata
  , c_tokenizer_vocab_size
  , c_tokenizer_token_to_id
  ) where

import Foreign.C.Types
import Foreign.C.String
import Foreign.Ptr

-- | Opaque pointer to tokenizer handle
type TokenizerPtr = Ptr ()

-- | Null tokenizer pointer
nullTokenizerPtr :: TokenizerPtr
nullTokenizerPtr = nullPtr

-- ════════════════════════════════════════════════════════════════════════════════
-- Construction / Destruction
-- ════════════════════════════════════════════════════════════════════════════════

-- | Create tokenizer from HuggingFace JSON blob
foreign import capi unsafe "tokenizers_c.h tokenizer_from_json"
  c_tokenizer_from_json
    :: CString      -- ^ JSON data
    -> CSize        -- ^ JSON length
    -> IO TokenizerPtr

-- | Create tokenizer from SentencePiece model blob
foreign import capi unsafe "tokenizers_c.h tokenizer_from_sentencepiece"
  c_tokenizer_from_sentencepiece
    :: CString      -- ^ Model data
    -> CSize        -- ^ Model length
    -> IO TokenizerPtr

-- | Free tokenizer
foreign import capi unsafe "tokenizers_c.h tokenizer_free"
  c_tokenizer_free :: TokenizerPtr -> IO ()

-- ════════════════════════════════════════════════════════════════════════════════
-- Encoding
-- ════════════════════════════════════════════════════════════════════════════════

-- | Encode text to token IDs (caller-allocated buffer)
foreign import capi unsafe "tokenizers_c.h tokenizer_encode"
  c_tokenizer_encode
    :: TokenizerPtr -- ^ Tokenizer handle
    -> CString      -- ^ Text to encode
    -> CSize        -- ^ Text length
    -> Ptr CInt     -- ^ Output buffer
    -> CSize        -- ^ Buffer capacity
    -> IO CInt      -- ^ Number of tokens, or -1 on error

-- | Encode text to token IDs (allocated buffer)
foreign import capi unsafe "tokenizers_c.h tokenizer_encode_alloc"
  c_tokenizer_encode_alloc
    :: TokenizerPtr     -- ^ Tokenizer handle
    -> CString          -- ^ Text to encode
    -> CSize            -- ^ Text length
    -> Ptr (Ptr CInt)   -- ^ Output buffer pointer
    -> Ptr CSize        -- ^ Output length
    -> IO CInt          -- ^ 0 on success, -1 on error

-- | Free token ID buffer
foreign import capi unsafe "tokenizers_c.h tokenizer_free_ids"
  c_tokenizer_free_ids :: Ptr CInt -> IO ()

-- ════════════════════════════════════════════════════════════════════════════════
-- Decoding
-- ════════════════════════════════════════════════════════════════════════════════

-- | Decode token IDs to text (caller-allocated buffer)
foreign import capi unsafe "tokenizers_c.h tokenizer_decode"
  c_tokenizer_decode
    :: TokenizerPtr -- ^ Tokenizer handle
    -> Ptr CInt     -- ^ Token IDs
    -> CSize        -- ^ Number of tokens
    -> CString      -- ^ Output buffer
    -> CSize        -- ^ Buffer capacity
    -> IO CInt      -- ^ Bytes written, or -1 on error

-- | Decode token IDs to text (allocated buffer)
foreign import capi unsafe "tokenizers_c.h tokenizer_decode_alloc"
  c_tokenizer_decode_alloc
    :: TokenizerPtr     -- ^ Tokenizer handle
    -> Ptr CInt         -- ^ Token IDs
    -> CSize            -- ^ Number of tokens
    -> Ptr CString      -- ^ Output buffer pointer
    -> Ptr CSize        -- ^ Output length
    -> IO CInt          -- ^ 0 on success, -1 on error

-- | Free text buffer
foreign import capi unsafe "tokenizers_c.h tokenizer_free_text"
  c_tokenizer_free_text :: CString -> IO ()

-- | Decode single token ID to text
foreign import capi unsafe "tokenizers_c.h tokenizer_id_to_token"
  c_tokenizer_id_to_token
    :: TokenizerPtr -- ^ Tokenizer handle
    -> CInt         -- ^ Token ID
    -> CString      -- ^ Output buffer
    -> CSize        -- ^ Buffer capacity
    -> IO CInt      -- ^ Bytes written, or -1 on error

-- ════════════════════════════════════════════════════════════════════════════════
-- Metadata
-- ════════════════════════════════════════════════════════════════════════════════

-- | Get vocabulary size
foreign import capi unsafe "tokenizers_c.h tokenizer_vocab_size"
  c_tokenizer_vocab_size :: TokenizerPtr -> IO CSize

-- | Convert token string to ID
foreign import capi unsafe "tokenizers_c.h tokenizer_token_to_id"
  c_tokenizer_token_to_id
    :: TokenizerPtr -- ^ Tokenizer handle
    -> CString      -- ^ Token string
    -> CSize        -- ^ Token length
    -> IO CInt      -- ^ Token ID, or -1 if not found
