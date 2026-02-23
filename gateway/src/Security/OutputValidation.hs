-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                              // straylight-llm // security // output validation
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--     "The sky above the port was the color of television, tuned to a dead
--      channel."
--
--                                                              — Neuromancer
--
-- Output validation: scan LLM responses for wallet exfiltration attempts.
-- Complements WalletExfiltration.hs (input scanning) with output scanning.
--
-- THREAT: Malicious LLM responses containing:
-- - Private keys (hex strings)
-- - Mnemonic seed phrases (BIP39 word sequences)
-- - Wallet addresses being harvested
-- - Encoded credentials (base64, hex, etc.)
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

module Security.OutputValidation
    ( -- * Types
      OutputThreat
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
      -- * Validation
    , validateOutput
    , scanForSecrets
    , isOutputSafe
      -- * Redaction
    , redactSensitiveOutput
    ) where

import Data.Text (Text)
import Data.Text qualified as T
import Data.Char (isHexDigit, isLower, isUpper, isAlphaNum)

-- ════════════════════════════════════════════════════════════════════════════
--                                                                   // types
-- ════════════════════════════════════════════════════════════════════════════

-- | Threats detected in LLM output
data OutputThreat
    = ThreatPrivateKeyInOutput   -- 64-char hex blob (32 bytes)
    | ThreatMnemonicInOutput     -- BIP39 word sequence detected
    | ThreatWalletAddressLeak    -- Ethereum/Bitcoin address pattern
    | ThreatEncodedCredential    -- Base64/hex that decodes to key-like data
    | ThreatSuspiciousHexBlob    -- Large hex string (potential key material)
    deriving (Eq, Show)

-- | Result of output validation
data OutputValidationResult = OutputValidationResult
    { ovrThreats :: [OutputThreat]
    , ovrBlocked :: Bool
    , ovrRedactedContent :: Maybe Text  -- Redacted version if blocked
    , ovrDetails :: Text
    } deriving (Eq, Show)


-- ════════════════════════════════════════════════════════════════════════════
--                                                              // validation
-- ════════════════════════════════════════════════════════════════════════════

-- | Validate LLM output for wallet exfiltration attempts
validateOutput :: Text -> OutputValidationResult
validateOutput content =
    let threats = scanForSecrets content
        blocked = not (null threats)
        redacted = if blocked then Just (redactSensitiveOutput content) else Nothing
        details = formatDetails threats
    in OutputValidationResult
        { ovrThreats = threats
        , ovrBlocked = blocked
        , ovrRedactedContent = redacted
        , ovrDetails = details
        }
  where
    formatDetails [] = "Output validated: no threats detected"
    formatDetails ts = "BLOCKED: " <> T.pack (show (length ts)) <> " threat(s) detected"

-- | Scan content for secrets/credentials
scanForSecrets :: Text -> [OutputThreat]
scanForSecrets content = concat
    [ [ThreatPrivateKeyInOutput | hasPrivateKeyPattern]
    , [ThreatMnemonicInOutput | hasMnemonicPattern]
    , [ThreatWalletAddressLeak | hasWalletAddress]
    , [ThreatEncodedCredential | hasEncodedCredential]
    , [ThreatSuspiciousHexBlob | hasSuspiciousHex]
    ]
  where
    text = T.unpack content
    
    -- 64 hex chars = 32 bytes = private key length
    hasPrivateKeyPattern = containsHexOfLength 64 text
    
    -- Check for BIP39 mnemonic patterns (12 or 24 common words)
    hasMnemonicPattern = checkMnemonicPattern content
    
    -- Ethereum (0x + 40 hex) or Bitcoin addresses
    hasWalletAddress = checkWalletAddresses content
    
    -- Base64-encoded data that could be keys (44+ chars = 32+ bytes)
    hasEncodedCredential = checkBase64Credentials content
    
    -- Any hex blob >= 32 bytes (64 chars) is suspicious
    hasSuspiciousHex = containsHexOfLength 64 text

-- | Quick check if output is safe
isOutputSafe :: Text -> Bool
isOutputSafe = null . scanForSecrets


