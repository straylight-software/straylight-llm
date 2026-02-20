-- | Health status panel component
module Straylight.Components.HealthStatus
  ( component
  , Input
  ) where

import Prelude

import Data.Maybe (Maybe(..))
import Effect.Aff.Class (class MonadAff)
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Properties as HP
import Straylight.API.Client as Api
import Straylight.Components.Icon as Icon


type Input =
  { health :: Maybe Api.HealthResponse
  }

type State = Input

component :: forall q o m. MonadAff m => H.Component q Input o m
component = H.mkComponent
  { initialState: identity
  , render
  , eval: H.mkEval H.defaultEval
  }

render :: forall m. State -> H.ComponentHTML Void () m
render state =
  HH.div [ HP.class_ (H.ClassName "dashboard-panel") ]
    [ HH.div [ HP.class_ (H.ClassName "panel-header") ]
        [ Icon.icon "gauge"
        , HH.span [ HP.class_ (H.ClassName "panel-title") ] [ HH.text "Gateway Health" ]
        ]
    , HH.div [ HP.class_ (H.ClassName "panel-body") ]
        [ case state.health of
            Nothing ->
              HH.div [ HP.class_ (H.ClassName "status-card error") ]
                [ HH.div [ HP.class_ (H.ClassName "status-indicator error") ] []
                , HH.div [ HP.class_ (H.ClassName "status-text") ]
                    [ HH.div [ HP.class_ (H.ClassName "status-label") ] [ HH.text "Status" ]
                    , HH.div [ HP.class_ (H.ClassName "status-value") ] [ HH.text "Disconnected" ]
                    ]
                ]
            Just h ->
              HH.div [ HP.class_ (H.ClassName "health-grid") ]
                [ HH.div [ HP.class_ (H.ClassName "status-card success") ]
                    [ HH.div [ HP.class_ (H.ClassName "status-indicator success") ] []
                    , HH.div [ HP.class_ (H.ClassName "status-text") ]
                        [ HH.div [ HP.class_ (H.ClassName "status-label") ] [ HH.text "Status" ]
                        , HH.div [ HP.class_ (H.ClassName "status-value") ] [ HH.text h.status ]
                        ]
                    ]
                , HH.div [ HP.class_ (H.ClassName "status-card") ]
                    [ HH.div [ HP.class_ (H.ClassName "status-text") ]
                        [ HH.div [ HP.class_ (H.ClassName "status-label") ] [ HH.text "Version" ]
                        , HH.div [ HP.class_ (H.ClassName "status-value mono") ] [ HH.text h.version ]
                        ]
                    ]
                , HH.div [ HP.class_ (H.ClassName "status-card") ]
                    [ HH.div [ HP.class_ (H.ClassName "status-text") ]
                        [ HH.div [ HP.class_ (H.ClassName "status-label") ] [ HH.text "Architecture" ]
                        , HH.div [ HP.class_ (H.ClassName "status-value") ] [ HH.text "aleph cube" ]
                        ]
                    ]
                , HH.div [ HP.class_ (H.ClassName "status-card") ]
                    [ HH.div [ HP.class_ (H.ClassName "status-text") ]
                        [ HH.div [ HP.class_ (H.ClassName "status-label") ] [ HH.text "Effects" ]
                        , HH.div [ HP.class_ (H.ClassName "status-value") ] [ HH.text "GatewayM graded monad" ]
                        ]
                    ]
                ]
        ]
    ]
