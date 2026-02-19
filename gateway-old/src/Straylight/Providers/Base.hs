{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

{- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                                                  // straylight // providers
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ -}

{- |
   "He'd found her, one rainy night, in an L.A. club called
    the Gentleman Loser. They'd gone back to her room, and
    she'd said he was like a clenched fist."

                                                               — Neuromancer

   Abstract provider interface and result types.
   n.b. corresponds to Lean4 Straylight.Provider.
-}
module Straylight.Providers.Base
  ( -- // result // types
    ProviderError (..)
  , ProviderResult (..)
    -- // constructors
  , mkProviderError
  , mkTimeoutError
  , mkConnectionError
    -- // queries
  , isRetryable
  , is4xx
  , is5xx
    -- // http // helpers
  , HttpManager
  , createHttpManager
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import qualified Network.HTTP.Client as HC
import qualified Network.HTTP.Client.TLS as TLS


{- ════════════════════════════════════════════════════════════════════════════════
                                                        // provider // error
   ════════════════════════════════════════════════════════════════════════════════ -}

-- | Provider error with retry information.
--   n.b. retryable determined by status code class
data ProviderError = ProviderError
  { peMessage    :: !Text
  , peStatusCode :: !Int
  , peRetryable  :: !Bool
  }
  deriving stock (Eq, Show)

-- | Check if status code is 4xx client error
is4xx :: Int -> Bool
is4xx code = code >= 400 && code < 500

-- | Check if status code is 5xx server error
is5xx :: Int -> Bool
is5xx code = code >= 500 && code < 600

-- | Construct provider error with automatic retry classification.
--   i.e. 5xx errors are retryable, 4xx are not
mkProviderError :: Text -> Int -> ProviderError
mkProviderError msg code = ProviderError
  { peMessage    = msg
  , peStatusCode = code
  , peRetryable  = is5xx code
  }

-- | Construct timeout error (retryable)
mkTimeoutError :: Text -> ProviderError
mkTimeoutError msg = ProviderError
  { peMessage    = msg
  , peStatusCode = 504
  , peRetryable  = True
  }

-- | Construct connection error (retryable)
mkConnectionError :: Text -> ProviderError
mkConnectionError msg = ProviderError
  { peMessage    = msg
  , peStatusCode = 503
  , peRetryable  = True
  }


{- ════════════════════════════════════════════════════════════════════════════════
                                                        // provider // result
   ════════════════════════════════════════════════════════════════════════════════ -}

-- | Result of a provider operation
data ProviderResult a
  = ProviderFailure !ProviderError
  | ProviderSuccess !a
  deriving stock (Eq, Show, Functor)

instance Applicative ProviderResult where
  pure = ProviderSuccess
  ProviderSuccess f <*> ProviderSuccess a = ProviderSuccess (f a)
  ProviderFailure e <*> _                 = ProviderFailure e
  _                 <*> ProviderFailure e = ProviderFailure e

instance Monad ProviderResult where
  ProviderSuccess a >>= f = f a
  ProviderFailure e >>= _ = ProviderFailure e

-- | Check if result is a retryable failure
isRetryable :: ProviderResult a -> Bool
isRetryable = \case
  ProviderSuccess _ -> False
  ProviderFailure e -> peRetryable e


{- ════════════════════════════════════════════════════════════════════════════════
                                                        // http // manager
   ════════════════════════════════════════════════════════════════════════════════ -}

-- | HTTP manager type alias
type HttpManager = HC.Manager

-- | Create HTTP manager with TLS support.
--   n.b. connection pooling enabled by default
createHttpManager :: Int -> IO HttpManager
createHttpManager timeoutSecs = HC.newManager $ TLS.tlsManagerSettings
  { HC.managerConnCount         = 10
  , HC.managerIdleConnectionCount = 5
  , HC.managerResponseTimeout   = HC.responseTimeoutMicro (timeoutSecs * 1000000)
  }
