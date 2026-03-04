{-# LANGUAGE OverloadedStrings #-}

{- | Hot token lookup table for SIGIL wire format

Maps token IDs to 1-byte indices for the top 127 most frequent tokens.
Everything else maps to 0xFF (not hot). This provides ~50-100x compression
for the most common tokens in LLM output.
-}
module Slide.HotTable (
    -- * Types
    HotTable,

    -- * Loading
    loadHotTable,
    defaultHotTable,

    -- * Lookup
    lookupHot,
    isHot,
    hotTableHash,

    -- * Building
    buildHotTable,
    boundarySet,
) where

import Control.Monad (forM_, when)
import Crypto.Hash (Blake2b_256, Digest, hash)
import Data.Bits (shiftL, shiftR, (.|.))
import Data.ByteArray (convert)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Vector.Unboxed qualified as VU
import Data.Vector.Unboxed.Mutable qualified as VUM
import Data.Word (Word32, Word8)
import System.IO.Unsafe (unsafePerformIO)

import Slide.Wire.Types (HotId, TokenId, maxHotId)

-- ════════════════════════════════════════════════════════════════════════════════
-- Types
-- ════════════════════════════════════════════════════════════════════════════════

{- | Hot token lookup table

Provides O(1) lookup from token ID to hot encoding.
Content-addressed via BLAKE2b-256 hash for verification.
-}
data HotTable = HotTable
    { hotTableLookup :: !(VU.Vector Word8)
    -- ^ token_id -> hot_index (0xFF if cold)
    , hotTableReverse :: !(VU.Vector Word32)
    -- ^ hot_index -> token_id
    , hotTableDigest :: !ByteString
    -- ^ BLAKE2b-256 hash for content addressing
    }
    deriving stock (Show)

-- ════════════════════════════════════════════════════════════════════════════════
-- Loading
-- ════════════════════════════════════════════════════════════════════════════════

{- | Load hot table from file

File format:
  - 4 bytes: vocab size (little-endian u32)
  - 127 * 4 bytes: token IDs of hot tokens in order
  - 32 bytes: BLAKE2b-256 hash of the above
-}
loadHotTable :: FilePath -> IO HotTable
loadHotTable filePath = do
    fileContents <- BS.readFile filePath

    let vocabularySize = fromIntegral $ decodeLE32 (BS.take 4 fileContents)
        hotTokenIds = parseHotTokenIds (BS.drop 4 fileContents)
        storedHash = BS.take 32 (BS.drop (4 + 127 * 4) fileContents)

    -- Verify content-addressed hash
    let computedHash = computeBlake2b256 (BS.take (4 + 127 * 4) fileContents)
    if computedHash /= storedHash
        then error "[slide] [hottable] [error] Hash verification failed"
        else buildHotTable vocabularySize hotTokenIds

{- | Default hot table: first 127 tokens are hot

This is a crude approximation. Real hot tables should be profiled
from actual traffic for your model.
-}
defaultHotTable :: HotTable
defaultHotTable = unsafePerformIO $ buildHotTable 150_000 [0 .. 126]
{-# NOINLINE defaultHotTable #-}

-- ════════════════════════════════════════════════════════════════════════════════
-- Lookup
-- ════════════════════════════════════════════════════════════════════════════════

-- | O(1) lookup: is this token hot? If so, what's its 1-byte encoding?
lookupHot :: HotTable -> TokenId -> Maybe HotId
lookupHot table tokenId
    | tokenId >= fromIntegral (VU.length (hotTableLookup table)) = Nothing
    | otherwise =
        let hotIndex = hotTableLookup table VU.! fromIntegral tokenId
         in if hotIndex == 0xFF then Nothing else Just hotIndex
{-# INLINE lookupHot #-}

-- | O(1) check if token is hot
isHot :: HotTable -> TokenId -> Bool
isHot table tokenId =
    tokenId < fromIntegral (VU.length (hotTableLookup table))
        && hotTableLookup table VU.! fromIntegral tokenId /= 0xFF
{-# INLINE isHot #-}

-- | Content-addressed hash of this table
hotTableHash :: HotTable -> ByteString
hotTableHash = hotTableDigest

-- ════════════════════════════════════════════════════════════════════════════════
-- Building
-- ════════════════════════════════════════════════════════════════════════════════

-- | Build hot table from vocab size and hot token list
buildHotTable :: Int -> [Word32] -> IO HotTable
buildHotTable vocabularySize hotTokenIds = do
    -- Build forward lookup vector (token_id -> hot_index)
    lookupVector <- VUM.replicate vocabularySize 0xFF
    forM_ (zip [0 .. maxHotId] hotTokenIds) $ \(hotIndex, tokenId) ->
        when (fromIntegral tokenId < vocabularySize) $
            VUM.write lookupVector (fromIntegral tokenId) hotIndex

    frozenLookup <- VU.unsafeFreeze lookupVector

    -- Build reverse lookup (hot_index -> token_id)
    let reverseVector = VU.fromList (take 127 $ hotTokenIds ++ repeat 0)

    -- Compute content-addressed hash
    let hashInput = BS.pack $ concatMap encodeLE32Bytes (fromIntegral vocabularySize : hotTokenIds)
        tableDigest = computeBlake2b256 hashInput

    pure
        HotTable
            { hotTableLookup = frozenLookup
            , hotTableReverse = reverseVector
            , hotTableDigest = tableDigest
            }

{- | Build boundary token set from a list of boundary characters

Returns a vector where vec[tokId] = True if tokId is a boundary token.
Used for semantic chunking at statement/line boundaries.
-}
boundarySet :: Int -> (Char -> [TokenId]) -> [Char] -> VU.Vector Bool
boundarySet vocabularySize tokenizeChar boundaryChars = VU.create $ do
    boundaryVector <- VUM.replicate vocabularySize False
    forM_ boundaryChars $ \character ->
        forM_ (tokenizeChar character) $ \tokenId ->
            when (fromIntegral tokenId < vocabularySize) $
                VUM.write boundaryVector (fromIntegral tokenId) True
    pure boundaryVector

-- ════════════════════════════════════════════════════════════════════════════════
-- Binary Helpers
-- ════════════════════════════════════════════════════════════════════════════════

decodeLE32 :: ByteString -> Word32
decodeLE32 bytes
    | BS.length bytes < 4 = 0
    | otherwise =
        fromIntegral (BS.index bytes 0)
            .|. (fromIntegral (BS.index bytes 1) `shiftL` 8)
            .|. (fromIntegral (BS.index bytes 2) `shiftL` 16)
            .|. (fromIntegral (BS.index bytes 3) `shiftL` 24)

encodeLE32Bytes :: Word32 -> [Word8]
encodeLE32Bytes value =
    [ fromIntegral value
    , fromIntegral (value `shiftR` 8)
    , fromIntegral (value `shiftR` 16)
    , fromIntegral (value `shiftR` 24)
    ]

parseHotTokenIds :: ByteString -> [Word32]
parseHotTokenIds bytes =
    [ decodeLE32 (BS.take 4 (BS.drop (index * 4) bytes))
    | index <- [0 .. 126]
    ]

computeBlake2b256 :: ByteString -> ByteString
computeBlake2b256 bytes = convert (hash bytes :: Digest Blake2b_256)
