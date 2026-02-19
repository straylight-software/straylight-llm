{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE UndecidableInstances #-}

{- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                                                     // straylight // coeffect
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ -}

{- |
   "The sky above the port was the color of television,
    tuned to a dead channel."

                                                               — Neuromancer

   Coeffect algebra for resource tracking in graded monads.
   n.b. corresponds to Lean4 Straylight.Coeffect with type-level encoding.

   The coeffect semiring (R, ⊔, 0, ⊓, 1) tracks resource usage:
   - ⊔ (join): parallel composition
   - ⊓ (meet): sequential composition
   - 0: no resource usage
   - 1: unit resource usage
-}
module Straylight.Coeffect
  ( -- // resource // levels
    ResourceLevel (..)
  , type RNone
  , type RRead
  , type RReadWrite
    -- // coeffect // type
  , Coeffect (..)
  , SCoeffect (..)
    -- // type-level // operations
  , type Join
  , type Meet
    -- // common // coeffects
  , type Pure
  , type NetRead
  , type NetReadWrite
  , type GpuInference
  , type LlmRequest
  , type ChatCompletions
  , type Models
  , type Health
    -- // term-level // witnesses
  , coeffectPure
  , coeffectNetRead
  , coeffectNetReadWrite
  , coeffectGpuInference
  , coeffectLlmRequest
  , coeffectChatCompletions
  , coeffectModels
  , coeffectHealth
    -- // JSON // encoding
  , coeffectToJson
  ) where

import Data.Aeson
import Data.Kind (Type)
import Data.Text (Text)
import GHC.Generics (Generic)
import GHC.TypeLits


{- ════════════════════════════════════════════════════════════════════════════════
                                                        // resource // levels
   ════════════════════════════════════════════════════════════════════════════════ -}

-- | Resource access level — type-level representation
data ResourceLevel
  = RLNone       -- ^ no access
  | RLRead       -- ^ read-only access
  | RLReadWrite  -- ^ read and write access
  deriving stock (Eq, Ord, Show, Generic)

instance ToJSON ResourceLevel where
  toJSON = \case
    RLNone      -> String "none"
    RLRead      -> String "read"
    RLReadWrite -> String "readWrite"

-- | Type-level resource levels
type RNone      = 'RLNone
type RRead      = 'RLRead
type RReadWrite = 'RLReadWrite


{- ════════════════════════════════════════════════════════════════════════════════
                                                        // type-level // join
   ════════════════════════════════════════════════════════════════════════════════ -}

-- | Type-level join (least upper bound) for resource levels
type family JoinRL (a :: ResourceLevel) (b :: ResourceLevel) :: ResourceLevel where
  JoinRL 'RLNone x = x
  JoinRL x 'RLNone = x
  JoinRL 'RLRead 'RLRead = 'RLRead
  JoinRL _ _ = 'RLReadWrite

-- | Type-level meet (greatest lower bound) for resource levels
type family MeetRL (a :: ResourceLevel) (b :: ResourceLevel) :: ResourceLevel where
  MeetRL 'RLReadWrite x = x
  MeetRL x 'RLReadWrite = x
  MeetRL 'RLRead 'RLRead = 'RLRead
  MeetRL _ _ = 'RLNone


{- ════════════════════════════════════════════════════════════════════════════════
                                                        // coeffect // type
   ════════════════════════════════════════════════════════════════════════════════ -}

-- | A coeffect is a mapping from resource kinds to usage levels.
--   Type-level representation for graded monads.
data Coeffect (cpu :: ResourceLevel)
              (gpu :: ResourceLevel)
              (mem :: ResourceLevel)
              (net :: ResourceLevel)
              (sto :: ResourceLevel)
  = MkCoeffect
  deriving stock (Eq, Show)

-- | Singleton witness for coeffects at term level
data SCoeffect (c :: Type) where
  SCoeffect :: ResourceLevel  -- cpu
            -> ResourceLevel  -- gpu
            -> ResourceLevel  -- memory
            -> ResourceLevel  -- network
            -> ResourceLevel  -- storage
            -> SCoeffect (Coeffect cpu gpu mem net sto)

deriving instance Show (SCoeffect c)


{- ════════════════════════════════════════════════════════════════════════════════
                                                        // type-level // operations
   ════════════════════════════════════════════════════════════════════════════════ -}

-- | Join of coeffects — parallel composition
type family Join (a :: Type) (b :: Type) :: Type where
  Join (Coeffect c1 g1 m1 n1 s1) (Coeffect c2 g2 m2 n2 s2) =
    Coeffect (JoinRL c1 c2) (JoinRL g1 g2) (JoinRL m1 m2) (JoinRL n1 n2) (JoinRL s1 s2)

-- | Meet of coeffects — sequential composition
type family Meet (a :: Type) (b :: Type) :: Type where
  Meet (Coeffect c1 g1 m1 n1 s1) (Coeffect c2 g2 m2 n2 s2) =
    Coeffect (MeetRL c1 c2) (MeetRL g1 g2) (MeetRL m1 m2) (MeetRL n1 n2) (MeetRL s1 s2)


{- ════════════════════════════════════════════════════════════════════════════════
                                                        // common // coeffects
   ════════════════════════════════════════════════════════════════════════════════ -}

-- | Pure computation — no external resources
type Pure = Coeffect RNone RNone RNone RNone RNone

-- | Network read operation
type NetRead = Coeffect RRead RNone RRead RRead RNone

-- | Network read/write operation
type NetReadWrite = Coeffect RRead RNone RRead RReadWrite RNone

-- | GPU inference operation
type GpuInference = Coeffect RRead RRead RRead RNone RNone

-- | Full LLM request — network + GPU
type LlmRequest = Join NetReadWrite GpuInference

-- | /v1/chat/completions endpoint
type ChatCompletions = Coeffect RRead RRead RRead RReadWrite RNone

-- | /v1/models endpoint
type Models = Coeffect RRead RNone RRead RNone RNone

-- | /health endpoint
type Health = Coeffect RRead RNone RRead RRead RNone


{- ════════════════════════════════════════════════════════════════════════════════
                                                        // term-level // witnesses
   ════════════════════════════════════════════════════════════════════════════════ -}

-- | Witness for pure coeffect
coeffectPure :: SCoeffect Pure
coeffectPure = SCoeffect RLNone RLNone RLNone RLNone RLNone

-- | Witness for network read
coeffectNetRead :: SCoeffect NetRead
coeffectNetRead = SCoeffect RLRead RLNone RLRead RLRead RLNone

-- | Witness for network read/write
coeffectNetReadWrite :: SCoeffect NetReadWrite
coeffectNetReadWrite = SCoeffect RLRead RLNone RLRead RLReadWrite RLNone

-- | Witness for GPU inference
coeffectGpuInference :: SCoeffect GpuInference
coeffectGpuInference = SCoeffect RLRead RLRead RLRead RLNone RLNone

-- | Witness for LLM request
coeffectLlmRequest :: SCoeffect LlmRequest
coeffectLlmRequest = SCoeffect RLRead RLRead RLRead RLReadWrite RLNone

-- | Witness for chat completions
coeffectChatCompletions :: SCoeffect ChatCompletions
coeffectChatCompletions = SCoeffect RLRead RLRead RLRead RLReadWrite RLNone

-- | Witness for models
coeffectModels :: SCoeffect Models
coeffectModels = SCoeffect RLRead RLNone RLRead RLNone RLNone

-- | Witness for health
coeffectHealth :: SCoeffect Health
coeffectHealth = SCoeffect RLRead RLNone RLRead RLRead RLNone


{- ════════════════════════════════════════════════════════════════════════════════
                                                        // json // encoding
   ════════════════════════════════════════════════════════════════════════════════ -}

-- | Convert a coeffect witness to JSON for the manifest
coeffectToJson :: SCoeffect c -> Value
coeffectToJson (SCoeffect cpu gpu mem net sto) = object
  [ "cpu"     .= cpu
  , "gpu"     .= gpu
  , "memory"  .= mem
  , "network" .= net
  , "storage" .= sto
  ]
