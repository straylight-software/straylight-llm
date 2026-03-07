{-# LANGUAGE OverloadedStrings #-}

-- | High-level tokenizer interface
--
-- Provides safe Haskell wrappers around the tokenizers-cpp FFI bindings.
-- Supports loading tokenizers from HuggingFace JSON format or SentencePiece models.
--
-- == Usage
--
-- @
-- -- Load a tokenizer from JSON
-- tok <- loadTokenizerJSON "path/to/tokenizer.json"
--
-- -- Encode text to token IDs
-- let ids = encode tok "Hello, world!"
--
-- -- Decode token IDs back to text
-- let text = decode tok ids
-- @
--
-- == Thread Safety
--
-- 'HFTokenizer' is thread-safe for concurrent read operations (encode/decode).
-- Multiple threads can safely call encode/decode on the same tokenizer.
module Slide.Tokenizer
  ( -- * Tokenizer type
    HFTokenizer
  
    -- * Loading tokenizers
  , loadTokenizerJSON
  , loadTokenizerSentencePiece
  , loadTokenizerFromBlob
  , TokenizerFormat(..)
  
    -- * Encoding
  , encode
  , encodeBS
  
    -- * Decoding
  , decode
  , decodeToken
  
    -- * Metadata
  , vocabSize
  , tokenToId
  
    -- * Conversion to Model tokenizer
  , toModelTokenizer
  ) where

import Control.Exception (throwIO)
import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Unsafe as BSU
import Data.Text (Text)
import qualified Data.Text.Encoding as TE
import Data.Word (Word32)
import Foreign.C.Types
import Foreign.ForeignPtr
import Foreign.Marshal.Alloc
import Foreign.Marshal.Array
import Foreign.Ptr
import Foreign.Storable

import Slide.Tokenizer.FFI
import qualified Slide.Model as Model

-- ════════════════════════════════════════════════════════════════════════════════
-- Types
-- ════════════════════════════════════════════════════════════════════════════════

-- | High-level tokenizer wrapper with automatic memory management
--
-- Uses 'ForeignPtr' to ensure the underlying C++ tokenizer is properly freed.
newtype HFTokenizer = HFTokenizer (ForeignPtr ())

-- | Tokenizer file format
data TokenizerFormat
  = FormatJSON           -- ^ HuggingFace tokenizer.json
  | FormatSentencePiece  -- ^ SentencePiece .model file
  deriving stock (Show, Eq)

-- ════════════════════════════════════════════════════════════════════════════════
-- Loading
-- ════════════════════════════════════════════════════════════════════════════════

-- | Load tokenizer from HuggingFace JSON file
loadTokenizerJSON :: FilePath -> IO HFTokenizer
loadTokenizerJSON path = do
  blob <- BS.readFile path
  loadTokenizerFromBlob FormatJSON blob

-- | Load tokenizer from SentencePiece model file
loadTokenizerSentencePiece :: FilePath -> IO HFTokenizer
loadTokenizerSentencePiece path = do
  blob <- BS.readFile path
  loadTokenizerFromBlob FormatSentencePiece blob

-- | Load tokenizer from in-memory blob
loadTokenizerFromBlob :: TokenizerFormat -> ByteString -> IO HFTokenizer
loadTokenizerFromBlob format blob = do
  ptr <- BSU.unsafeUseAsCStringLen blob $ \(dataPtr, dataLen) -> do
    let len = fromIntegral dataLen
    case format of
      FormatJSON          -> c_tokenizer_from_json dataPtr len
      FormatSentencePiece -> c_tokenizer_from_sentencepiece dataPtr len
  
  if ptr == nullPtr
    then throwIO $ userError "Failed to load tokenizer"
    else do
      foreignPtr <- newForeignPtr finalizerPtr ptr
      pure $ HFTokenizer foreignPtr
  where
    finalizerPtr = castFunPtr c_tokenizer_free_ptr

-- | Get function pointer for finalizer
foreign import ccall "&tokenizer_free" c_tokenizer_free_ptr :: FunPtr (Ptr () -> IO ())

-- ════════════════════════════════════════════════════════════════════════════════
-- Encoding
-- ════════════════════════════════════════════════════════════════════════════════

-- | Encode text to token IDs
encode :: HFTokenizer -> Text -> IO [Word32]
encode tok text = encodeBS tok (TE.encodeUtf8 text)

-- | Encode UTF-8 bytes to token IDs
encodeBS :: HFTokenizer -> ByteString -> IO [Word32]
encodeBS (HFTokenizer fptr) textBytes = 
  withForeignPtr fptr $ \ptr ->
    BSU.unsafeUseAsCStringLen textBytes $ \(textPtr, textLen) ->
      alloca $ \outIdsPtr ->
        alloca $ \outLenPtr -> do
          result <- c_tokenizer_encode_alloc ptr textPtr (fromIntegral textLen) outIdsPtr outLenPtr
          if result /= 0
            then throwIO $ userError "Tokenizer encode failed"
            else do
              idsPtr <- peek outIdsPtr
              len <- peek outLenPtr
              ids <- peekArray (fromIntegral len) idsPtr
              c_tokenizer_free_ids idsPtr
              pure $ map (fromIntegral . (\(CInt x) -> x)) ids

-- ════════════════════════════════════════════════════════════════════════════════
-- Decoding
-- ════════════════════════════════════════════════════════════════════════════════

-- | Decode token IDs to text
decode :: HFTokenizer -> [Word32] -> IO Text
decode (HFTokenizer fptr) ids =
  withForeignPtr fptr $ \ptr ->
    withArrayLen (map (CInt . fromIntegral) ids) $ \len idsPtr ->
      alloca $ \outTextPtr ->
        alloca $ \outLenPtr -> do
          result <- c_tokenizer_decode_alloc ptr idsPtr (fromIntegral len) outTextPtr outLenPtr
          if result /= 0
            then throwIO $ userError "Tokenizer decode failed"
            else do
              textPtr <- peek outTextPtr
              textLen <- peek outLenPtr
              text <- BS.packCStringLen (textPtr, fromIntegral textLen)
              c_tokenizer_free_text textPtr
              pure $ TE.decodeUtf8 text

-- | Decode single token ID to its string representation
decodeToken :: HFTokenizer -> Word32 -> IO (Maybe ByteString)
decodeToken (HFTokenizer fptr) tokenId =
  withForeignPtr fptr $ \ptr ->
    allocaBytes 256 $ \bufPtr -> do
      result <- c_tokenizer_id_to_token ptr (CInt $ fromIntegral tokenId) bufPtr 256
      if result < 0
        then pure Nothing
        else do
          bytes <- BS.packCStringLen (bufPtr, fromIntegral result)
          pure $ Just bytes

-- ════════════════════════════════════════════════════════════════════════════════
-- Metadata
-- ════════════════════════════════════════════════════════════════════════════════

-- | Get vocabulary size
vocabSize :: HFTokenizer -> IO Int
vocabSize (HFTokenizer fptr) =
  withForeignPtr fptr $ \ptr -> do
    size <- c_tokenizer_vocab_size ptr
    pure $ fromIntegral size

-- | Convert token string to ID
tokenToId :: HFTokenizer -> Text -> IO (Maybe Word32)
tokenToId (HFTokenizer fptr) token =
  withForeignPtr fptr $ \ptr ->
    BSU.unsafeUseAsCStringLen (TE.encodeUtf8 token) $ \(tokenPtr, tokenLen) -> do
      result <- c_tokenizer_token_to_id ptr tokenPtr (fromIntegral tokenLen)
      if result < 0
        then pure Nothing
        else pure $ Just (fromIntegral result)

-- ════════════════════════════════════════════════════════════════════════════════
-- Model Integration
-- ════════════════════════════════════════════════════════════════════════════════

-- | Convert HFTokenizer to Model.Tokenizer interface
--
-- This allows using a loaded HFTokenizer with the Model abstraction.
-- The HFTokenizer is captured in the closures, keeping it alive as long
-- as the Model.Tokenizer is reachable.
toModelTokenizer :: HFTokenizer -> ByteString -> IO Model.Tokenizer
toModelTokenizer tok hash = do
  size <- vocabSize tok
  pure Model.Tokenizer
    { Model.tokenizerEncode    = encode tok
    , Model.tokenizerDecode    = decode tok
    , Model.tokenizerDecodeOne = decodeToken tok
    , Model.tokenizerVocabSize = size
    , Model.tokenizerConfig = Model.TokenizerConfig
        { Model.tokenizerModelId = "huggingface"
        , Model.tokenizerHash = hash
        }
    }
