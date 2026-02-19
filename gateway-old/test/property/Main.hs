{- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                                                // straylight // property-tests
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ -}

module Main (main) where

import Test.Hspec

import qualified Test.Straylight.Property.Coeffect as Coeffect
import qualified Test.Straylight.Property.Types as Types


main :: IO ()
main = hspec $ do
  describe "Property: Straylight.Coeffect" Coeffect.spec
  describe "Property: Straylight.Types" Types.spec
