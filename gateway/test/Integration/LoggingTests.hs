-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                // straylight-llm // integration // logging
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--     "Information wants to be free, but it also wants to be expensive."
--
--                                                              — Stewart Brand
--
-- Tests for structured logging with redaction.
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
{-# LANGUAGE OverloadedStrings #-}

module Integration.LoggingTests
  ( tests,
  )
where

import Observability.Logging
import Test.Tasty
import Test.Tasty.HUnit

-- ════════════════════════════════════════════════════════════════════════════
--                                                       // configuration tests
-- ════════════════════════════════════════════════════════════════════════════

test_defaultConfig :: TestTree
test_defaultConfig = testCase "defaultLogConfig has sensible defaults" $ do
  let config = defaultLogConfig
  lcLevel config @?= LogInfo
  lcFormat config @?= LogFormatJSON
  lcLogRequests config @?= True
  lcLogResponses config @?= True
  lcLogBodies config @?= False -- Bodies disabled by default (PII safety)
  lcMaxBodySize config @?= 1024

test_logLevelOrdering :: TestTree
test_logLevelOrdering = testCase "log levels are ordered correctly" $ do
  assertBool "debug < info" (LogDebug < LogInfo)
  assertBool "info < warn" (LogInfo < LogWarn)
  assertBool "warn < error" (LogWarn < LogError)

-- ════════════════════════════════════════════════════════════════════════════
--                                                            // redaction tests
-- ════════════════════════════════════════════════════════════════════════════

test_redactTextWithPattern :: TestTree
test_redactTextWithPattern = testCase "redactText redacts matching patterns" $ do
  let config = defaultRedactionConfig
  -- Text containing "api_key" should be redacted
  redactText config "my_api_key_value" @?= "[REDACTED]"
  -- Text not containing patterns should pass through
  redactText config "hello world" @?= "hello world"

test_redactTextCaseInsensitive :: TestTree
test_redactTextCaseInsensitive = testCase "redactText is case insensitive" $ do
  let config = defaultRedactionConfig
  redactText config "my_API_KEY_value" @?= "[REDACTED]"
  redactText config "Authorization: Bearer xyz" @?= "[REDACTED]"

test_redactTextPrefixes :: TestTree
test_redactTextPrefixes = testCase "redactText catches common API key prefixes" $ do
  let config = defaultRedactionConfig
  -- OpenAI API key prefix
  redactText config "sk-1234567890abcdef" @?= "[REDACTED]"
  -- GitHub PAT prefix
  redactText config "ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx" @?= "[REDACTED]"

test_redactHeaders :: TestTree
test_redactHeaders = testCase "redactHeaders redacts sensitive header names" $ do
  let config = defaultLogConfig
      headers =
        [ ("Content-Type", "application/json"),
          ("Authorization", "Bearer sk-secret123"),
          ("X-Request-Id", "req_12345"),
          ("User-Agent", "test/1.0")
        ]
      redacted = redactHeaders config headers

  -- Content-Type should pass through
  lookup "Content-Type" redacted @?= Just "application/json"
  -- Authorization should be redacted
  lookup "Authorization" redacted @?= Just "[REDACTED]"
  -- User-Agent should pass through
  lookup "User-Agent" redacted @?= Just "test/1.0"

-- ════════════════════════════════════════════════════════════════════════════
--                                                            // logger tests
-- ════════════════════════════════════════════════════════════════════════════

test_initLogger :: TestTree
test_initLogger = testCase "initLogger succeeds with default config" $ do
  logger <- initLogger defaultLogConfig
  -- Just verify it doesn't crash
  lhConfig logger `seq` pure ()

-- ════════════════════════════════════════════════════════════════════════════
--                                                                 // test tree
-- ════════════════════════════════════════════════════════════════════════════

tests :: TestTree
tests =
  testGroup
    "Logging Tests"
    [ testGroup
        "Configuration"
        [ test_defaultConfig,
          test_logLevelOrdering
        ],
      testGroup
        "Redaction"
        [ test_redactTextWithPattern,
          test_redactTextCaseInsensitive,
          test_redactTextPrefixes,
          test_redactHeaders
        ],
      testGroup
        "Logger"
        [ test_initLogger
        ]
    ]
