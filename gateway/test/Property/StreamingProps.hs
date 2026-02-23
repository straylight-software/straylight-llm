-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                      // straylight-llm // streaming props
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--     "He'd operated on an almost permanent adrenaline high, a byproduct of 
--      youth and proficiency, jacked into a custom cyberspace deck..."
--
--                                                              — Neuromancer
--
-- Property tests for streaming types and SSE parsing.
--
-- Tests:
--   - StreamChunk JSON roundtrip
--   - ChoiceDelta JSON roundtrip
--   - SSE line parsing
--   - Stream flag handling
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

{-# LANGUAGE OverloadedStrings #-}

module Property.StreamingProps
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
--                                                      // stream chunk tests
-- ════════════════════════════════════════════════════════════════════════════

test_streamChunkBasics :: TestTree
test_streamChunkBasics = testGroup "StreamChunk Basics"
    [ testCase "Empty choices chunk parses" $ do
        let json = object
                [ "id" .= ("chatcmpl-123" :: Text)
                , "object" .= ("chat.completion.chunk" :: Text)
                , "created" .= Timestamp 1234567890
                , "model" .= ("gpt-4" :: Text)
                , "choices" .= ([] :: [Value])
                ]
        let result = decode (encode json) :: Maybe StreamChunk
        assertBool "Should parse empty choices" (isJust result)
        case result of
            Just chunk -> length (chunkChoices chunk) @?= 0
            Nothing -> assertFailure "Failed to parse"
    
    , testCase "Single delta chunk parses" $ do
        let json = object
                [ "id" .= ("chatcmpl-123" :: Text)
                , "object" .= ("chat.completion.chunk" :: Text)
                , "created" .= Timestamp 1234567890
                , "model" .= ("gpt-4" :: Text)
                , "choices" .= 
                    [ object
                        [ "index" .= (0 :: Int)
                        , "delta" .= object
                            [ "content" .= ("Hello" :: Text)
                            ]
                        , "finish_reason" .= Null
                        ]
                    ]
                ]
        let result = decode (encode json) :: Maybe StreamChunk
        assertBool "Should parse single delta" (isJust result)
        case result of
            Just chunk -> length (chunkChoices chunk) @?= 1
            Nothing -> assertFailure "Failed to parse"
    
    , testCase "Chunk with finish_reason parses" $ do
        let json = object
                [ "id" .= ("chatcmpl-123" :: Text)
                , "object" .= ("chat.completion.chunk" :: Text)
                , "created" .= Timestamp 1234567890
                , "model" .= ("gpt-4" :: Text)
                , "choices" .= 
                    [ object
                        [ "index" .= (0 :: Int)
                        , "delta" .= object []
                        , "finish_reason" .= ("stop" :: Text)
                        ]
                    ]
                ]
        let result = decode (encode json) :: Maybe StreamChunk
        assertBool "Should parse finish_reason" (isJust result)
    ]

test_choiceDeltaBasics :: TestTree
test_choiceDeltaBasics = testGroup "ChoiceDelta Basics"
    [ testCase "Content delta parses" $ do
        let json = object
                [ "index" .= (0 :: Int)
                , "delta" .= object
                    [ "content" .= ("Hello world" :: Text)
                    ]
                ]
        let result = decode (encode json) :: Maybe ChoiceDelta
        assertBool "Should parse content delta" (isJust result)
    
    , testCase "Role delta parses" $ do
        let json = object
                [ "index" .= (0 :: Int)
                , "delta" .= object
                    [ "role" .= ("assistant" :: Text)
                    ]
                ]
        let result = decode (encode json) :: Maybe ChoiceDelta
        assertBool "Should parse role delta" (isJust result)
    
    , testCase "Empty delta parses" $ do
        let json = object
                [ "index" .= (0 :: Int)
                , "delta" .= object []
                ]
        let result = decode (encode json) :: Maybe ChoiceDelta
        assertBool "Should parse empty delta" (isJust result)
    
    , testCase "Tool call delta parses" $ do
        let json = object
                [ "index" .= (0 :: Int)
                , "delta" .= object
                    [ "tool_calls" .= 
                        [ object
                            [ "index" .= (0 :: Int)
                            , "id" .= ("call_123" :: Text)
                            , "type" .= ("function" :: Text)
                            , "function" .= object
                                [ "name" .= ("get_weather" :: Text)
                                , "arguments" .= ("{" :: Text)
                                ]
                            ]
                        ]
                    ]
                ]
        let result = decode (encode json) :: Maybe ChoiceDelta
        assertBool "Should parse tool call delta" (isJust result)
    ]


-- ════════════════════════════════════════════════════════════════════════════
--                                                          // sse line tests
-- ════════════════════════════════════════════════════════════════════════════

-- | Parse SSE data line (simple version for testing)
parseSSELine :: Text -> Maybe Text
parseSSELine line
    | "data: " `T.isPrefixOf` line = Just $ T.drop 6 line
    | "data:" `T.isPrefixOf` line = Just $ T.drop 5 line
    | otherwise = Nothing

test_sseLineParsing :: TestTree
test_sseLineParsing = testGroup "SSE Line Parsing"
    [ testCase "data: prefix extracts content" $ do
        parseSSELine "data: {\"hello\":\"world\"}" @?= Just "{\"hello\":\"world\"}"
    
    , testCase "data: with space extracts content" $ do
        parseSSELine "data: hello" @?= Just "hello"
    
    , testCase "data: without space extracts content" $ do
        parseSSELine "data:hello" @?= Just "hello"
    
    , testCase "[DONE] is valid data" $ do
        parseSSELine "data: [DONE]" @?= Just "[DONE]"
    
    , testCase "Empty line returns Nothing" $ do
        parseSSELine "" @?= Nothing
    
    , testCase "Non-data line returns Nothing" $ do
        parseSSELine "event: message" @?= Nothing
        parseSSELine ": comment" @?= Nothing
        parseSSELine "id: 123" @?= Nothing
    
    , testCase "data: with JSON object" $ do
        let line = "data: {\"id\":\"chatcmpl-123\",\"choices\":[{\"delta\":{\"content\":\"Hi\"}}]}"
        let result = parseSSELine line
        assertBool "Should extract JSON" (isJust result)
        case result of
            Just json -> assertBool "Should contain id" ("chatcmpl-123" `T.isInfixOf` json)
            Nothing -> assertFailure "Failed to parse"
    ]


-- ════════════════════════════════════════════════════════════════════════════
--                                                      // stream flag tests
-- ════════════════════════════════════════════════════════════════════════════

test_streamFlagHandling :: TestTree
test_streamFlagHandling = testGroup "Stream Flag Handling"
    [ testCase "stream=true in request" $ do
        let json = object
                [ "model" .= ("gpt-4" :: Text)
                , "messages" .= 
                    [ object
                        [ "role" .= ("user" :: Text)
                        , "content" .= ("Hello" :: Text)
                        ]
                    ]
                , "stream" .= True
                ]
        let result = decode (encode json) :: Maybe ChatRequest
        case result of
            Just req -> crStream req @?= Just True
            Nothing -> assertFailure "Failed to parse"
    
    , testCase "stream=false in request" $ do
        let json = object
                [ "model" .= ("gpt-4" :: Text)
                , "messages" .= 
                    [ object
                        [ "role" .= ("user" :: Text)
                        , "content" .= ("Hello" :: Text)
                        ]
                    ]
                , "stream" .= False
                ]
        let result = decode (encode json) :: Maybe ChatRequest
        case result of
            Just req -> crStream req @?= Just False
            Nothing -> assertFailure "Failed to parse"
    
    , testCase "stream omitted in request" $ do
        let json = object
                [ "model" .= ("gpt-4" :: Text)
                , "messages" .= 
                    [ object
                        [ "role" .= ("user" :: Text)
                        , "content" .= ("Hello" :: Text)
                        ]
                    ]
                ]
        let result = decode (encode json) :: Maybe ChatRequest
        case result of
            Just req -> crStream req @?= Nothing
            Nothing -> assertFailure "Failed to parse"
    ]


-- ════════════════════════════════════════════════════════════════════════════
--                                                   // chunk sequence tests
-- ════════════════════════════════════════════════════════════════════════════

test_chunkSequence :: TestTree
test_chunkSequence = testGroup "Chunk Sequence"
    [ testCase "First chunk has role" $ do
        -- OpenAI streams typically start with a role-only delta
        let json = object
                [ "id" .= ("chatcmpl-123" :: Text)
                , "object" .= ("chat.completion.chunk" :: Text)
                , "created" .= Timestamp 1234567890
                , "model" .= ("gpt-4" :: Text)
                , "choices" .= 
                    [ object
                        [ "index" .= (0 :: Int)
                        , "delta" .= object
                            [ "role" .= ("assistant" :: Text)
                            ]
                        , "finish_reason" .= Null
                        ]
                    ]
                ]
        let result = decode (encode json) :: Maybe StreamChunk
        assertBool "Should parse first chunk" (isJust result)
    
    , testCase "Middle chunk has content" $ do
        let json = object
                [ "id" .= ("chatcmpl-123" :: Text)
                , "object" .= ("chat.completion.chunk" :: Text)
                , "created" .= Timestamp 1234567890
                , "model" .= ("gpt-4" :: Text)
                , "choices" .= 
                    [ object
                        [ "index" .= (0 :: Int)
                        , "delta" .= object
                            [ "content" .= ("Hello" :: Text)
                            ]
                        , "finish_reason" .= Null
                        ]
                    ]
                ]
        let result = decode (encode json) :: Maybe StreamChunk
        assertBool "Should parse middle chunk" (isJust result)
    
    , testCase "Final chunk has finish_reason" $ do
        let json = object
                [ "id" .= ("chatcmpl-123" :: Text)
                , "object" .= ("chat.completion.chunk" :: Text)
                , "created" .= Timestamp 1234567890
                , "model" .= ("gpt-4" :: Text)
                , "choices" .= 
                    [ object
                        [ "index" .= (0 :: Int)
                        , "delta" .= object []
                        , "finish_reason" .= ("stop" :: Text)
                        ]
                    ]
                ]
        let result = decode (encode json) :: Maybe StreamChunk
        assertBool "Should parse final chunk" (isJust result)
    
    , testCase "Multiple chunks can be parsed in sequence" $ do
        let chunks = 
                [ object ["id" .= ("c1" :: Text), "object" .= ("chunk" :: Text), "created" .= Timestamp 1, "model" .= ("m" :: Text), "choices" .= ([] :: [Value])]
                , object ["id" .= ("c2" :: Text), "object" .= ("chunk" :: Text), "created" .= Timestamp 2, "model" .= ("m" :: Text), "choices" .= ([] :: [Value])]
                , object ["id" .= ("c3" :: Text), "object" .= ("chunk" :: Text), "created" .= Timestamp 3, "model" .= ("m" :: Text), "choices" .= ([] :: [Value])]
                ]
        let results = map (\j -> decode (encode j) :: Maybe StreamChunk) chunks
        assertBool "All chunks should parse" (all isJust results)
    ]


-- ════════════════════════════════════════════════════════════════════════════
--                                                                 // test tree
-- ════════════════════════════════════════════════════════════════════════════

tests :: TestTree
tests = testGroup "Streaming Property Tests"
    [ test_streamChunkBasics
    , test_choiceDeltaBasics
    , test_sseLineParsing
    , test_streamFlagHandling
    , test_chunkSequence
    ]
