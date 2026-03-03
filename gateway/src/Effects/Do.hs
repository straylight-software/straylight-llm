{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE PolyKinds #-}
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
{-# OPTIONS_GHC -Wno-unused-imports #-}
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                                              // Effects.Do
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
-- QualifiedDo support for GatewayM.
--
-- Usage:
--
--     {-# LANGUAGE QualifiedDo #-}
--     import Effects.Do qualified as G
--
--     handleChat :: ChatRequest -> GatewayM '[Net, Auth, Crypto] ChatResponse
--     handleChat req = G.do
--       G.return ()                              -- Pure, no effect labels added
--       provider <- selectProvider req            -- Pure
--       response <- callUpstream provider req     -- '[Net, Auth]
--       proof    <- signResponse response         -- '[Crypto]
--       G.return (response, proof)                -- grade = Net ∪ Auth ∪ Crypto
--
-- Regular do-notation still works in the same module for IO/other monads.
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

module Effects.Do
  ( return
  , (>>=)
  , (>>)
  , fail
  ) where

import Prelude (String, error)
import Control.Effect (Effect)
import qualified Control.Effect as E
import Effects.Graded (GatewayM)
import Effects.Grade (GradeLabel, Union)

-- | Graded return. Grade: Pure ('[]). 
return :: a -> GatewayM '[] a
return = E.return

-- | Graded bind. Grade: Union f g.
(>>=) :: GatewayM f a -> (a -> GatewayM g b) -> GatewayM (Union f g) b
(>>=) = (E.>>=)

-- | Graded sequence. Grade: Union f g.
(>>) :: GatewayM f a -> GatewayM g b -> GatewayM (Union f g) b
(>>) = (E.>>)

-- | Graded fail. Bottom — graded monads have no meaningful failure.
fail :: String -> a
fail = error