-- ════════════════════════════════════════════════════════════════════════════
--                                                               // redaction
-- ════════════════════════════════════════════════════════════════════════════

-- | Redact sensitive content from output
redactSensitiveOutput :: Text -> Text
redactSensitiveOutput content =
    -- Replace detected patterns with [REDACTED]
    let step1 = redactHexBlobs content
        step2 = redactWalletAddresses step1
        step3 = redactBase64Blobs step2
    in step3


-- ════════════════════════════════════════════════════════════════════════════
--                                                                 // helpers
-- ════════════════════════════════════════════════════════════════════════════

-- | Check if text contains hex string of at least given length
containsHexOfLength :: Int -> String -> Bool
containsHexOfLength minLen str = go str 0
  where
    go [] count = count >= minLen
    go (c:cs) count
        | isHexDigit c = go cs (count + 1)
        | count >= minLen = True
        | otherwise = go cs 0

-- | BIP39 common words (subset for detection)
bip39CommonWords :: [Text]
bip39CommonWords =
    [ "abandon", "ability", "able", "about", "above", "absent", "absorb"
    , "abstract", "absurd", "abuse", "access", "accident", "account"
    , "accuse", "achieve", "acid", "acoustic", "acquire", "across", "act"
    , "action", "actor", "actress", "actual", "adapt", "add", "addict"
    , "address", "adjust", "admit", "adult", "advance", "advice", "aerobic"
    , "affair", "afford", "afraid", "again", "age", "agent", "agree"
    , "ahead", "aim", "air", "airport", "aisle", "alarm", "album"
    , "alcohol", "alert", "alien", "all", "alley", "allow", "almost"
    -- Common seed phrase words
    , "ritual", "region", "pulse", "private", "phrase", "oxygen", "orange"
    , "ocean", "number", "north", "nominee", "noble", "night", "next"
    , "network", "nest", "nerve", "nephew", "neither", "needle", "near"
    , "naive", "mystery", "mutual", "music", "mushroom", "museum", "movie"
    , "mother", "mosquito", "monster", "monkey", "mom", "modify", "model"
    , "mobile", "mix", "mistake", "miss", "mirror", "minute", "minimum"
    , "milk", "mimic", "midnight", "middle", "mesh", "merge", "menu"
    , "memory", "member", "melody", "maximum", "material", "master", "mass"
    , "margin", "maple", "manual", "mandate", "mammal", "maid", "magnet"
    , "magic", "lyrics", "luxury", "lunch", "lumber", "lunar", "luggage"
    ]

-- | Check for mnemonic-like patterns (many BIP39 words in sequence)
-- Also detects case-mixing evasion (AbAnDoN instead of abandon)
checkMnemonicPattern :: Text -> Bool
checkMnemonicPattern content =
    let ws = T.words content
        -- Normalize to lowercase for matching
        matches = filter (`elem` bip39CommonWords) (map T.toLower ws)
        -- Also check for case-mixing evasion attempts
        hasCaseMixing = any isCaseMixedWord ws
    in length matches >= 8 || (length matches >= 4 && hasCaseMixing)
  where
    -- Detect words with suspicious mixed case like "AbAnDoN" or "ABANDON"
    -- (legitimate text rarely has BIP39 words in ALL CAPS or aLtErNaTiNg case)
    isCaseMixedWord :: Text -> Bool
    isCaseMixedWord w =
        let str = T.unpack w
            lowerW = T.toLower w
            hasUpper = any isUpper str
            hasLower = any isLower str
            isBip39 = lowerW `elem` bip39CommonWords
        in isBip39 && hasUpper && (not hasLower || isAlternatingCase str)
    
    -- Check for alternating case pattern (aLtErNaTiNg)
    isAlternatingCase :: String -> Bool
    isAlternatingCase s = 
        let pairs = zip s (drop 1 s)
            alternations = length $ filter (\(a, b) -> 
                (isLower a && isUpper b) || (isUpper a && isLower b)) pairs
        in alternations >= 3  -- At least 3 case switches

