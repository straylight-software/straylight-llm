{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                       // straylight-llm // evring/trace
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--     "When you want to know how things really work, study them when
--      they're coming apart."
--
--                                                              — Neuromancer
--
-- Event trace recording and replay for deterministic testing.
--
-- A 'Trace' captures completion events from a machine run, allowing
-- exact replay without actual I/O. This is the key to testability:
-- record once, replay deterministically forever.
--
-- Usage:
--
-- @
-- -- Record a trace during actual I/O
-- (result, trace) <- runTraced ring machine
--
-- -- Later, replay without I/O
-- let replayResult = replay machine (traceEvents trace)
-- @
--
-- Imported from: libevring/hs/Evring/Trace.hs
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

module Evring.Trace
  ( -- * Trace type
    Trace (Trace, _traceEvents)
  , emptyTrace
    -- * Recording
  , record
  , recordAll
    -- * Accessors
  , traceEvents
  , traceSize
    -- * Serialization (for golden tests)
  , serializeTrace
  , deserializeTrace
  ) where

import Data.Bits (shiftL, shiftR, (.|.))
import Data.ByteString (ByteString)
import Data.Int (Int64)
import Data.Word (Word8, Word32, Word64)
import GHC.Generics (Generic)

import qualified Data.ByteString as BS

import Evring.Event (Event (Event, eventHandle, eventType, eventResult, eventData, eventUserData))
import Evring.Handle (packHandle, unpackHandle)


-- ════════════════════════════════════════════════════════════════════════════
--                                                                   // types
-- ════════════════════════════════════════════════════════════════════════════

-- | A trace: recorded events for replay testing.
--
-- The trace owns copies of all event data, so it can outlive
-- the original buffers used during the actual I/O.
data Trace = Trace
  { _traceEvents :: ![Event]
    -- ^ Events in order of occurrence
  } deriving stock (Eq, Show, Generic)


-- ════════════════════════════════════════════════════════════════════════════
--                                                             // construction
-- ════════════════════════════════════════════════════════════════════════════

-- | Empty trace.
emptyTrace :: Trace
emptyTrace = Trace []


-- ════════════════════════════════════════════════════════════════════════════
--                                                               // recording
-- ════════════════════════════════════════════════════════════════════════════

-- | Record a single event into a trace.
--
-- Note: We copy the event data so the trace owns its data.
record :: Event -> Trace -> Trace
record event (Trace events) = Trace (events ++ [copyEvent event])
  where
    -- Ensure we own the ByteString data
    copyEvent e = e { eventData = BS.copy (eventData e) }

-- | Record multiple events.
recordAll :: [Event] -> Trace -> Trace
recordAll newEvents trace = foldr record trace (reverse newEvents)


-- ════════════════════════════════════════════════════════════════════════════
--                                                               // accessors
-- ════════════════════════════════════════════════════════════════════════════

-- | Get all events from a trace.
traceEvents :: Trace -> [Event]
traceEvents (Trace events) = events

-- | Get the number of events in a trace.
traceSize :: Trace -> Int
traceSize (Trace events) = length events


-- ════════════════════════════════════════════════════════════════════════════
--                                                           // serialization
-- ════════════════════════════════════════════════════════════════════════════

-- | Magic bytes for trace format identification.
traceMagic :: ByteString
traceMagic = BS.pack [0x45, 0x56, 0x54, 0x52]  -- "EVTR"

-- | Trace format version.
traceVersion :: Word8
traceVersion = 1

-- | Serialize a trace to bytes (for golden tests / persistence).
--
-- Format:
--   - 4 bytes: magic "EVTR"
--   - 1 byte: version
--   - 4 bytes: event count (big-endian)
--   - For each event:
--     - 8 bytes: handle
--     - 1 byte: operation type
--     - 8 bytes: result
--     - 8 bytes: user data
--     - 4 bytes: data length
--     - N bytes: event data
serializeTrace :: Trace -> ByteString
serializeTrace (Trace events) = BS.concat
    [ traceMagic
    , BS.singleton traceVersion
    , encodeWord32BE (fromIntegral $ length events)
    , BS.concat (map serializeEvent events)
    ]
  where
    serializeEvent :: Event -> ByteString
    serializeEvent e = BS.concat
        [ encodeWord64BE (packHandle $ eventHandle e)
        , BS.singleton (fromIntegral $ fromEnum $ eventType e)
        , encodeInt64BE (eventResult e)
        , encodeWord64BE (eventUserData e)
        , encodeWord32BE (fromIntegral $ BS.length (eventData e))
        , eventData e
        ]

-- | Deserialize a trace from bytes.
deserializeTrace :: ByteString -> Either String Trace
deserializeTrace bs
    | BS.length bs < 9 = Left "Trace too short"
    | BS.take 4 bs /= traceMagic = Left "Invalid trace magic"
    | BS.index bs 4 /= traceVersion = Left $ "Unsupported trace version: " ++ show (BS.index bs 4)
    | otherwise = do
        let countBytes = BS.take 4 (BS.drop 5 bs)
        eventCount <- decodeWord32BE countBytes
        parseEvents (fromIntegral eventCount) (BS.drop 9 bs)
  where
    parseEvents :: Int -> ByteString -> Either String Trace
    parseEvents 0 _ = Right emptyTrace
    parseEvents n remaining
        | BS.length remaining < 29 = Left "Truncated event"
        | otherwise = do
            let handleBytes = BS.take 8 remaining
                typeBytes = BS.index remaining 8
                resultBytes = BS.take 8 (BS.drop 9 remaining)
                userDataBytes = BS.take 8 (BS.drop 17 remaining)
                dataLenBytes = BS.take 4 (BS.drop 25 remaining)
            
            handle <- decodeWord64BE handleBytes
            result <- decodeInt64BE resultBytes
            userData <- decodeWord64BE userDataBytes
            dataLen <- decodeWord32BE dataLenBytes
            
            let eventDataStart = 29
                eventDataEnd = eventDataStart + fromIntegral dataLen
            
            if BS.length remaining < eventDataEnd
                then Left "Truncated event data"
                else do
                    let evData = BS.take (fromIntegral dataLen) (BS.drop eventDataStart remaining)
                        event = Event
                            { eventHandle = unpackHandle handle
                            , eventType = toEnum (fromIntegral typeBytes)
                            , eventData = evData
                            , eventResult = result
                            , eventUserData = userData
                            }
                        rest = BS.drop eventDataEnd remaining
                    
                    Trace moreEvents <- parseEvents (n - 1) rest
                    Right $ Trace (event : moreEvents)


-- ════════════════════════════════════════════════════════════════════════════
--                                                       // encoding helpers
-- ════════════════════════════════════════════════════════════════════════════

encodeWord32BE :: Word32 -> ByteString
encodeWord32BE w = BS.pack
    [ fromIntegral (w `shiftR` 24)
    , fromIntegral (w `shiftR` 16)
    , fromIntegral (w `shiftR` 8)
    , fromIntegral w
    ]

encodeWord64BE :: Word64 -> ByteString
encodeWord64BE w = BS.pack
    [ fromIntegral (w `shiftR` 56)
    , fromIntegral (w `shiftR` 48)
    , fromIntegral (w `shiftR` 40)
    , fromIntegral (w `shiftR` 32)
    , fromIntegral (w `shiftR` 24)
    , fromIntegral (w `shiftR` 16)
    , fromIntegral (w `shiftR` 8)
    , fromIntegral w
    ]

encodeInt64BE :: Int64 -> ByteString
encodeInt64BE i = encodeWord64BE (fromIntegral i)

decodeWord32BE :: ByteString -> Either String Word32
decodeWord32BE bs
    | BS.length bs < 4 = Left "Not enough bytes for Word32"
    | otherwise = Right $
        (fromIntegral (BS.index bs 0) `shiftL` 24) .|.
        (fromIntegral (BS.index bs 1) `shiftL` 16) .|.
        (fromIntegral (BS.index bs 2) `shiftL` 8) .|.
        fromIntegral (BS.index bs 3)

decodeWord64BE :: ByteString -> Either String Word64
decodeWord64BE bs
    | BS.length bs < 8 = Left "Not enough bytes for Word64"
    | otherwise = Right $
        (fromIntegral (BS.index bs 0) `shiftL` 56) .|.
        (fromIntegral (BS.index bs 1) `shiftL` 48) .|.
        (fromIntegral (BS.index bs 2) `shiftL` 40) .|.
        (fromIntegral (BS.index bs 3) `shiftL` 32) .|.
        (fromIntegral (BS.index bs 4) `shiftL` 24) .|.
        (fromIntegral (BS.index bs 5) `shiftL` 16) .|.
        (fromIntegral (BS.index bs 6) `shiftL` 8) .|.
        fromIntegral (BS.index bs 7)

decodeInt64BE :: ByteString -> Either String Int64
decodeInt64BE bs = do
    w <- decodeWord64BE bs
    Right (fromIntegral w)
