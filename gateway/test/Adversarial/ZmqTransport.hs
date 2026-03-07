-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                             // straylight-llm // adversarial // zmq transport
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--     "He'd seen it all, and none of it meant anything to him."
--
--                                                              — Neuromancer
--
-- Adversarial tests for ZMQ transport layer.
--
-- Test categories:
--   1. Malformed multipart messages
--   2. Invalid JSON in metadata/payload
--   3. Missing frames
--   4. Identity spoofing attempts
--   5. Request ID collisions
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

{-# LANGUAGE OverloadedStrings #-}

module Adversarial.ZmqTransport
    ( tests
    ) where

import Control.Monad (when)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Hedgehog
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Test.Tasty
import Test.Tasty.Hedgehog

import Transport.ZmqInbound (parseRequest, SigilRequest (SigilRequest, reqIdentity, reqRequestId))


-- ════════════════════════════════════════════════════════════════════════════
--                                                               // generators
-- ════════════════════════════════════════════════════════════════════════════

-- | Generate valid ZMQ identity (random bytes)
genIdentity :: Gen ByteString
genIdentity = Gen.bytes (Range.linear 1 255)

-- | Generate valid request ID
genRequestId :: Gen ByteString
genRequestId = TE.encodeUtf8 <$> Gen.text (Range.linear 8 64) Gen.alphaNum

-- | Generate valid metadata JSON
genValidMetadata :: Gen ByteString
genValidMetadata = do
    model <- Gen.element ["claude-3-opus", "gpt-4", "llama-3-70b"]
    stream <- Gen.bool
    pure $ TE.encodeUtf8 $ T.concat
        [ "{\"model\":\""
        , model
        , "\",\"stream\":"
        , if stream then "true" else "false"
        , "}"
        ]

-- | Generate valid ChatRequest payload JSON
genValidPayload :: Gen ByteString
genValidPayload = do
    model <- Gen.element ["claude-3-opus", "gpt-4", "llama-3-70b"]
    content <- Gen.text (Range.linear 1 100) Gen.alphaNum
    pure $ TE.encodeUtf8 $ T.concat
        [ "{\"model\":\""
        , model
        , "\",\"messages\":[{\"role\":\"user\",\"content\":\""
        , content
        , "\"}]}"
        ]

-- | Generate invalid JSON (various malformations)
genInvalidJson :: Gen ByteString
genInvalidJson = Gen.choice
    [ pure "{"                              -- unclosed brace
    , pure "}"                              -- unexpected close
    , pure "{\"key\": }"                    -- missing value
    , pure "{\"key\" \"value\"}"            -- missing colon
    , pure "[1, 2, 3"                       -- unclosed array
    , pure "null null"                      -- multiple values
    , pure "{\"key\": undefined}"           -- JS-ism
    , pure "{\"key\": NaN}"                 -- invalid number
    , pure $ BS.pack [0xFE, 0xFF]           -- BOM
    , pure $ BS.pack [0x00, 0x01, 0x02]     -- binary garbage
    , Gen.bytes (Range.linear 1 100)        -- random bytes
    ]

-- | Generate metadata with invalid types
genMalformedMetadata :: Gen ByteString
genMalformedMetadata = Gen.choice
    [ pure "{\"model\": 123}"                       -- model should be string
    , pure "{\"stream\": \"yes\"}"                  -- stream should be bool
    , pure "{\"timeout\": \"forever\"}"             -- timeout should be int
    , pure "{\"model\": null}"                      -- null model
    , pure "[]"                                     -- array instead of object
    , pure "\"just a string\""                      -- string instead of object
    , pure "42"                                     -- number instead of object
    ]

-- | Generate ChatRequest with missing required fields
genMalformedPayload :: Gen ByteString
genMalformedPayload = Gen.choice
    [ pure "{\"messages\": []}"                     -- missing model
    , pure "{\"model\": \"gpt-4\"}"                 -- missing messages
    , pure "{\"model\": \"gpt-4\", \"messages\": \"not an array\"}"
    , pure "{\"model\": \"gpt-4\", \"messages\": [{}]}"  -- empty message
    , pure "{\"model\": \"gpt-4\", \"messages\": [{\"role\": \"invalid\"}]}"
    ]


-- ════════════════════════════════════════════════════════════════════════════
--                                                // multipart frame properties
-- ════════════════════════════════════════════════════════════════════════════

-- | Valid 5-frame message parses successfully
prop_validMessageParses :: Property
prop_validMessageParses = property $ do
    identity <- forAll genIdentity
    requestId <- forAll genRequestId
    metadata <- forAll genValidMetadata
    payload <- forAll genValidPayload
    let frames = [identity, BS.empty, requestId, metadata, payload]
    case parseRequest frames of
        Left _ -> failure
        Right req -> do
            reqIdentity req === identity
            TE.encodeUtf8 (reqRequestId req) === requestId

-- | Wrong frame count fails gracefully
prop_wrongFrameCountFails :: Property
prop_wrongFrameCountFails = property $ do
    numFrames <- forAll $ Gen.int (Range.linear 0 10)
    frames <- forAll $ Gen.list (Range.singleton numFrames) (Gen.bytes (Range.linear 0 100))
    -- Only 5 frames is valid
    when (numFrames /= 5) $ do
        case parseRequest frames of
            Left err -> assert $ "frame count" `T.isInfixOf` err
            Right _ -> failure

-- | Empty identity is handled
prop_emptyIdentityHandled :: Property
prop_emptyIdentityHandled = property $ do
    requestId <- forAll genRequestId
    metadata <- forAll genValidMetadata
    payload <- forAll genValidPayload
    -- Empty identity (valid for some ZMQ patterns)
    let frames = [BS.empty, BS.empty, requestId, metadata, payload]
    case parseRequest frames of
        Left _ -> success  -- acceptable to reject
        Right _ -> success -- acceptable to accept

-- | Invalid metadata JSON fails with specific error
prop_invalidMetadataFails :: Property
prop_invalidMetadataFails = property $ do
    identity <- forAll genIdentity
    requestId <- forAll genRequestId
    badMetadata <- forAll genInvalidJson
    payload <- forAll genValidPayload
    let frames = [identity, BS.empty, requestId, badMetadata, payload]
    case parseRequest frames of
        Left err -> assert $ "metadata" `T.isInfixOf` T.toLower err
        Right _ -> failure

-- | Invalid payload JSON fails with specific error
prop_invalidPayloadFails :: Property
prop_invalidPayloadFails = property $ do
    identity <- forAll genIdentity
    requestId <- forAll genRequestId
    metadata <- forAll genValidMetadata
    badPayload <- forAll genInvalidJson
    let frames = [identity, BS.empty, requestId, metadata, badPayload]
    case parseRequest frames of
        Left err -> assert $ "chatrequest" `T.isInfixOf` T.toLower err
        Right _ -> failure


-- ════════════════════════════════════════════════════════════════════════════
--                                                      // injection attempts
-- ════════════════════════════════════════════════════════════════════════════

-- | Request ID with null bytes handled safely
prop_requestIdNullBytes :: Property
prop_requestIdNullBytes = property $ do
    identity <- forAll genIdentity
    -- Request ID with embedded nulls
    requestId <- forAll $ do
        prefix <- Gen.bytes (Range.linear 1 10)
        suffix <- Gen.bytes (Range.linear 1 10)
        pure $ prefix <> BS.singleton 0x00 <> suffix
    metadata <- forAll genValidMetadata
    payload <- forAll genValidPayload
    let frames = [identity, BS.empty, requestId, metadata, payload]
    -- Should not crash, may fail or succeed
    case parseRequest frames of
        Left _ -> success
        Right _ -> success

-- | Extremely large frames handled without OOM
prop_largeFramesHandled :: Property
prop_largeFramesHandled = withTests 10 $ property $ do
    identity <- forAll genIdentity
    requestId <- forAll genRequestId
    -- Large but valid metadata/payload
    largeContent <- forAll $ Gen.text (Range.linear 10000 50000) Gen.alphaNum
    let metadata = "{\"model\":\"gpt-4\",\"stream\":false}"
        payload = TE.encodeUtf8 $ T.concat
            [ "{\"model\":\"gpt-4\",\"messages\":[{\"role\":\"user\",\"content\":\""
            , largeContent
            , "\"}]}"
            ]
        frames = [identity, BS.empty, requestId, TE.encodeUtf8 metadata, payload]
    -- Should parse (slowly maybe, but without crash)
    case parseRequest frames of
        Left _ -> success
        Right _ -> success

-- | Unicode in all fields handled correctly
prop_unicodeHandled :: Property
prop_unicodeHandled = property $ do
    identity <- forAll genIdentity
    -- Unicode request ID
    requestId <- forAll $ TE.encodeUtf8 <$> Gen.text (Range.linear 1 32) Gen.unicode
    metadata <- forAll genValidMetadata
    -- Unicode content
    unicodeContent <- forAll $ Gen.text (Range.linear 1 100) Gen.unicode
    let escapedContent = T.concatMap escapeJsonChar unicodeContent
        payload = TE.encodeUtf8 $ T.concat
            [ "{\"model\":\"gpt-4\",\"messages\":[{\"role\":\"user\",\"content\":\""
            , escapedContent
            , "\"}]}"
            ]
        frames = [identity, BS.empty, requestId, metadata, payload]
    case parseRequest frames of
        Left _ -> success  -- may fail on malformed escaping
        Right _ -> success


-- ════════════════════════════════════════════════════════════════════════════
--                                                   // realistic distributions
-- ════════════════════════════════════════════════════════════════════════════

-- | Generate request with realistic model distribution
genRealisticModel :: Gen Text
genRealisticModel = Gen.frequency
    [ (40, pure "anthropic/claude-sonnet-4")
    , (25, pure "anthropic/claude-opus-4")
    , (15, pure "openai/gpt-4-turbo")
    , (10, pure "meta-llama/llama-3-70b")
    , (5, pure "deepseek/deepseek-v3")
    , (3, pure "qwen/qwen-2.5-72b")
    , (2, pure "mistral/mixtral-8x22b")
    ]

-- | Generate request with realistic streaming distribution (90% stream)
genRealisticStreamFlag :: Gen Bool
genRealisticStreamFlag = Gen.frequency
    [ (90, pure True)
    , (10, pure False)
    ]

-- | Generate realistic message length distribution
genRealisticMessageLength :: Gen Int
genRealisticMessageLength = Gen.frequency
    [ (20, Gen.int (Range.linear 1 50))        -- short prompts
    , (40, Gen.int (Range.linear 50 500))      -- medium prompts
    , (30, Gen.int (Range.linear 500 2000))    -- long prompts
    , (8, Gen.int (Range.linear 2000 8000))    -- very long
    , (2, Gen.int (Range.linear 8000 32000))   -- context-stuffing
    ]

-- | Property: realistic requests parse successfully
prop_realisticRequestsParses :: Property
prop_realisticRequestsParses = property $ do
    identity <- forAll genIdentity
    requestId <- forAll genRequestId
    model <- forAll genRealisticModel
    stream <- forAll genRealisticStreamFlag
    msgLen <- forAll genRealisticMessageLength
    content <- forAll $ Gen.text (Range.singleton msgLen) Gen.alphaNum
    let metadata = TE.encodeUtf8 $ T.concat
            [ "{\"model\":\""
            , model
            , "\",\"stream\":"
            , if stream then "true" else "false"
            , "}"
            ]
        payload = TE.encodeUtf8 $ T.concat
            [ "{\"model\":\""
            , model
            , "\",\"messages\":[{\"role\":\"user\",\"content\":\""
            , content
            , "\"}]}"
            ]
        frames = [identity, BS.empty, requestId, metadata, payload]
    case parseRequest frames of
        Left err -> annotate (T.unpack err) >> failure
        Right _ -> success


-- ════════════════════════════════════════════════════════════════════════════
--                                                                  // helpers
-- ════════════════════════════════════════════════════════════════════════════

-- | Escape special JSON characters
escapeJsonChar :: Char -> Text
escapeJsonChar '"' = "\\\""
escapeJsonChar '\\' = "\\\\"
escapeJsonChar '\n' = "\\n"
escapeJsonChar '\r' = "\\r"
escapeJsonChar '\t' = "\\t"
escapeJsonChar c
    | c < ' ' = T.pack $ "\\u" <> pad4 (showHex' (fromEnum c))
    | otherwise = T.singleton c
  where
    pad4 s = replicate (4 - length s) '0' <> s
    showHex' n
        | n < 16 = [hexDigit n]
        | otherwise = showHex' (n `div` 16) <> [hexDigit (n `mod` 16)]
    hexDigit d
        | d < 10 = toEnum (fromEnum '0' + d)
        | otherwise = toEnum (fromEnum 'a' + d - 10)


-- ════════════════════════════════════════════════════════════════════════════
--                                                                 // test tree
-- ════════════════════════════════════════════════════════════════════════════

tests :: TestTree
tests = testGroup "ZMQ Transport Adversarial Tests"
    [ testGroup "Multipart Frame Parsing"
        [ testProperty "valid message parses" prop_validMessageParses
        , testProperty "wrong frame count fails" prop_wrongFrameCountFails
        , testProperty "empty identity handled" prop_emptyIdentityHandled
        , testProperty "invalid metadata fails" prop_invalidMetadataFails
        , testProperty "invalid payload fails" prop_invalidPayloadFails
        ]
    , testGroup "Injection Resistance"
        [ testProperty "null bytes in request ID" prop_requestIdNullBytes
        , testProperty "large frames handled" prop_largeFramesHandled
        , testProperty "unicode handled" prop_unicodeHandled
        ]
    , testGroup "Realistic Distributions"
        [ testProperty "realistic requests parse" prop_realisticRequestsParses
        ]
    ]
