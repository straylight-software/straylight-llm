-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                         // straylight-llm // coeffect props
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--     "He'd see the matrix in his sleep, bright lattices of logic."
--
--                                                              — Neuromancer
--
-- Property tests for Coeffect types JSON serialization.
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

{-# LANGUAGE OverloadedStrings #-}

module Property.CoeffectProps
    ( tests
    ) where

import Coeffect.Types
import Data.Aeson (decode, encode)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Text (Text)
import Data.Time.Clock (UTCTime (..), secondsToDiffTime)
import Data.Time.Calendar (fromGregorian)

import Hedgehog
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Test.Tasty
import Test.Tasty.Hedgehog


-- ════════════════════════════════════════════════════════════════════════════
--                                                                // generators
-- ════════════════════════════════════════════════════════════════════════════

genText :: Gen Text
genText = Gen.text (Range.linear 0 100) Gen.alphaNum

genNonEmptyText :: Gen Text
genNonEmptyText = Gen.text (Range.linear 1 100) Gen.alphaNum

genUTCTime :: Gen UTCTime
genUTCTime = do
    year <- Gen.integral (Range.linear 2020 2030)
    month <- Gen.int (Range.linear 1 12)
    day <- Gen.int (Range.linear 1 28)
    hour <- Gen.integral (Range.linear 0 86399)
    pure $ UTCTime (fromGregorian year month day) (secondsToDiffTime hour)

genByteString :: Int -> Gen ByteString
genByteString n = BS.pack <$> Gen.list (Range.singleton n) (Gen.word8 Range.constantBounded)

genHash :: Gen Hash
genHash = Hash <$> genByteString 32  -- SHA256 is 32 bytes

genCoeffect :: Gen Coeffect
genCoeffect = Gen.recursive Gen.choice
    [ pure Pure
    , pure Network
    , Auth <$> genNonEmptyText
    , Sandbox <$> genNonEmptyText
    , Filesystem <$> genNonEmptyText
    ]
    [ Combined <$> Gen.list (Range.linear 1 3) genCoeffect
    ]

genNetworkAccess :: Gen NetworkAccess
genNetworkAccess = NetworkAccess
    <$> genNonEmptyText
    <*> Gen.element ["GET", "POST", "PUT", "DELETE", "PATCH"]
    <*> genHash
    <*> genUTCTime

genFilesystemMode :: Gen FilesystemMode
genFilesystemMode = Gen.element [Read, Write, Execute]

genFilesystemAccess :: Gen FilesystemAccess
genFilesystemAccess = FilesystemAccess
    <$> genNonEmptyText
    <*> genFilesystemMode
    <*> Gen.maybe genHash  -- faContentHash is Maybe Hash
    <*> genUTCTime

genAuthUsage :: Gen AuthUsage
genAuthUsage = AuthUsage
    <$> Gen.element ["openai", "anthropic", "venice", "vertex"]
    <*> Gen.maybe (Gen.element ["chat", "embeddings", "completions"])  -- auScope is Maybe Text
    <*> genUTCTime

genOutputHash :: Gen OutputHash
genOutputHash = OutputHash
    <$> genNonEmptyText  -- ohName
    <*> genHash          -- ohHash

genDischargeProof :: Gen DischargeProof
genDischargeProof = DischargeProof
    <$> Gen.list (Range.linear 0 5) genCoeffect
    <*> Gen.list (Range.linear 0 3) genNetworkAccess
    <*> Gen.list (Range.linear 0 3) genFilesystemAccess
    <*> Gen.list (Range.linear 0 3) genAuthUsage
    <*> genNonEmptyText
    <*> genHash
    <*> Gen.list (Range.linear 0 3) genOutputHash
    <*> genUTCTime
    <*> genUTCTime
    <*> pure Nothing  -- Signature generation requires IO


-- ════════════════════════════════════════════════════════════════════════════
--                                                      // roundtrip properties
-- ════════════════════════════════════════════════════════════════════════════

prop_coeffectRoundtrip :: Property
prop_coeffectRoundtrip = property $ do
    x <- forAll genCoeffect
    decode (encode x) === Just x

prop_networkAccessRoundtrip :: Property
prop_networkAccessRoundtrip = property $ do
    x <- forAll genNetworkAccess
    decode (encode x) === Just x

prop_filesystemAccessRoundtrip :: Property
prop_filesystemAccessRoundtrip = property $ do
    x <- forAll genFilesystemAccess
    decode (encode x) === Just x

prop_authUsageRoundtrip :: Property
prop_authUsageRoundtrip = property $ do
    x <- forAll genAuthUsage
    decode (encode x) === Just x

prop_dischargeProofRoundtrip :: Property
prop_dischargeProofRoundtrip = property $ do
    x <- forAll genDischargeProof
    decode (encode x) === Just x

prop_hashRoundtrip :: Property
prop_hashRoundtrip = property $ do
    x <- forAll genHash
    decode (encode x) === Just x


-- ════════════════════════════════════════════════════════════════════════════
--                                                    // algebraic properties
-- ════════════════════════════════════════════════════════════════════════════

-- | Left identity: Pure `combineCoeffects` c ≡ c
prop_coeffectLeftIdentity :: Property
prop_coeffectLeftIdentity = property $ do
    c <- forAll genCoeffect
    combineCoeffects Pure c === c

-- | Right identity: c `combineCoeffects` Pure ≡ c
prop_coeffectRightIdentity :: Property
prop_coeffectRightIdentity = property $ do
    c <- forAll genCoeffect
    combineCoeffects c Pure === c

-- | Associativity: (a `combineCoeffects` b) `combineCoeffects` c ≡ a `combineCoeffects` (b `combineCoeffects` c)
-- Note: We test structural equivalence, which requires normalization for Combined
prop_coeffectAssociativity :: Property
prop_coeffectAssociativity = property $ do
    a <- forAll genCoeffect
    b <- forAll genCoeffect
    c <- forAll genCoeffect
    -- Flatten both sides to compare
    flattenCoeffect (combineCoeffects (combineCoeffects a b) c) 
        === flattenCoeffect (combineCoeffects a (combineCoeffects b c))

-- | Helper to flatten nested Combined into a single Combined list
flattenCoeffect :: Coeffect -> [Coeffect]
flattenCoeffect Pure = []
flattenCoeffect (Combined cs) = concatMap flattenCoeffect cs
flattenCoeffect c = [c]

-- | Pure is identity - combining with pure gives back the other
prop_pureIsIdentity :: Property
prop_pureIsIdentity = property $ do
    -- Pure combined with Pure is Pure
    combineCoeffects Pure Pure === Pure

-- | Network absorbed into combined
prop_networkAbsorbed :: Property
prop_networkAbsorbed = property $ do
    -- Network + Network should just be Combined [Network, Network]
    let combined = combineCoeffects Network Network
    case combined of
        Combined cs -> length cs === 2
        _ -> failure

-- | Coeffect equivalence: Pure is identity for combine
prop_coeffectPureIdentity :: Property
prop_coeffectPureIdentity = property $ do
    c <- forAll genCoeffect
    -- Left identity
    combineCoeffects Pure c === c
    -- Right identity
    combineCoeffects c Pure === c


-- ════════════════════════════════════════════════════════════════════════════
--                                                                 // test tree
-- ════════════════════════════════════════════════════════════════════════════

tests :: TestTree
tests = testGroup "Coeffect Property Tests"
    [ testGroup "JSON Roundtrip"
        [ testProperty "Coeffect round-trip" prop_coeffectRoundtrip
        , testProperty "NetworkAccess round-trip" prop_networkAccessRoundtrip
        , testProperty "FilesystemAccess round-trip" prop_filesystemAccessRoundtrip
        , testProperty "AuthUsage round-trip" prop_authUsageRoundtrip
        , testProperty "DischargeProof round-trip" prop_dischargeProofRoundtrip
        , testProperty "Hash round-trip" prop_hashRoundtrip
        ]
    , testGroup "Algebraic Laws"
        [ testProperty "Left identity (Pure)" prop_coeffectLeftIdentity
        , testProperty "Right identity (Pure)" prop_coeffectRightIdentity
        , testProperty "Associativity" prop_coeffectAssociativity
        , testProperty "Pure is identity (combine)" prop_pureIsIdentity
        , testProperty "Network absorbed" prop_networkAbsorbed
        , testProperty "Pure identity both sides" prop_coeffectPureIdentity
        ]
    ]
