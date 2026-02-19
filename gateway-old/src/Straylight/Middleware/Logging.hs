{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

{- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                                                      // straylight // logging
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ -}

{- |
   Structured request/response logging.
-}
module Straylight.Middleware.Logging
  ( -- // logging // functions
    logRequest
  , logResponse
  , logInfo
  , logError
  , logDebug
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import Data.Time.Clock (UTCTime, getCurrentTime)
import Data.Time.Format.ISO8601 (iso8601Show)
import System.IO (hFlush, stdout, stderr)

import Straylight.Config


{- ════════════════════════════════════════════════════════════════════════════════
                                                        // logging // output
   ════════════════════════════════════════════════════════════════════════════════ -}

-- | Log a request
logRequest :: LogLevel -> Text -> Text -> Text -> IO ()
logRequest level method path clientIp = do
  when' (level >= LogInfo) $ do
    now <- getCurrentTime
    TIO.putStrLn $ formatLog now "INFO" $
      "→ " <> method <> " " <> path <> " from " <> clientIp
    hFlush stdout

-- | Log a response
logResponse :: LogLevel -> Text -> Int -> Double -> IO ()
logResponse level path status latencyMs = do
  when' (level >= LogInfo) $ do
    now <- getCurrentTime
    TIO.putStrLn $ formatLog now "INFO" $
      "← " <> path <> " " <> T.pack (show status) <> " in " <> T.pack (show latencyMs) <> "ms"
    hFlush stdout

-- | Log an info message
logInfo :: LogLevel -> Text -> IO ()
logInfo level msg = do
  when' (level >= LogInfo) $ do
    now <- getCurrentTime
    TIO.putStrLn $ formatLog now "INFO" msg
    hFlush stdout

-- | Log an error message
logError :: LogLevel -> Text -> IO ()
logError level msg = do
  when' (level >= LogError) $ do
    now <- getCurrentTime
    TIO.hPutStrLn stderr $ formatLog now "ERROR" msg
    hFlush stderr

-- | Log a debug message
logDebug :: LogLevel -> Text -> IO ()
logDebug level msg = do
  when' (level >= LogDebug) $ do
    now <- getCurrentTime
    TIO.putStrLn $ formatLog now "DEBUG" msg
    hFlush stdout


{- ════════════════════════════════════════════════════════════════════════════════
                                                        // formatting
   ════════════════════════════════════════════════════════════════════════════════ -}

-- | Format a log message
formatLog :: UTCTime -> Text -> Text -> Text
formatLog time level msg =
  T.pack (iso8601Show time) <> " [" <> level <> "] " <> msg

-- | Conditional execution helper
when' :: Bool -> IO () -> IO ()
when' True  action = action
when' False _      = pure ()
