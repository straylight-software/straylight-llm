module Main where

import Prelude

import Data.Maybe (Maybe(..))
import Effect (Effect)
import Halogen.Aff as HA
import Halogen.VDom.Driver (runUI)
import Web.DOM.ParentNode (QuerySelector(..))
import Straylight.App as App

main :: Effect Unit
main = HA.runHalogenAff do
  HA.awaitLoad
  mel <- HA.selectElement (QuerySelector "#app")
  case mel of
    Nothing -> pure unit
    Just el -> void $ runUI App.component unit el
