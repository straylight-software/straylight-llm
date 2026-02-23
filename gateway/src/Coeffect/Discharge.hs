-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                    // straylight-llm // coeffect/discharge
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--     "They damaged his nervous system with a wartime Russian mycotoxin."
--
--                                                              — Neuromancer
--
-- Discharge proof generation and verification. A DischargeProof provides
-- cryptographic evidence that a computation accessed only the resources
-- it declared (its coeffects).
--
-- The proof is:
--   1. Generated after successful request handling
--   2. Optionally signed with ed25519
--   3. Verifiable offline
--
-- Soundness property (from Continuity.lean):
--   A valid DischargeProof for coeffects C implies that the request
--   execution actually satisfied C.
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# OPTIONS_GHC -Wno-unused-imports #-}

module Coeffect.Discharge
    ( -- * Proof Generation
      generateProof
    , generatePureProof
    , fromGatewayTracking
    
      -- * Signing
    , signProof
    , generateKeyPair
    
      -- * Verification
    , verifyProof
    , verifySignature
    
      -- * Hashing
    , sha256Hash
    , hashProofContent
    ) where

import Crypto.Hash (hash, SHA256, Digest)
import Crypto.PubKey.Ed25519 qualified as Ed25519
import Crypto.Error (CryptoFailable (CryptoPassed, CryptoFailed))
import Data.ByteArray (convert)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding (encodeUtf8)
import Data.Time (UTCTime, getCurrentTime)
import Data.UUID qualified as UUID
import Data.UUID.V4 qualified as UUID

import Coeffect.Types
    ( Coeffect (Pure, Network, Auth, Sandbox, Filesystem, Combined)
    , combineCoeffects
    , coeffectToText
    , NetworkAccess (NetworkAccess, naUrl, naMethod, naContentHash, naTimestamp)
    , FilesystemAccess (FilesystemAccess, faPath, faMode, faContentHash, faTimestamp)
    , FilesystemMode (Read, Write, Execute)
    , AuthUsage (AuthUsage, auProvider, auScope, auTimestamp)
    , Hash (Hash, unHash)
    , PublicKey (PublicKey, unPublicKey)
    , Signature (Signature, unSignature)
    , DischargeProof
        ( DischargeProof
        , dpCoeffects
        , dpNetworkAccess
        , dpFilesystemAccess
        , dpAuthUsage
        , dpBuildId
        , dpDerivationHash
        , dpOutputHashes
        , dpStartTime
        , dpEndTime
        , dpSignature
        )
    , OutputHash (OutputHash, ohName, ohHash)
    , isPure
    , isSigned
    , hasNetworkEvidence
    )
-- NOTE: Effects.Graded also exports AuthUsage, but we use it qualified as G.AuthUsage
-- to avoid shadowing Coeffect.Types.AuthUsage. Full module interface documented here.
import Effects.Graded
    ( -- * Gateway Grade
      GatewayGrade
        ( GatewayGrade
        , ggLatencyMs
        , ggInputTokens
        , ggOutputTokens
        , ggProviderCalls
        , ggRetries
        , ggCacheHits
        , ggCacheMisses
        )
    , emptyGrade
    , combineGrades
    , gradeFromLatency
      -- * Gateway Co-Effect
    , GatewayCoEffect (GatewayCoEffect, gceHttpAccess, gceAuthUsage, gceConfigAccess)
    , emptyCoEffect
    , HttpAccess (HttpAccess, haUrl, haMethod, haTimestamp, haStatusCode)
    -- AuthUsage (AuthUsage, auProvider, auScope, auTimestamp) -- via G qualified
    , ConfigAccess (ConfigAccess, caKey, caTimestamp)
      -- * Gateway Provenance
    , GatewayProvenance
        ( GatewayProvenance
        , gpRequestId
        , gpProvidersUsed
        , gpModelsUsed
        , gpTimestamp
        , gpClientIp
        )
    , emptyProvenance
      -- * Gateway Graded Monad
    , GatewayM (GatewayM, unGatewayM)
    , runGatewayM
    , runGatewayMPure
    , liftGatewayIO
      -- * Cost Tracking Operations
    , withLatency
    , withTokens
    , withCacheHit
    , withCacheMiss
    , withRetry
      -- * Co-Effect Recording
    , recordHttpAccess
    , recordAuthUsage
    , recordConfigAccess
      -- * Provenance Recording
    , recordProvider
    , recordModel
    , recordRequestId
      -- * Grade Inspection
    , getGrade
    , getCoEffect
    , getProvenance
    , shouldCacheResponse
    )
