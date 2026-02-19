{- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                                                    // straylight // unit-tests
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ -}

module Main (main) where

import Test.Hspec

import qualified Test.Straylight.Coeffect as Coeffect
import qualified Test.Straylight.Config as Config
import qualified Test.Straylight.Router as Router
import qualified Test.Straylight.Types as Types


main :: IO ()
main = hspec $ do
  describe "Straylight.Coeffect" Coeffect.spec
  describe "Straylight.Config" Config.spec
  describe "Straylight.Router" Router.spec
  describe "Straylight.Types" Types.spec
