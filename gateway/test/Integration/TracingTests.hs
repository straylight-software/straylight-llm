-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                // straylight-llm // integration // tracing
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--     "The sky was that shade of gray you get when you've been staring
--      at a screen too long."
--
--                                                              — Neuromancer
--
-- Tests for OpenTelemetry tracing integration.
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
{-# LANGUAGE OverloadedStrings #-}

module Integration.TracingTests
  ( tests,
  )
where

import Observability.Tracing
import Test.Tasty
import Test.Tasty.HUnit

-- ════════════════════════════════════════════════════════════════════════════
--                                                       // configuration tests
-- ════════════════════════════════════════════════════════════════════════════

test_defaultConfig :: TestTree
test_defaultConfig = testCase "defaultTracingConfig has tracing disabled" $ do
  let config = defaultTracingConfig
  tcEnabled config @?= False
  tcServiceName config @?= "straylight-llm"
  tcServiceVersion config @?= "0.1.0"
  tcSampleRate config @?= 1.0

test_defaultEndpoint :: TestTree
test_defaultEndpoint = testCase "default OTLP endpoint is localhost:4317" $ do
  let config = defaultTracingConfig
  tcOtlpEndpoint config @?= "http://localhost:4317"

-- ════════════════════════════════════════════════════════════════════════════
--                                                            // tracer tests
-- ════════════════════════════════════════════════════════════════════════════

test_initTracerDisabled :: TestTree
test_initTracerDisabled = testCase "initTracer with disabled config succeeds" $ do
  tracer <- initTracer defaultTracingConfig
  -- Just verify it doesn't crash
  shutdownTracer tracer

test_withSpanDisabled :: TestTree
test_withSpanDisabled = testCase "withSpan with disabled tracing is a no-op" $ do
  tracer <- initTracer defaultTracingConfig
  (result, ctx) <- withSpan tracer "test-span" SpanKindInternal $ do
    pure (42 :: Int)
  result @?= 42
  -- Context should be empty when tracing is disabled
  scTraceId ctx @?= ""
  scSpanId ctx @?= ""
  scSampled ctx @?= False
  shutdownTracer tracer

test_withSpanEnabled :: TestTree
test_withSpanEnabled = testCase "withSpan with enabled tracing creates context" $ do
  let config = defaultTracingConfig {tcEnabled = True}
  tracer <- initTracer config
  (result, ctx) <- withSpan tracer "test-span" SpanKindServer $ do
    pure ("hello" :: String)
  result @?= "hello"
  -- Context should have valid IDs when tracing is enabled
  assertBool "traceId should not be empty" (scTraceId ctx /= "")
  assertBool "spanId should not be empty" (scSpanId ctx /= "")
  scSampled ctx @?= True
  shutdownTracer tracer

-- ════════════════════════════════════════════════════════════════════════════
--                                                                 // test tree
-- ════════════════════════════════════════════════════════════════════════════

tests :: TestTree
tests =
  testGroup
    "Tracing Tests"
    [ testGroup
        "Configuration"
        [ test_defaultConfig,
          test_defaultEndpoint
        ],
      testGroup
        "Tracer Initialization"
        [ test_initTracerDisabled,
          test_withSpanDisabled,
          test_withSpanEnabled
        ]
    ]