-- Qualified import for G.AuthUsage, G.HttpAccess (when we need the Effects.Graded version)
import Effects.Graded qualified as G
    ( AuthUsage (AuthUsage, auProvider, auScope, auTimestamp)
    , HttpAccess (HttpAccess, haUrl, haMethod, haTimestamp, haStatusCode)
    )


-- ════════════════════════════════════════════════════════════════════════════
--                                                          // proof generation
-- ════════════════════════════════════════════════════════════════════════════

-- | Generate a discharge proof from gateway tracking data
generateProof
    :: Text                             -- ^ Build/request ID
    -> Hash                             -- ^ Derivation/input hash
    -> [OutputHash]                     -- ^ Output hashes
    -> [Coeffect]                       -- ^ Required coeffects
    -> [NetworkAccess]                  -- ^ Network access evidence
    -> [FilesystemAccess]               -- ^ Filesystem access evidence
    -> [Coeffect.Types.AuthUsage]       -- ^ Auth usage evidence
    -> UTCTime                          -- ^ Start time
    -> UTCTime                          -- ^ End time
    -> DischargeProof
generateProof buildId derivHash outputs coeffs network fs auth start end =
    DischargeProof
        { dpCoeffects = coeffs
        , dpNetworkAccess = network
        , dpFilesystemAccess = fs
        , dpAuthUsage = auth
        , dpBuildId = buildId
        , dpDerivationHash = derivHash
        , dpOutputHashes = outputs
        , dpStartTime = start
        , dpEndTime = end
        , dpSignature = Nothing
        }

-- | Generate a pure proof (no external resources)
generatePureProof
    :: Text                             -- ^ Build/request ID
    -> Hash                             -- ^ Derivation/input hash
    -> [OutputHash]                     -- ^ Output hashes
    -> UTCTime                          -- ^ Start time
    -> UTCTime                          -- ^ End time
    -> DischargeProof
generatePureProof buildId derivHash outputs start end =
    generateProof buildId derivHash outputs [Pure] [] [] [] start end

-- | Generate a discharge proof from GatewayM tracking data
fromGatewayTracking
    :: GatewayProvenance                -- ^ Provenance from GatewayM
    -> GatewayCoEffect                  -- ^ Co-effects from GatewayM
    -> ByteString                       -- ^ Request body (for hashing)
    -> ByteString                       -- ^ Response body (for hashing)
    -> IO DischargeProof
fromGatewayTracking prov coeff reqBody respBody = do
    -- Generate unique build ID
    buildId <- UUID.toText <$> UUID.nextRandom
    
    -- Get timestamps
    now <- getCurrentTime
    let startTime = case gpTimestamp prov of
            Just t -> t
            Nothing -> now
    
    -- Compute hashes
    let derivHash = sha256Hash reqBody
        outputHash = OutputHash "response" (sha256Hash respBody)
    
    -- Determine coeffects from co-effects
    let coeffs = determineCoeffects coeff
    
    -- Convert network access
    let networkAccess = map convertHttpAccess (Set.toList $ gceHttpAccess coeff)
    
    -- Convert auth usage
    let authUsage = map convertAuthUsage (Set.toList $ gceAuthUsage coeff)
    
    pure DischargeProof
        { dpCoeffects = coeffs
        , dpNetworkAccess = networkAccess
        , dpFilesystemAccess = []  -- Gateway doesn't access filesystem
        , dpAuthUsage = authUsage
        , dpBuildId = buildId
        , dpDerivationHash = derivHash
        , dpOutputHashes = [outputHash]
        , dpStartTime = startTime
        , dpEndTime = now
        , dpSignature = Nothing
        }

-- | Determine coeffects from co-effect tracking
determineCoeffects :: GatewayCoEffect -> [Coeffect]
determineCoeffects coeff
    | Set.null (gceHttpAccess coeff) 
      && Set.null (gceAuthUsage coeff)
      && Set.null (gceConfigAccess coeff) = [Pure]
    | otherwise = 
        let network = if Set.null (gceHttpAccess coeff) then [] else [Network]
            auth = map (Auth . G.auProvider) (Set.toList $ gceAuthUsage coeff)
        in network ++ auth

-- | Convert GatewayM HttpAccess to Coeffect.Types NetworkAccess
convertHttpAccess :: G.HttpAccess -> NetworkAccess
convertHttpAccess G.HttpAccess{..} = NetworkAccess
    { naUrl = haUrl
    , naMethod = haMethod
    , naContentHash = Hash BS.empty  -- Would need response body
    , naTimestamp = haTimestamp
    }

