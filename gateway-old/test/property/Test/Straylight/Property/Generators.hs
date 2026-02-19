{-# LANGUAGE OverloadedStrings #-}

{- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                                              // test // property // generators
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

   Hedgehog generators for property-based testing.
   n.b. uses realistic distributions to find real bugs
-}
module Test.Straylight.Property.Generators
  ( -- // resource // levels
    genResourceLevel
    -- // types
  , genRole
  , genContent
  , genChatMessage
  , genChatMessages
  , genTemperature
  , genTopP
  , genMaxTokens
  , genModel
    -- // requests
  , genChatRequest
  ) where

import qualified Data.Text as T
import Hedgehog
import qualified Hedgehog.Gen as Gen
import qualified Hedgehog.Range as Range

import Straylight.Coeffect
import Straylight.Types


{- ════════════════════════════════════════════════════════════════════════════════
                                                        // resource // levels
   ════════════════════════════════════════════════════════════════════════════════ -}

-- | Generate a random ResourceLevel
genResourceLevel :: Gen ResourceLevel
genResourceLevel = Gen.element [RLNone, RLRead, RLReadWrite]


{- ════════════════════════════════════════════════════════════════════════════════
                                                        // type // generators
   ════════════════════════════════════════════════════════════════════════════════ -}

-- | Generate a random Role with realistic distribution.
--   n.b. user and assistant are more common than system and tool
genRole :: Gen Role
genRole = Gen.frequency
  [ (10, pure RoleUser)
  , (10, pure RoleAssistant)
  , (3,  pure RoleSystem)
  , (1,  pure RoleTool)
  ]

-- | Generate text content
genContent :: Gen Content
genContent = ContentText <$> genMessageText

-- | Generate realistic message text
genMessageText :: Gen T.Text
genMessageText = Gen.choice
  [ -- Short messages (common in chat)
    Gen.text (Range.linear 1 50) Gen.unicode
    -- Medium messages
  , Gen.text (Range.linear 50 200) Gen.unicode
    -- Long messages (less common)
  , Gen.text (Range.linear 200 1000) Gen.unicode
    -- Edge cases
  , pure ""
  , pure " "
  , pure "\n\n\n"
  , Gen.text (Range.linear 1 10) Gen.unicodeAll  -- includes weird chars
  ]

-- | Generate a chat message with realistic structure
genChatMessage :: Gen ChatMessage
genChatMessage = do
  role <- genRole
  content <- Gen.maybe genContent
  name <- Gen.maybe (Gen.text (Range.linear 1 20) Gen.alphaNum)
  -- Tool call ID only for tool role
  toolCallId <- case role of
    RoleTool -> Gen.maybe (Gen.text (Range.linear 10 30) Gen.alphaNum)
    _        -> pure Nothing
  pure ChatMessage
    { msgRole = role
    , msgContent = content
    , msgName = name
    , msgToolCallId = toolCallId
    , msgToolCalls = Nothing  -- Complex, skip for now
    }

-- | Generate a list of chat messages with realistic conversation structure
genChatMessages :: Gen [ChatMessage]
genChatMessages = do
  -- Most conversations have 1-20 messages
  n <- Gen.int (Range.linear 1 20)
  -- Generate messages with proper role alternation
  genConversation n

genConversation :: Int -> Gen [ChatMessage]
genConversation 0 = pure []
genConversation n = do
  -- Start with optional system message
  hasSystem <- Gen.bool
  systemMsg <- if hasSystem
    then do
      content <- Gen.text (Range.linear 10 500) Gen.unicode
      pure [ChatMessage RoleSystem (Just (ContentText content)) Nothing Nothing Nothing]
    else pure []
  -- Generate user/assistant pairs
  remaining <- max 0 <$> pure (n - length systemMsg)
  pairs <- genMessagePairs (remaining `div` 2)
  -- Maybe end with user message
  endWithUser <- Gen.bool
  lastMsg <- if endWithUser && remaining > length pairs * 2
    then do
      content <- genMessageText
      pure [ChatMessage RoleUser (Just (ContentText content)) Nothing Nothing Nothing]
    else pure []
  pure $ systemMsg ++ pairs ++ lastMsg

genMessagePairs :: Int -> Gen [ChatMessage]
genMessagePairs 0 = pure []
genMessagePairs n = do
  userContent <- genMessageText
  assistantContent <- genMessageText
  let userMsg = ChatMessage RoleUser (Just (ContentText userContent)) Nothing Nothing Nothing
      assistantMsg = ChatMessage RoleAssistant (Just (ContentText assistantContent)) Nothing Nothing Nothing
  rest <- genMessagePairs (n - 1)
  pure $ userMsg : assistantMsg : rest


{- ════════════════════════════════════════════════════════════════════════════════
                                                        // parameter // generators
   ════════════════════════════════════════════════════════════════════════════════ -}

-- | Generate temperature (0.0 to 2.0)
genTemperature :: Gen Double
genTemperature = Gen.frequency
  [ (5, Gen.double (Range.linearFrac 0.0 0.5))   -- Low temp (focused)
  , (10, Gen.double (Range.linearFrac 0.5 1.0)) -- Normal range
  , (3, Gen.double (Range.linearFrac 1.0 1.5))  -- Higher creativity
  , (1, Gen.double (Range.linearFrac 1.5 2.0))  -- Very high (rare)
  , (2, pure 0.0)                                -- Edge: zero
  , (2, pure 1.0)                                -- Common default
  ]

-- | Generate top_p (0.0 to 1.0)
genTopP :: Gen Double
genTopP = Gen.frequency
  [ (10, Gen.double (Range.linearFrac 0.8 1.0)) -- Most common range
  , (3, Gen.double (Range.linearFrac 0.5 0.8))
  , (1, Gen.double (Range.linearFrac 0.0 0.5))
  , (2, pure 1.0)                                -- Common default
  ]

-- | Generate max_tokens
genMaxTokens :: Gen Int
genMaxTokens = Gen.frequency
  [ (5, Gen.int (Range.linear 1 100))           -- Short responses
  , (10, Gen.int (Range.linear 100 1000))       -- Medium
  , (5, Gen.int (Range.linear 1000 4096))       -- Long
  , (2, Gen.int (Range.linear 4096 16384))      -- Very long
  , (1, pure 1)                                  -- Edge: minimum
  ]

-- | Generate model name
genModel :: Gen T.Text
genModel = Gen.element
  [ "gpt-4"
  , "gpt-4-turbo"
  , "gpt-3.5-turbo"
  , "claude-3-opus"
  , "claude-3-sonnet"
  , "claude-3-haiku"
  , "mistral-large"
  , "llama-3-70b"
  ]


{- ════════════════════════════════════════════════════════════════════════════════
                                                        // request // generators
   ════════════════════════════════════════════════════════════════════════════════ -}

-- | Generate a complete chat request structure (as tuple since we don't have request type)
genChatRequest :: Gen (T.Text, [ChatMessage], Maybe Double, Maybe Double, Maybe Int, Bool)
genChatRequest = do
  model <- genModel
  messages <- genChatMessages
  temp <- Gen.maybe genTemperature
  topP <- Gen.maybe genTopP
  maxTokens <- Gen.maybe genMaxTokens
  stream <- Gen.bool
  pure (model, messages, temp, topP, maxTokens, stream)
