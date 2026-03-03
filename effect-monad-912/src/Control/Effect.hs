{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE TypeFamilies #-}

module Control.Effect (Effect (..), Subeffect (..), fail) where

import Data.Kind (Constraint, Type)
import Prelude hiding (Monad (..), fail)

-- | Specifies "parametric effect monads" which are essentially monads but
--     annotated by a type-level monoid formed by 'Plus' and 'Unit'
class Effect (m :: k -> Type -> Type) where
  -- | Effect of a trivially effectful computation |
  type Unit m :: k

  -- | Combining effects of two subcomputations |
  type Plus m (f :: k) (g :: k) :: k

  -- | 'Inv' provides a way to give instances of 'Effect' their own constraints for '>>='
  type Inv m (f :: k) (g :: k) :: Constraint

  type Inv m f g = ()

  -- | Effect-parameterised version of 'return'. Annotated with the 'Unit m' effect,
  --    denoting pure computation
  return :: a -> m (Unit m) a

  -- | Effect-parameterised version of '>>=' (bind). Combines
  --    two effect annotations 'f' and 'g' on its parameter computations into 'Plus'
  (>>=) :: (Inv m f g) => m f a -> (a -> m g b) -> m (Plus m f g) b

  (>>) :: (Inv m f g) => m f a -> m g b -> m (Plus m f g) b
  x >> y = x >>= (\_ -> y)

-- | Provided for RebindableSyntax: do-blocks with failable patterns need
--    a 'fail' in scope. This is intentionally bottom — graded monads have
--    no meaningful failure semantics by default.
fail :: String -> a
fail = error

-- | Specifies subeffecting behaviour
class Subeffect (m :: k -> Type -> Type) f g where
  sub :: m f a -> m g a
