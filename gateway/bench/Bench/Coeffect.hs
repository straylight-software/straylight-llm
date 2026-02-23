-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                   // straylight-llm // bench/Coeffect.hs
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
-- Coeffect and discharge proof performance benchmarks.
--
-- Tests:
--   - Coeffect combination overhead
--   - Proof generation latency
--   - JSON serialization/deserialization
--   - Hash computation
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

{-# LANGUAGE BangPatterns #-}

module Bench.Coeffect (benchmarks) where

import Control.DeepSeq ()
import Criterion.Main
    ( Benchmark
    , bench
    , bgroup
    , nf
    , nfIO
    , whnf
    )
import Data.Aeson (encode, eitherDecode)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.Time.Clock (getCurrentTime)

import Coeffect.Types
    ( Coeffect (..)
    , combineCoeffects
    , coeffectToText
    , DischargeProof (..)
    , NetworkAccess (..)
    , AuthUsage (..)
    , Hash (..)
    , OutputHash (..)
    , isPure
    , isSigned
    )
import Coeffect.Discharge (sha256Hash, fromGatewayTracking)
import Effects.Graded (emptyProvenance, emptyCoEffect)


-- | All coeffect benchmarks
benchmarks :: Benchmark
benchmarks = bgroup "Coeffect"
    [ combinationBenchmarks
    , serializationBenchmarks
    , hashingBenchmarks
    , proofGenerationBenchmarks
    ]


-- ════════════════════════════════════════════════════════════════════════════
--                                                   // coeffect combination
-- ════════════════════════════════════════════════════════════════════════════

combinationBenchmarks :: Benchmark
combinationBenchmarks = bgroup "Combination"
    [ bench "Pure+Pure" $ whnf (uncurry combineCoeffects) (Pure, Pure)
    , bench "Pure+Network" $ whnf (uncurry combineCoeffects) (Pure, Network)
    , bench "Network+Auth" $ whnf (uncurry combineCoeffects) (Network, Auth "venice")
    , bench "Combined+Network" $ whnf (uncurry combineCoeffects) 
        (Combined [Network, Auth "venice"], Network)
    , bench "combine/10-coeffects" $ nf combineMany 10
    , bench "combine/100-coeffects" $ nf combineMany 100
    , bench "coeffectToText/simple" $ nf coeffectToText Network
    , bench "coeffectToText/combined" $ nf coeffectToText 
        (Combined [Network, Auth "venice", Auth "anthropic", Filesystem "/tmp"])
    ]
  where
    combineMany :: Int -> Coeffect
    combineMany n = foldr combineCoeffects Pure (replicate n Network)


-- ════════════════════════════════════════════════════════════════════════════
--                                                        // serialization
-- ════════════════════════════════════════════════════════════════════════════

serializationBenchmarks :: Benchmark
serializationBenchmarks = bgroup "Serialization"
    [ bgroup "Coeffect"
        [ bench "encode/Pure" $ nf encode Pure
        , bench "encode/Network" $ nf encode Network
        , bench "encode/Auth" $ nf encode (Auth "venice")
        , bench "encode/Combined" $ nf encode 
            (Combined [Network, Auth "venice", Auth "anthropic"])
        , bench "decode/Network" $ nf (eitherDecode @Coeffect) encodedNetwork
        ]
    , bgroup "DischargeProof"
        [ bench "encode" $ nfIO $ do
            proof <- sampleProof
            pure $! encode proof
        , bench "roundtrip" $ nfIO $ do
            proof <- sampleProof
            let !encoded = encode proof
            let !decoded = eitherDecode @DischargeProof encoded
            pure decoded
        , bench "isPure" $ nfIO $ do
            proof <- sampleProof
            pure $! isPure proof
        , bench "isSigned" $ nfIO $ do
            proof <- sampleProof
            pure $! isSigned proof
        ]
    ]
  where
    encodedNetwork :: LBS.ByteString
    encodedNetwork = encode Network

-- | Sample proof for serialization benchmarks
sampleProof :: IO DischargeProof
sampleProof = do
    now <- getCurrentTime
    pure DischargeProof
        { dpCoeffects = [Network, Auth "venice", Auth "anthropic"]
        , dpNetworkAccess = 
            [ NetworkAccess
                { naUrl = "https://api.venice.ai/v1/chat/completions"
                , naMethod = "POST"
                , naContentHash = Hash (BS.replicate 32 0xAB)
                , naTimestamp = now
                }
            ]
        , dpFilesystemAccess = []
        , dpAuthUsage = 
            [ AuthUsage
                { auProvider = "venice"
                , auScope = Just "inference"
                , auTimestamp = now
                }
            ]
        , dpBuildId = "req_abc123def456789"
        , dpDerivationHash = Hash (BS.replicate 32 0xCD)
        , dpOutputHashes = 
            [ OutputHash "response" (Hash (BS.replicate 32 0xEF))
            ]
        , dpStartTime = now
        , dpEndTime = now
        , dpSignature = Nothing
        }


-- ════════════════════════════════════════════════════════════════════════════
--                                                              // hashing
-- ════════════════════════════════════════════════════════════════════════════

hashingBenchmarks :: Benchmark
hashingBenchmarks = bgroup "Hashing"
    [ bench "sha256Hash/empty" $ nf sha256Hash BS.empty
    , bench "sha256Hash/1KB" $ nf sha256Hash (BS.replicate 1024 0x42)
    , bench "sha256Hash/10KB" $ nf sha256Hash (BS.replicate 10240 0x42)
    , bench "sha256Hash/100KB" $ nf sha256Hash (BS.replicate 102400 0x42)
    , bench "sha256Hash/1MB" $ nf sha256Hash (BS.replicate 1048576 0x42)
    ]


-- ════════════════════════════════════════════════════════════════════════════
--                                                      // proof generation
-- ════════════════════════════════════════════════════════════════════════════

proofGenerationBenchmarks :: Benchmark
proofGenerationBenchmarks = bgroup "ProofGeneration"
    [ bench "fromGatewayTracking/empty" $ nfIO $
        fromGatewayTracking emptyProvenance emptyCoEffect BS.empty BS.empty
    , bench "fromGatewayTracking/1KB-request" $ nfIO $
        fromGatewayTracking emptyProvenance emptyCoEffect 
            (BS.replicate 1024 0x42) BS.empty
    , bench "fromGatewayTracking/1KB-both" $ nfIO $
        fromGatewayTracking emptyProvenance emptyCoEffect 
            (BS.replicate 1024 0x42) (BS.replicate 1024 0x43)
    , bench "fromGatewayTracking/10KB-both" $ nfIO $
        fromGatewayTracking emptyProvenance emptyCoEffect 
            (BS.replicate 10240 0x42) (BS.replicate 10240 0x43)
    ]
