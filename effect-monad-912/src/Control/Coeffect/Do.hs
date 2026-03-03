{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE ImportQualifiedPost #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE TypeFamilies #-}

-- | QualifiedDo-style support for coeffect comonads.
--
-- Usage with @comonadic@ style (if you define a @do@-like combinator):
--
-- @
-- {-\# LANGUAGE QualifiedDo \#-}
-- import Control.Coeffect.Do qualified as C
-- @
--
-- Since Haskell has no built-in comonadic @do@-notation, this module
-- primarily provides a consistent qualified namespace for 'extract'
-- and 'extend', paralleling "Control.Effect.Do".
module Control.Coeffect.Do
  ( extract,
    extend,
  )
where

import Control.Coeffect qualified as C
import Prelude ()

-- | Re-export coeffect 'extract'.
extract :: (C.Coeffect c) => c (C.Unit c) a -> a
extract = C.extract

-- | Re-export coeffect 'extend'.
extend :: (C.Coeffect c, C.Inv c s t) => (c t a -> b) -> c (C.Plus c s t) a -> c s b
extend = C.extend
