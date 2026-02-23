-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                      // straylight-llm // bench/Main.hs
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--     "The matrix has its roots in primitive arcade games."
--
--                                                              — Neuromancer
--
-- Criterion benchmark suite for straylight-llm gateway.
--
-- Benchmarks:
--   - Router: request routing, provider selection, proof generation
--   - CircuitBreaker: state transitions, concurrent access
--   - SSEBroadcaster: event broadcasting, subscriber scaling
--   - Coeffect: proof generation, JSON serialization
--
-- Run with:
--   cabal bench
--   cabal bench --benchmark-options='--output bench.html'
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

module Main (main) where

import Criterion.Main (defaultMain)

import Bench.Router qualified
import Bench.CircuitBreaker qualified
import Bench.SSEBroadcaster qualified
import Bench.Coeffect qualified
import Bench.E2ELatency qualified


main :: IO ()
main = defaultMain
    [ Bench.E2ELatency.benchmarks   -- E2E latency first (most important for swarm scale)
    , Bench.Router.benchmarks
    , Bench.CircuitBreaker.benchmarks
    , Bench.SSEBroadcaster.benchmarks
    , Bench.Coeffect.benchmarks
    ]
