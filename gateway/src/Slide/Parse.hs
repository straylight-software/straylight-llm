{-# LANGUAGE OverloadedStrings #-}

-- | SSE parsing for OpenAI-compatible endpoints
--
-- We use Megaparsec to surgically extract just the "content" field from 
-- OpenAI-format JSON. This avoids parsing 650 bytes of garbage we don't need.
--
-- Imported from: slide/src/Slide/Parse.hs
module Slide.Parse
  ( -- * SSE types
    SSEEvent (SSEData, SSEDone, SSERetry, SSEComment, SSEEmpty)
  
    -- * Parsing
  , parseSSE
  , parseSSELine
  
    -- * Content extraction
  , extractDelta
  , extractFinishReason
  ) where

import Control.Applicative ((<|>))
import Data.Text (Text)
import qualified Data.Text as T
import Data.Void (Void)
import Text.Megaparsec
  ( Parsec
  , anySingle
  , anySingleBut
  , choice
  , count
  , eof
  , errorBundlePretty
  , many
  , manyTill
  , optional
  , parse
  , some
  , takeWhileP
  , try
  )
import Text.Megaparsec.Char (char, digitChar, hexDigitChar, newline, space, string)

type Parser = Parsec Void Text

-- ════════════════════════════════════════════════════════════════════════════════
-- SSE Types
-- ════════════════════════════════════════════════════════════════════════════════

-- | Parsed SSE event
data SSEEvent
  = SSEData !Text        -- ^ data: line content
  | SSEDone              -- ^ [DONE] marker
  | SSERetry !Int        -- ^ retry: milliseconds
  | SSEComment !Text     -- ^ : comment
  | SSEEmpty             -- ^ empty line (event separator)
  deriving stock (Show, Eq)

-- ════════════════════════════════════════════════════════════════════════════════
-- SSE Parsing
-- ════════════════════════════════════════════════════════════════════════════════

-- | Parse SSE text into events
parseSSE :: Text -> Either String [SSEEvent]
parseSSE input = case parse parseSSEBlock "sse" input of
  Left parseError -> Left $ errorBundlePretty parseError
  Right events    -> Right events

-- | Parse single SSE line
parseSSELine :: Text -> Either String SSEEvent
parseSSELine input = case parse parseSingleSSELine "sse" input of
  Left parseError -> Left $ errorBundlePretty parseError
  Right event     -> Right event

parseSSEBlock :: Parser [SSEEvent]
parseSSEBlock = many parseSingleSSELine <* eof

parseSingleSSELine :: Parser SSEEvent
parseSingleSSELine = choice
  [ parseDoneMarker
  , parseDataLine
  , parseRetryLine
  , parseCommentLine
  , SSEEmpty <$ some newline
  ]

parseDoneMarker :: Parser SSEEvent
parseDoneMarker = SSEDone <$ string "data: [DONE]" <* optional newline

parseDataLine :: Parser SSEEvent
parseDataLine = do
  _ <- string "data: "
  content <- takeWhileP Nothing (/= '\n')
  _ <- optional newline
  pure $ SSEData content

parseRetryLine :: Parser SSEEvent
parseRetryLine = do
  _ <- string "retry: "
  digits <- some digitChar
  _ <- optional newline
  -- Using readMaybe pattern instead of partial read
  case reads digits of
    [(n, "")] -> pure $ SSERetry n
    _         -> pure $ SSERetry 0  -- Default on parse failure

parseCommentLine :: Parser SSEEvent
parseCommentLine = do
  _ <- char ':'
  content <- takeWhileP Nothing (/= '\n')
  _ <- optional newline
  pure $ SSEComment content

-- ════════════════════════════════════════════════════════════════════════════════
-- JSON Content Extraction
--
-- We DON'T use aeson for streaming. We use Megaparsec to surgically extract
-- just the "content" field from OpenAI-format JSON. This avoids parsing 650
-- bytes of garbage we don't need per token.
-- ════════════════════════════════════════════════════════════════════════════════

-- | Extract content delta from OpenAI-format JSON
extractDelta :: Text -> Maybe Text
extractDelta input = case parse parseContentField "json" input of
  Left _parseError -> Nothing
  Right maybeContent -> maybeContent

parseContentField :: Parser (Maybe Text)
parseContentField = do
  _ <- manyTill anySingle (try $ string "\"content\"")
  _ <- char ':'
  _ <- space
  choice
    [ Nothing <$ string "null"
    , Just <$> parseJSONString
    ]

-- | Extract finish_reason from OpenAI-format JSON
extractFinishReason :: Text -> Maybe Text
extractFinishReason input = case parse parseFinishReasonField "json" input of
  Left _parseError -> Nothing
  Right maybeReason -> maybeReason

parseFinishReasonField :: Parser (Maybe Text)
parseFinishReasonField = do
  _ <- manyTill anySingle (try $ string "\"finish_reason\"")
  _ <- char ':'
  _ <- space
  choice
    [ Nothing <$ string "null"
    , Just <$> parseJSONString
    ]

-- ════════════════════════════════════════════════════════════════════════════════
-- JSON String Parser
-- ════════════════════════════════════════════════════════════════════════════════

parseJSONString :: Parser Text
parseJSONString = do
  _ <- char '"'
  characters <- manyTill parseStringCharacter (char '"')
  pure $ T.pack characters

parseStringCharacter :: Parser Char
parseStringCharacter = parseEscapedCharacter <|> anySingleBut '"'

parseEscapedCharacter :: Parser Char
parseEscapedCharacter = char '\\' *> choice
  [ '"'  <$ char '"'
  , '\\' <$ char '\\'
  , '/'  <$ char '/'
  , '\b' <$ char 'b'
  , '\f' <$ char 'f'
  , '\n' <$ char 'n'
  , '\r' <$ char 'r'
  , '\t' <$ char 't'
  , parseUnicodeEscape
  ]

parseUnicodeEscape :: Parser Char
parseUnicodeEscape = do
  _ <- char 'u'
  hexDigits <- count 4 hexDigitChar
  -- Using reads instead of partial read
  case reads ("0x" ++ hexDigits) of
    [(n, "")] -> pure $ toEnum n
    _         -> pure '\xFFFD'  -- Unicode replacement character on failure
