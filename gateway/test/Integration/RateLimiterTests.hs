-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                              // straylight-llm // integration // ratelimiter
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--     "Time passed. The construct flickered. Zero smiled."
--
--                                                              — Neuromancer
--
-- Tests for token bucket rate limiter.
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
{-# LANGUAGE OverloadedStrings #-}

module Integration.RateLimiterTests
  ( tests,
  )
where

import Control.Concurrent (threadDelay)
import Control.Monad (replicateM_)
import Resilience.RateLimiter
  ( KeyLimits (KeyLimits),
    RateLimitConfig
      ( RateLimitConfig,
        rlcBucketExpirySeconds,
        rlcBurstCapacity,
        rlcCleanupIntervalSeconds,
        rlcEnabled,
        rlcRequestsPerMinute
      ),
    RateLimitResult (RateLimitAllowed, RateLimitExceeded),
    RateLimiterStats (rlsActiveBuckets, rlsTotalAllowed, rlsTotalRejected),
    checkRateLimit,
    consumeToken,
    defaultRateLimitConfig,
    getRateLimiterStats,
    newRateLimiter,
    setKeyLimits,
  )
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

-- ════════════════════════════════════════════════════════════════════════════
--                                                       // configuration tests
-- ════════════════════════════════════════════════════════════════════════════

test_defaultConfig :: TestTree
test_defaultConfig = testCase "defaultRateLimitConfig has sane defaults" $ do
  let config = defaultRateLimitConfig
  rlcEnabled config @?= False
  rlcRequestsPerMinute config @?= 60
  rlcBurstCapacity config @?= 10

-- ════════════════════════════════════════════════════════════════════════════
--                                                           // disabled tests
-- ════════════════════════════════════════════════════════════════════════════

test_disabledAllowsAll :: TestTree
test_disabledAllowsAll = testCase "disabled rate limiter allows all requests" $ do
  limiter <- newRateLimiter defaultRateLimitConfig
  -- Consume many tokens - should all be allowed when disabled
  result1 <- consumeToken limiter "test-key"
  result2 <- consumeToken limiter "test-key"
  result3 <- consumeToken limiter "test-key"
  assertAllowed result1
  assertAllowed result2
  assertAllowed result3

-- ════════════════════════════════════════════════════════════════════════════
--                                                            // enabled tests
-- ════════════════════════════════════════════════════════════════════════════

test_enabledEnforcesLimits :: TestTree
test_enabledEnforcesLimits = testCase "enabled rate limiter enforces limits" $ do
  let config =
        RateLimitConfig
          { rlcEnabled = True,
            rlcRequestsPerMinute = 60, -- 1/second
            rlcBurstCapacity = 2, -- Only allow 2 burst
            rlcCleanupIntervalSeconds = 3600,
            rlcBucketExpirySeconds = 3600
          }
  limiter <- newRateLimiter config

  -- First 62 requests should succeed (60 RPM + 2 burst = 62 capacity)
  -- But let's just test the burst capacity of 2 extra
  -- Initial capacity = 60 + 2 = 62

  -- Consume all tokens rapidly
  results <- sequence $ replicate 62 (consumeToken limiter "burst-key")
  let allowedCount = length $ filter isAllowed results
  allowedCount @?= 62

  -- Next request should be rate limited
  result <- consumeToken limiter "burst-key"
  assertExceeded result

test_checkDoesNotConsume :: TestTree
test_checkDoesNotConsume = testCase "checkRateLimit does not consume tokens" $ do
  let config =
        RateLimitConfig
          { rlcEnabled = True,
            rlcRequestsPerMinute = 60,
            rlcBurstCapacity = 0, -- No burst, exactly 60 tokens
            rlcCleanupIntervalSeconds = 3600,
            rlcBucketExpirySeconds = 3600
          }
  limiter <- newRateLimiter config

  -- Check multiple times - should not consume
  _ <- checkRateLimit limiter "check-key"
  _ <- checkRateLimit limiter "check-key"
  _ <- checkRateLimit limiter "check-key"

  -- Now consume all 60 tokens
  replicateM_ 60 (consumeToken limiter "check-key")

  -- 61st should fail
  result <- consumeToken limiter "check-key"
  assertExceeded result

test_tokensRefill :: TestTree
test_tokensRefill = testCase "tokens refill over time" $ do
  let config =
        RateLimitConfig
          { rlcEnabled = True,
            rlcRequestsPerMinute = 60, -- 1 token/second
            rlcBurstCapacity = 0,
            rlcCleanupIntervalSeconds = 3600,
            rlcBucketExpirySeconds = 3600
          }
  limiter <- newRateLimiter config

  -- Consume all 60 tokens
  replicateM_ 60 (consumeToken limiter "refill-key")

  -- Should be rate limited
  result1 <- consumeToken limiter "refill-key"
  assertExceeded result1

  -- Wait 1.1 seconds for 1 token to refill
  threadDelay 1100000

  -- Should have 1 token now
  result2 <- consumeToken limiter "refill-key"
  assertAllowed result2

-- ════════════════════════════════════════════════════════════════════════════
--                                                         // per-key limits
-- ════════════════════════════════════════════════════════════════════════════

test_perKeyLimits :: TestTree
test_perKeyLimits = testCase "per-key limits override defaults" $ do
  let config =
        RateLimitConfig
          { rlcEnabled = True,
            rlcRequestsPerMinute = 60,
            rlcBurstCapacity = 0,
            rlcCleanupIntervalSeconds = 3600,
            rlcBucketExpirySeconds = 3600
          }
  limiter <- newRateLimiter config

  -- Set very low limit for VIP key
  setKeyLimits limiter "limited-key" (KeyLimits 6 0) -- Only 6 requests/minute

  -- Consume 6 tokens
  replicateM_ 6 (consumeToken limiter "limited-key")

  -- 7th should fail
  result <- consumeToken limiter "limited-key"
  assertExceeded result

-- ════════════════════════════════════════════════════════════════════════════
--                                                         // stats tracking
-- ════════════════════════════════════════════════════════════════════════════

test_statsTracking :: TestTree
test_statsTracking = testCase "stats are tracked correctly" $ do
  let config =
        RateLimitConfig
          { rlcEnabled = True,
            rlcRequestsPerMinute = 60,
            rlcBurstCapacity = 2,
            rlcCleanupIntervalSeconds = 3600,
            rlcBucketExpirySeconds = 3600
          }
  limiter <- newRateLimiter config

  -- Consume 62 tokens (should all succeed) then 1 more (should fail)
  replicateM_ 62 (consumeToken limiter "stats-key")
  _ <- consumeToken limiter "stats-key"

  stats <- getRateLimiterStats limiter
  rlsTotalAllowed stats @?= 62
  rlsTotalRejected stats @?= 1
  rlsActiveBuckets stats @?= 1

-- ════════════════════════════════════════════════════════════════════════════
--                                                                  // helpers
-- ════════════════════════════════════════════════════════════════════════════

isAllowed :: RateLimitResult -> Bool
isAllowed (RateLimitAllowed _ _) = True
isAllowed (RateLimitExceeded _) = False

assertAllowed :: RateLimitResult -> IO ()
assertAllowed result =
  assertBool ("Expected RateLimitAllowed but got: " ++ show result) (isAllowed result)

assertExceeded :: RateLimitResult -> IO ()
assertExceeded result =
  assertBool ("Expected RateLimitExceeded but got: " ++ show result) (not $ isAllowed result)

-- ════════════════════════════════════════════════════════════════════════════
--                                                                 // test tree
-- ════════════════════════════════════════════════════════════════════════════

tests :: TestTree
tests =
  testGroup
    "RateLimiter Tests"
    [ testGroup
        "Configuration"
        [ test_defaultConfig
        ],
      testGroup
        "Disabled Mode"
        [ test_disabledAllowsAll
        ],
      testGroup
        "Enabled Mode"
        [ test_enabledEnforcesLimits,
          test_checkDoesNotConsume,
          test_tokensRefill
        ],
      testGroup
        "Per-Key Limits"
        [ test_perKeyLimits
        ],
      testGroup
        "Statistics"
        [ test_statsTracking
        ]
    ]
