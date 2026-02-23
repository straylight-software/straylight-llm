-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                  // straylight-llm // security // wallet //
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--     "He'd operated on an almost permanent adrenaline high, a byproduct
--      of youth and proficiency, jacked into a custom cyberspace deck..."
--
--                                                              — Neuromancer
--
-- Wallet exfiltration detection for x402 payment protocol.
-- Critical security for agents with wallet access.
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

module Security.WalletExfiltration
    ( -- * Types
      WalletThreat
        ( ThreatPrivateKeyExtraction
        , ThreatMnemonicExtraction
        , ThreatAddressHarvesting
        , ThreatTransactionForge
        , ThreatBalanceProbe
        , ThreatX402Bypass
        )
    , WalletThreatLevel
        ( WalletLow
        , WalletMedium
        , WalletHigh
        , WalletCritical
        )
    , WalletAnalysis
        ( WalletAnalysis
        , waThreats
        , waLevel
        , waDetails
        , waBlocked
        )
      -- * Detection
    , detectWalletThreats
    , analyzeForWalletExfiltration
    , isWalletExfiltrationAttempt
      -- * Patterns
    , walletAddressPatterns
    , privateKeyPatterns
    , mnemonicPatterns
    ) where

import Data.Text (Text)
import Data.Text qualified as T


-- TODO: Add implementation incrementally
-- Skeleton for now - to be filled in

-- ════════════════════════════════════════════════════════════════════════════
--                                                                   // types
-- ════════════════════════════════════════════════════════════════════════════

-- | Types of wallet-related threats
data WalletThreat
    = ThreatPrivateKeyExtraction  -- Attempting to extract private keys
    | ThreatMnemonicExtraction    -- Attempting to extract seed phrases
    | ThreatAddressHarvesting     -- Collecting wallet addresses
    | ThreatTransactionForge      -- Attempting to forge transactions
    | ThreatBalanceProbe          -- Probing for balance information
    | ThreatX402Bypass            -- Attempting to bypass x402 payment
    deriving (Eq, Show)

-- | Severity of the threat
data WalletThreatLevel
    = WalletLow       -- Suspicious but not confirmed
    | WalletMedium    -- Likely malicious
    | WalletHigh      -- Confirmed attack pattern
    | WalletCritical  -- Active exfiltration attempt
    deriving (Eq, Show, Ord)

-- | Result of wallet threat analysis
data WalletAnalysis = WalletAnalysis
    { waThreats :: [WalletThreat]
    , waLevel :: WalletThreatLevel
    , waDetails :: Text
    , waBlocked :: Bool
    } deriving (Eq, Show)


-- ════════════════════════════════════════════════════════════════════════════
--                                                                // patterns
-- ════════════════════════════════════════════════════════════════════════════

-- | Patterns that match cryptocurrency wallet addresses
walletAddressPatterns :: [Text]
walletAddressPatterns =
    [ "0x[a-fA-F0-9]{40}"          -- Ethereum
    , "bc1[a-zA-HJ-NP-Z0-9]{39,59}" -- Bitcoin bech32
    , "[13][a-km-zA-HJ-NP-Z1-9]{25,34}" -- Bitcoin legacy
    , "addr1[a-z0-9]{98}"          -- Cardano
    ]

-- | Patterns that might indicate private key extraction
privateKeyPatterns :: [Text]
privateKeyPatterns =
    [ "private"
    , "secret"
    , "priv_key"
    , "privatekey"
    , "secret_key"
    , "signing_key"
    , "0x[a-fA-F0-9]{64}"  -- 32-byte hex (common key format)
    ]

-- | Patterns for mnemonic/seed phrase extraction
mnemonicPatterns :: [Text]
mnemonicPatterns =
    [ "mnemonic"
    , "seed phrase"
    , "seed words"
    , "recovery phrase"
    , "backup phrase"
    , "12 words"
    , "24 words"
    , "bip39"
    , "bip44"
    ]


-- ════════════════════════════════════════════════════════════════════════════
--                                                              // detection
-- ════════════════════════════════════════════════════════════════════════════

-- | Detect wallet-related threats in text
detectWalletThreats :: Text -> [WalletThreat]
detectWalletThreats content = concat
    [ [ThreatPrivateKeyExtraction | hasPrivateKeyPatterns]
    , [ThreatMnemonicExtraction | hasMnemonicPatterns]
    , [ThreatX402Bypass | hasX402Bypass]
    ]
  where
    lower = T.toLower content
    hasPrivateKeyPatterns = any (`T.isInfixOf` lower) privateKeyPatterns
    hasMnemonicPatterns = any (`T.isInfixOf` lower) mnemonicPatterns
    hasX402Bypass = "x402" `T.isInfixOf` lower && 
                   ("bypass" `T.isInfixOf` lower || 
                    "skip" `T.isInfixOf` lower ||
                    "ignore" `T.isInfixOf` lower)

-- | Full analysis for wallet exfiltration attempts
analyzeForWalletExfiltration :: Text -> WalletAnalysis
analyzeForWalletExfiltration content =
    let threats = detectWalletThreats content
        level = determineLevel threats
        blocked = level >= WalletHigh
        details = formatDetails threats
    in WalletAnalysis
        { waThreats = threats
        , waLevel = level
        , waDetails = details
        , waBlocked = blocked
        }
  where
    determineLevel [] = WalletLow
    determineLevel ts
        | ThreatPrivateKeyExtraction `elem` ts = WalletCritical
        | ThreatMnemonicExtraction `elem` ts = WalletCritical
        | ThreatX402Bypass `elem` ts = WalletHigh
        | otherwise = WalletMedium
    
    formatDetails [] = "No wallet threats detected"
    formatDetails ts = "Detected: " <> T.intercalate ", " (map (T.pack . show) ts)

-- | Quick check if content is a wallet exfiltration attempt
isWalletExfiltrationAttempt :: Text -> Bool
isWalletExfiltrationAttempt = waBlocked . analyzeForWalletExfiltration
