{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE ImportQualifiedPost #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE TypeFamilies #-}

-- | QualifiedDo support for graded monads.
--
-- Instead of @RebindableSyntax@ (which hijacks /all/ @do@-blocks in a module),
-- import this module qualified and use @QualifiedDo@:
--
-- @
-- {-\# LANGUAGE QualifiedDo \#-}
-- import Control.Effect.Do qualified as E
--
-- example :: Counter 2 Int
-- example = E.do
--   x <- tick 1
--   y <- tick 2
--   E.return (x + y)
-- @
--
-- Regular @do@-notation still works normally in the same module.
-- Both can coexist in the same function.
module Control.Effect.Do
  ( return,
    (>>=),
    (>>),
    fail,
  )
where

import Control.Effect qualified as E
import Prelude (String, error)

-- | Re-export graded 'return'.
return :: (E.Effect m) => a -> m (E.Unit m) a
return = E.return

-- | Re-export graded '>>='.
(>>=) :: (E.Effect m, E.Inv m f g) => m f a -> (a -> m g b) -> m (E.Plus m f g) b
(>>=) = (E.>>=)

-- | Re-export graded '>>'.
(>>) :: (E.Effect m, E.Inv m f g) => m f a -> m g b -> m (E.Plus m f g) b
(>>) = (E.>>)

-- | Graded monads have no meaningful failure. Bottom by default.
fail :: String -> a
fail = error
