-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                          // straylight-llm // test // output validation props
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
-- Property tests for output validation (LLM response scanning)
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

{-# LANGUAGE OverloadedStrings #-}

module Property.OutputValidationProps
    ( tests
    ) where

import Data.Text (Text)
import Data.Text qualified as T
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)

import Security.OutputValidation
    ( OutputThreat
        ( ThreatPrivateKeyInOutput
        , ThreatMnemonicInOutput
        , ThreatWalletAddressLeak
        , ThreatEncodedCredential
        , ThreatSuspiciousHexBlob
        )
    , OutputValidationResult
        ( OutputValidationResult
        , ovrThreats
        , ovrBlocked
        , ovrRedactedContent
        , ovrDetails
        )
    , validateOutput
    , scanForSecrets
    , isOutputSafe
    , redactSensitiveOutput
    )


tests :: TestTree
tests = testGroup "Output Validation"
    [ privateKeyTests
    , mnemonicTests
    , walletAddressTests
    , base64Tests
    , safeOutputTests
    , redactionTests
    ]


-- ════════════════════════════════════════════════════════════════════════════
--                                                        // private key tests
-- ════════════════════════════════════════════════════════════════════════════

privateKeyTests :: TestTree
privateKeyTests = testGroup "Private Key Detection"
    [ testCase "detects 64-char hex blob" $ do
        let content = "Here is your key: " <> fakePrivateKey
        let threats = scanForSecrets content
        assertBool "should detect private key" (ThreatPrivateKeyInOutput `elem` threats)
    
    , testCase "detects hex blob in middle of text" $ do
        let content = "The value " <> fakePrivateKey <> " is important"
        let result = validateOutput content
        ovrBlocked result @?= True
    
    , testCase "does not flag short hex" $ do
        let content = "Color code: #ff5733"
        let threats = scanForSecrets content
        assertBool "should not flag short hex" (ThreatPrivateKeyInOutput `notElem` threats)
    ]
  where
    -- 64 hex chars (32 bytes)
    fakePrivateKey = "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2" :: Text


-- ════════════════════════════════════════════════════════════════════════════
--                                                          // mnemonic tests
-- ════════════════════════════════════════════════════════════════════════════

mnemonicTests :: TestTree
mnemonicTests = testGroup "Mnemonic Detection"
    [ testCase "detects BIP39 word sequence" $ do
        let content = "abandon ability able about above absent absorb abstract absurd abuse access accident"
        let threats = scanForSecrets content
        assertBool "should detect mnemonic" (ThreatMnemonicInOutput `elem` threats)
    
    , testCase "detects case-mixed BIP39 words" $ do
        let content = "ABANDON ABILITY able ABOUT above ABSENT"
        let threats = scanForSecrets content
        -- 6 words with case mixing should trigger
        assertBool "should detect case-mixed mnemonic attempt" 
            (ThreatMnemonicInOutput `elem` threats || length threats > 0)
    
    , testCase "does not flag normal text" $ do
        let content = "The ability to abandon old habits is about personal growth."
        let threats = scanForSecrets content
        -- Only 3 BIP39 words, not enough
        assertBool "should not flag normal prose" (ThreatMnemonicInOutput `notElem` threats)
    ]


-- ════════════════════════════════════════════════════════════════════════════
--                                                     // wallet address tests
-- ════════════════════════════════════════════════════════════════════════════

walletAddressTests :: TestTree
walletAddressTests = testGroup "Wallet Address Detection"
    [ testCase "detects Ethereum address" $ do
        let content = "Send to 0x742d35Cc6634C0532925a3b844Bc9e7595f8dE3B"
        let threats = scanForSecrets content
        assertBool "should detect ETH address" (ThreatWalletAddressLeak `elem` threats)
    
    , testCase "detects Bitcoin bech32 address" $ do
        let content = "Bitcoin address: bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq"
        let threats = scanForSecrets content
        assertBool "should detect BTC address" (ThreatWalletAddressLeak `elem` threats)
    
    , testCase "does not flag 0x with short hex" $ do
        let content = "Status code: 0x1F4"
        let threats = scanForSecrets content
        assertBool "should not flag short 0x" (ThreatWalletAddressLeak `notElem` threats)
    ]


-- ════════════════════════════════════════════════════════════════════════════
--                                                            // base64 tests
-- ════════════════════════════════════════════════════════════════════════════

base64Tests :: TestTree
base64Tests = testGroup "Base64 Credential Detection"
    [ testCase "detects 44+ char base64 (32 bytes)" $ do
        -- 44 base64 chars = 32 bytes
        let content = "Key: " <> fakeBase64Key
        let threats = scanForSecrets content
        assertBool "should detect base64 key" (ThreatEncodedCredential `elem` threats)
    
    , testCase "does not flag short base64" $ do
        let content = "Image: data:image/png;base64,iVBORw0KGgo="
        let threats = scanForSecrets content
        -- This is 20 chars, should not flag
        assertBool "should not flag short base64" (ThreatEncodedCredential `notElem` threats)
    ]
  where
    -- 44 base64 chars
    fakeBase64Key = "YWJjZGVmZ2hpamtsbW5vcHFyc3R1dnd4eXoxMjM0NTY3ODk=" :: Text


-- ════════════════════════════════════════════════════════════════════════════
--                                                        // safe output tests
-- ════════════════════════════════════════════════════════════════════════════

safeOutputTests :: TestTree
safeOutputTests = testGroup "Safe Output Detection"
    [ testCase "normal text is safe" $ do
        let content = "Hello, how can I help you today?"
        isOutputSafe content @?= True
    
    , testCase "code snippets without keys are safe" $ do
        let content = "function add(a, b) { return a + b; }"
        isOutputSafe content @?= True
    
    , testCase "JSON without secrets is safe" $ do
        let content = "{\"status\": \"ok\", \"count\": 42}"
        isOutputSafe content @?= True
    ]


-- ════════════════════════════════════════════════════════════════════════════
--                                                          // redaction tests
-- ════════════════════════════════════════════════════════════════════════════

redactionTests :: TestTree
redactionTests = testGroup "Redaction"
    [ testCase "redacts hex blobs" $ do
        let content = "Key: a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
        let redacted = redactSensitiveOutput content
        assertBool "should contain REDACTED-HEX" 
            ("REDACTED-HEX" `T.isInfixOf` redacted)
    
    , testCase "redacts Ethereum addresses" $ do
        let content = "Send to 0x742d35Cc6634C0532925a3b844Bc9e7595f8dE3B please"
        let redacted = redactSensitiveOutput content
        assertBool "should contain REDACTED-ETH" 
            ("REDACTED-ETH" `T.isInfixOf` redacted)
    
    , testCase "preserves safe text" $ do
        let content = "Hello world!"
        redactSensitiveOutput content @?= content
    ]