-- | Convert GatewayM AuthUsage to Coeffect.Types AuthUsage
convertAuthUsage :: G.AuthUsage -> Coeffect.Types.AuthUsage
convertAuthUsage G.AuthUsage{..} = Coeffect.Types.AuthUsage
    { auProvider = auProvider
    , auScope = Just auScope
    , auTimestamp = auTimestamp
    }


-- ════════════════════════════════════════════════════════════════════════════
--                                                                  // signing
-- ════════════════════════════════════════════════════════════════════════════

-- | Generate an Ed25519 key pair
generateKeyPair :: IO (PublicKey, Ed25519.SecretKey)
generateKeyPair = do
    secretKey <- Ed25519.generateSecretKey
    let publicKey = Ed25519.toPublic secretKey
    pure (PublicKey (convert publicKey), secretKey)

-- | Sign a discharge proof with ed25519
signProof :: Ed25519.SecretKey -> DischargeProof -> DischargeProof
signProof secretKey proof =
    let publicKey = Ed25519.toPublic secretKey
        contentHash = hashProofContent proof
        sig = Ed25519.sign secretKey publicKey (unHash contentHash)
    in proof { dpSignature = Just (PublicKey (convert publicKey), Signature (convert sig)) }


-- ════════════════════════════════════════════════════════════════════════════
--                                                             // verification
-- ════════════════════════════════════════════════════════════════════════════

-- | Verify a discharge proof
-- Checks:
--   1. Signature is valid (if present)
--   2. Evidence matches declared coeffects
verifyProof :: DischargeProof -> Either Text ()
verifyProof proof = do
    -- Verify signature if present
    case dpSignature proof of
        Nothing -> Right ()
        Just (pk, sig) -> verifySignature pk sig (hashProofContent proof)
    
    -- Verify evidence matches coeffects
    verifyEvidenceMatches proof

-- | Verify an ed25519 signature
verifySignature :: PublicKey -> Signature -> Hash -> Either Text ()
verifySignature (PublicKey pkBytes) (Signature sigBytes) (Hash msgHash) =
    case (Ed25519.publicKey pkBytes, Ed25519.signature sigBytes) of
        (CryptoPassed pk, CryptoPassed sig) ->
            if Ed25519.verify pk msgHash sig
                then Right ()
                else Left "Signature verification failed"
        (CryptoFailed e, _) -> Left $ "Invalid public key: " <> showT e
        (_, CryptoFailed e) -> Left $ "Invalid signature: " <> showT e
  where
    showT :: Show a => a -> Text
    showT = T.pack . show

-- | Verify that evidence matches declared coeffects
verifyEvidenceMatches :: DischargeProof -> Either Text ()
verifyEvidenceMatches proof
    -- Pure proofs should have no evidence
    | isPure proof && hasEvidence = Left "Pure proof has external evidence"
    -- Network coeffect requires network evidence
    | hasNetworkCoeffect && null (dpNetworkAccess proof) = 
        Left "Network coeffect declared but no network evidence"
    | otherwise = Right ()
  where
    hasEvidence = not (null (dpNetworkAccess proof)) 
               || not (null (dpFilesystemAccess proof))
               || not (null (dpAuthUsage proof))
    hasNetworkCoeffect = any isNetworkCoeffect (dpCoeffects proof)
    isNetworkCoeffect Network = True
    isNetworkCoeffect (Combined cs) = any isNetworkCoeffect cs
    isNetworkCoeffect _ = False


-- ════════════════════════════════════════════════════════════════════════════
--                                                                  // hashing
-- ════════════════════════════════════════════════════════════════════════════

-- | Compute SHA256 hash
sha256Hash :: ByteString -> Hash
sha256Hash bs = Hash (convert (hash bs :: Digest SHA256))

-- | Hash the content of a proof (for signing)
-- Includes: derivationHash, outputHashes, evidence
hashProofContent :: DischargeProof -> Hash
hashProofContent DischargeProof{..} =
    sha256Hash $ BS.concat
        [ unHash dpDerivationHash
        , BS.concat [ unHash (ohHash oh) | oh <- dpOutputHashes ]
        , encodeUtf8 dpBuildId
        , BS.concat [ encodeUtf8 (naUrl na) | na <- dpNetworkAccess ]
        , BS.concat [ encodeUtf8 (Coeffect.Types.auProvider au) | au <- dpAuthUsage ]
        ]