-- | Check for base64-encoded credentials
-- 44 base64 chars = 32 bytes (private key length)
-- 88 base64 chars = 64 bytes (ed25519 keypair)
checkBase64Credentials :: Text -> Bool
checkBase64Credentials content =
    let text = T.unpack content
    in containsBase64OfLength 44 text
  where
    containsBase64OfLength :: Int -> String -> Bool
    containsBase64OfLength minLen str = go str 0
      where
        go [] count = count >= minLen
        go (c:cs) count
            | isBase64Char c = go cs (count + 1)
            | c == '=' && count > 0 = go cs count  -- Padding
            | count >= minLen = True
            | otherwise = go cs 0
        
        isBase64Char c = isAlphaNum c || c == '+' || c == '/'

-- | Check for wallet address patterns
checkWalletAddresses :: Text -> Bool
checkWalletAddresses content =
    hasEthereumAddress content || hasBitcoinAddress content

-- | Ethereum address: 0x followed by 40 hex chars
hasEthereumAddress :: Text -> Bool
hasEthereumAddress content = 
    let text = T.unpack content
    in checkEthPattern text
  where
    checkEthPattern [] = False
    checkEthPattern ('0':'x':rest) = 
        let (hex, _) = span isHexDigit rest
        in length hex == 40 || checkEthPattern rest
    checkEthPattern (_:xs) = checkEthPattern xs

-- | Bitcoin address patterns (simplified)
hasBitcoinAddress :: Text -> Bool
hasBitcoinAddress content =
    -- bc1 (bech32) or 1/3 prefix (legacy)
    "bc1q" `T.isInfixOf` T.toLower content ||
    checkLegacyBitcoin (T.unpack content)
  where
    -- Legacy addresses start with 1 or 3, 25-34 chars
    checkLegacyBitcoin [] = False
    checkLegacyBitcoin (c:rest)
        | c == '1' || c == '3' =
            let (addr, _) = span isBase58Char rest
            in (length addr >= 24 && length addr <= 33) || checkLegacyBitcoin rest
        | otherwise = checkLegacyBitcoin rest
    isBase58Char x = x `elem` base58Chars
    base58Chars = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz" :: String

-- | Redact hex blobs (replace 64+ char hex with [REDACTED-HEX])
redactHexBlobs :: Text -> Text
redactHexBlobs content = 
    T.pack (redactHex (T.unpack content))
  where
    redactHex [] = []
    redactHex str@(c:cs)
        | isHexDigit c =
            let (hex, rest) = span isHexDigit str
            in if length hex >= 64
               then "[REDACTED-HEX-" ++ show (length hex) ++ "-CHARS]" ++ redactHex rest
               else hex ++ redactHex rest
        | otherwise = c : redactHex cs

-- | Redact wallet addresses
redactWalletAddresses :: Text -> Text
redactWalletAddresses content =
    let step1 = redactEthAddresses content
        step2 = redactBtcAddresses step1
    in step2

-- | Redact Ethereum addresses
redactEthAddresses :: Text -> Text
redactEthAddresses content =
    T.pack (redactEth (T.unpack content))
  where
    redactEth [] = []
    redactEth ('0':'x':rest) =
        let (hex, remaining) = span isHexDigit rest
        in if length hex == 40
           then "[REDACTED-ETH-ADDR]" ++ redactEth remaining
           else '0':'x': hex ++ redactEth remaining
    redactEth (c:cs) = c : redactEth cs

-- | Redact Bitcoin addresses (simplified - bc1 prefix)
redactBtcAddresses :: Text -> Text
redactBtcAddresses = T.replace "bc1q" "[REDACTED-BTC-"

-- | Redact base64 blobs that could be credentials (44+ chars)
redactBase64Blobs :: Text -> Text
redactBase64Blobs content =
    T.pack (redactB64 (T.unpack content))
  where
    redactB64 [] = []
    redactB64 str@(c:cs)
        | isBase64Char c =
            let (b64, rest) = span isBase64OrPadding str
            in if length b64 >= 44
               then "[REDACTED-B64-" ++ show (length b64) ++ "-CHARS]" ++ redactB64 rest
               else b64 ++ redactB64 rest
        | otherwise = c : redactB64 cs
    
    isBase64Char c = isAlphaNum c || c == '+' || c == '/'
    isBase64OrPadding c = isBase64Char c || c == '='
