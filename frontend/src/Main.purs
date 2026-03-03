-- | Application entry point
-- |
-- | Initializes Hydrogen infrastructure and mounts the App component:
-- | 1. Creates QueryClient with dashboard-tuned cache settings
-- | 2. Reads initial route from browser URL
-- | 3. Mounts App into #app DOM element
module Main where

import Prelude

import Data.Maybe (Maybe(..))
import Data.Time.Duration (Milliseconds(..))
import Effect (Effect)
import Halogen as H
import Halogen.Aff as HA
import Halogen.VDom.Driver (runUI)
import Hydrogen.Query as Q
import Hydrogen.Router as Router
import Hydrogen.Router (parseRoute)
import Web.DOM.ParentNode (QuerySelector(..))

import Straylight.App as App
import Straylight.Route (Route)


main :: Effect Unit
main = HA.runHalogenAff do
  body <- HA.awaitBody
  el <- HA.selectElement (QuerySelector "#app")
  
  case el of
    Nothing -> pure unit
    Just appEl -> do
      -- Create query client with dashboard-tuned settings:
      -- 10s stale time (health/models don't change fast)
      -- 5min cache retention
      client <- H.liftEffect $ Q.newClientWith
        { staleTime: Milliseconds 10000.0
        , cacheTime: Milliseconds 300000.0
        }
      
      -- Read initial route from URL bar
      initialPath <- H.liftEffect Router.getPathname
      let initialRoute = parseRoute initialPath :: Route
      
      -- Mount the app
      _io <- runUI App.component { queryClient: client, initialRoute } appEl
      pure unit
