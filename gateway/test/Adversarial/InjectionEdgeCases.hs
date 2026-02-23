-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                // straylight-llm // adversarial // injection
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--     "He'd see the matrix in his sleep, bright lattices of logic."
--
--                                                              — Neuromancer
--
-- Injection edge case tests.
-- Designed to BREAK things - hunt for real bugs.
--
-- Tests:
--   - Unicode lookalikes in text fields
--   - Path traversal in model names
--   - JSON structure attacks
--   - Boundary conditions (empty, huge inputs)
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

{-# LANGUAGE OverloadedStrings #-}

module Adversarial.InjectionEdgeCases
    ( tests
    ) where

import Data.Aeson (decode, encode, object, (.=), Value(..))
import Data.ByteString.Lazy qualified as LBS
import Data.Maybe (isJust, isNothing)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Test.Tasty
import Test.Tasty.HUnit

import Types


-- ════════════════════════════════════════════════════════════════════════════
--                                                    // unicode injection tests
-- ════════════════════════════════════════════════════════════════════════════

-- | Test that unicode lookalike characters are handled safely
test_unicodeLookalikes :: TestTree
test_unicodeLookalikes = testGroup "Unicode Lookalikes"
    [ testCase "Cyrillic lookalikes in model ID" $ do
        -- Cyrillic 'а' (U+0430) looks like Latin 'a'
        let modelId = ModelId "clаude-3-opus"  -- Note: 'а' is Cyrillic
        let encoded = encode modelId
        let decoded = decode encoded :: Maybe ModelId
        assertBool "Should decode safely" (isJust decoded)
        -- Should preserve the exact characters
        assertEqual "Should preserve unicode" modelId (maybe (ModelId "") id decoded)
    
    , testCase "Zero-width characters in model ID" $ do
        -- Zero-width space (U+200B)
        let modelId = ModelId "claude\x200B3-opus"
        let encoded = encode modelId
        let decoded = decode encoded :: Maybe ModelId
        assertBool "Should decode safely" (isJust decoded)
    
    , testCase "Null byte in model ID" $ do
        -- Null byte should be preserved or rejected, not truncated
        let modelId = ModelId "claude\x00-3-opus"
        let encoded = encode modelId
        let decoded = decode encoded :: Maybe ModelId
        assertBool "Should decode safely" (isJust decoded)
        -- The key point: it shouldn't silently truncate
        case decoded of
            Nothing -> pure ()  -- Rejection is OK
            Just (ModelId t) -> assertBool "Should preserve full text" (T.length t > 6)
    
    , testCase "Unicode normalization variants" $ do
        -- These are different codepoint sequences for the same glyph
        let nfc = "café"   -- é as single codepoint U+00E9
        let nfd = "café"  -- e + combining acute U+0065 U+0301
        let modelNfc = ModelId nfc
        let modelNfd = ModelId nfd
        -- Both should parse successfully
        assertBool "NFC should decode" (isJust (decode (encode modelNfc) :: Maybe ModelId))
        assertBool "NFD should decode" (isJust (decode (encode modelNfd) :: Maybe ModelId))
    ]

-- | Test path traversal attempts in model names
test_pathTraversal :: TestTree
test_pathTraversal = testGroup "Path Traversal"
    [ testCase "Simple path traversal" $ do
        let modelId = ModelId "../../../etc/passwd"
        let encoded = encode modelId
        let decoded = decode encoded :: Maybe ModelId
        -- Should parse (we're not rejecting at parse time)
        -- but the value should be preserved exactly
        assertEqual "Should preserve traversal string" (Just modelId) decoded
    
    , testCase "URL-encoded path traversal" $ do
        let modelId = ModelId "..%2f..%2f..%2fetc/passwd"
        let encoded = encode modelId
        let decoded = decode encoded :: Maybe ModelId
        assertEqual "Should preserve URL-encoded string" (Just modelId) decoded
    
    , testCase "Double URL-encoded traversal" $ do
        let modelId = ModelId "..%252f..%252fetc/passwd"
        let encoded = encode modelId
        let decoded = decode encoded :: Maybe ModelId
        assertEqual "Should preserve double-encoded string" (Just modelId) decoded
    
    , testCase "Backslash traversal (Windows-style)" $ do
        let modelId = ModelId "..\\..\\..\\etc\\passwd"
        let encoded = encode modelId
        let decoded = decode encoded :: Maybe ModelId
        assertEqual "Should preserve backslash string" (Just modelId) decoded
    ]


-- ════════════════════════════════════════════════════════════════════════════
--                                                       // json structure tests
-- ════════════════════════════════════════════════════════════════════════════

-- | Test deeply nested JSON doesn't cause stack overflow
test_deepNesting :: TestTree
test_deepNesting = testGroup "Deep Nesting"
    [ testCase "Deeply nested tool calls" $ do
        -- Build deeply nested JSON
        let depth = 50 :: Int
            nested = foldr (\_ acc -> object ["nested" .= acc]) (object ["leaf" .= ("value" :: Text)]) [1..depth]
            json = object
                [ "model" .= ("test" :: Text)
                , "messages" .= [object ["role" .= ("user" :: Text), "content" .= ("hi" :: Text)]]
                , "metadata" .= nested  -- This field doesn't exist but tests parser depth
                ]
        -- This should not crash
        let result = decode (encode json) :: Maybe ChatRequest
        -- It's OK if it fails to parse (unknown field) but shouldn't crash
        pure ()
    
    , testCase "Many array elements" $ do
        -- Array with 10000 elements
        let manyMessages = replicate 10000 $ object
                [ "role" .= ("user" :: Text)
                , "content" .= ("message" :: Text)
                ]
            json = object
                [ "model" .= ("test" :: Text)
                , "messages" .= manyMessages
                ]
        -- This should parse (though slowly) - tests memory handling
        let result = decode (encode json) :: Maybe ChatRequest
        assertBool "Should parse large array" (isJust result)
        case result of
            Just req -> assertEqual "Should have all messages" 10000 (length (crMessages req))
            Nothing -> assertFailure "Failed to parse"
    ]

-- | Test malformed JSON handling
test_malformedJson :: TestTree
test_malformedJson = testGroup "Malformed JSON"
    [ testCase "Truncated JSON" $ do
        let truncated = "{\"model\": \"test\", \"messages\": ["
        let result = decode (LBS.fromStrict $ TE.encodeUtf8 truncated) :: Maybe ChatRequest
        assertBool "Truncated JSON should fail to parse" (isNothing result)
    
    , testCase "Invalid UTF-8 sequences" $ do
        -- Invalid UTF-8: 0xFF is never valid
        let invalid = LBS.pack [0x7b, 0x22, 0x6d, 0x6f, 0x64, 0x65, 0x6c, 0x22, 0x3a, 0xff, 0x7d]
        let result = decode invalid :: Maybe ChatRequest
        assertBool "Invalid UTF-8 should fail to parse" (isNothing result)
    
    , testCase "Duplicate keys" $ do
        -- JSON with duplicate keys - behavior is implementation-defined
        let dupes = "{\"model\": \"first\", \"model\": \"second\", \"messages\": []}"
        let result = decode (LBS.fromStrict $ TE.encodeUtf8 dupes) :: Maybe ChatRequest
        -- Either parse should be OK, but shouldn't crash
        case result of
            Just req -> pure ()  -- Aeson takes last value
            Nothing -> pure ()   -- Rejection also OK
    ]


-- ════════════════════════════════════════════════════════════════════════════
--                                                        // boundary conditions
-- ════════════════════════════════════════════════════════════════════════════

-- | Test boundary conditions
test_boundaryConditions :: TestTree
test_boundaryConditions = testGroup "Boundary Conditions"
    [ testCase "Empty model ID" $ do
        let modelId = ModelId ""
        let encoded = encode modelId
        let decoded = decode encoded :: Maybe ModelId
        assertEqual "Should preserve empty string" (Just modelId) decoded
    
    , testCase "Very long model ID" $ do
        -- 10KB model name
        let longName = T.replicate 10240 "a"
        let modelId = ModelId longName
        let encoded = encode modelId
        let decoded = decode encoded :: Maybe ModelId
        assertEqual "Should preserve long string" (Just modelId) decoded
    
    , testCase "Empty messages array" $ do
        let json = object
                [ "model" .= ("test" :: Text)
                , "messages" .= ([] :: [Value])
                ]
        let result = decode (encode json) :: Maybe ChatRequest
        -- Empty messages should parse successfully
        assertBool "Should parse empty messages" (isJust result)
    
    , testCase "Temperature at boundaries" $ do
        -- Temperature 0.0 (minimum)
        let temp0 = Temperature 0.0
        assertEqual "Temp 0.0 roundtrip" (Just temp0) (decode (encode temp0))
        
        -- Temperature 2.0 (typical max)
        let temp2 = Temperature 2.0
        assertEqual "Temp 2.0 roundtrip" (Just temp2) (decode (encode temp2))
        
        -- Negative temperature (should preserve, validation is elsewhere)
        let tempNeg = Temperature (-1.0)
        assertEqual "Negative temp roundtrip" (Just tempNeg) (decode (encode tempNeg))
    
    , testCase "Max tokens at boundaries" $ do
        -- MaxTokens 0
        let mt0 = MaxTokens 0
        assertEqual "MaxTokens 0 roundtrip" (Just mt0) (decode (encode mt0))
        
        -- Large MaxTokens
        let mtLarge = MaxTokens 1000000
        assertEqual "Large MaxTokens roundtrip" (Just mtLarge) (decode (encode mtLarge))
    ]

-- | Test special character handling in content
test_specialCharacters :: TestTree
test_specialCharacters = testGroup "Special Characters"
    [ testCase "Content with control characters" $ do
        let content = TextContent "hello\x00\x01\x02world"
        let encoded = encode content
        let decoded = decode encoded :: Maybe MessageContent
        assertEqual "Should preserve control chars" (Just content) decoded
    
    , testCase "Content with newlines and tabs" $ do
        let content = TextContent "line1\nline2\tcolumn"
        let encoded = encode content
        let decoded = decode encoded :: Maybe MessageContent
        assertEqual "Should preserve whitespace" (Just content) decoded
    
    , testCase "Content with emoji" $ do
        let content = TextContent "Hello 👋 World 🌍"
        let encoded = encode content
        let decoded = decode encoded :: Maybe MessageContent
        assertEqual "Should preserve emoji" (Just content) decoded
    
    , testCase "Content with right-to-left text" $ do
        -- Hebrew text
        let content = TextContent "Hello שלום World"
        let encoded = encode content
        let decoded = decode encoded :: Maybe MessageContent
        assertEqual "Should preserve RTL text" (Just content) decoded
    ]


-- ════════════════════════════════════════════════════════════════════════════
--                                                                 // test tree
-- ════════════════════════════════════════════════════════════════════════════

tests :: TestTree
tests = testGroup "Injection Edge Cases"
    [ test_unicodeLookalikes
    , test_pathTraversal
    , test_deepNesting
    , test_malformedJson
    , test_boundaryConditions
    , test_specialCharacters
    ]
