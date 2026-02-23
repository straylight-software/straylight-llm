{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}

-- | Events and Operations for the evring state machine model.
--
-- An 'Event' is a completion from the kernel (what happened).
-- An 'Operation' is a request to the kernel (what to do).
--
-- The state machine processes Events and emits Operations:
--
-- @
--   step :: State -> Event -> (State, [Operation])
-- @
--
-- Imported from: libevring/hs/Evring/Event.hs
module Evring.Event
  ( -- * Events (completions from kernel)
    Event(..)
  , emptyEvent
    -- * Operations (requests to kernel)
  , Operation(..)
  , OperationType(..)
    -- * Handles
  , Handle
    -- * Parameters (simplified for gateway use)
  , OperationParams(..)
  ) where

import Data.ByteString (ByteString)
import Data.Int (Int64)
import Data.Word (Word64)
import GHC.Generics (Generic)

import Evring.Handle (Handle, invalidHandle)

-- ============================================================================
-- Events (completions from kernel)
-- ============================================================================

-- | An event: what happened (completion from the kernel).
data Event = Event
  { eventHandle   :: !Handle
    -- ^ Resource this event pertains to
  , eventType     :: !OperationType
    -- ^ What operation completed
  , eventResult   :: !Int64
    -- ^ Bytes transferred, fd for open/accept, or -errno
  , eventData     :: !ByteString
    -- ^ For reads: the data that was read
  , eventUserData :: !Word64
    -- ^ User-provided context for correlation
  } deriving stock (Eq, Show, Generic)

-- | Empty event, used to trigger initial operations in replay.
emptyEvent :: Event
emptyEvent = Event
  { eventHandle   = invalidHandle
  , eventType     = Nop
  , eventResult   = 0
  , eventData     = mempty
  , eventUserData = 0
  }

instance Semigroup Event where
  _ <> e = e

instance Monoid Event where
  mempty = emptyEvent

-- ============================================================================
-- Operation Types
-- ============================================================================

-- | Operation type enum (matches C++ evring::operation_type).
-- Simplified for gateway use - we mainly care about network operations.
data OperationType
  = Nop
  -- Network operations
  | Connect
  | Send
  | Recv
  | Timeout
  | Cancel
  -- Stream operations (for SIGIL)
  | StreamData
  | StreamEnd
  | StreamError
  deriving stock (Eq, Show, Enum, Bounded, Generic)

-- ============================================================================
-- Operations (requests to kernel)
-- ============================================================================

-- | An operation: request to the kernel (what to do).
data Operation = Operation
  { opHandle   :: !Handle
    -- ^ Resource this operation pertains to
  , opType     :: !OperationType
    -- ^ What operation to perform
  , opUserData :: !Word64
    -- ^ User-provided context for correlation
  , opParams   :: !OperationParams
    -- ^ Operation-specific parameters
  } deriving stock (Eq, Show, Generic)

-- | Operation-specific parameters (simplified for gateway).
data OperationParams
  = NoParams
  | ParamsData !ByteString
  | ParamsTimeout !Word64  -- nanoseconds
  deriving stock (Eq, Show, Generic)
