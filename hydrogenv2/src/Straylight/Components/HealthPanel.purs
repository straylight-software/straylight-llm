-- | Health status panel — gateway health, version, architecture info
module Straylight.Components.HealthPanel
  ( component
  , Input
  ) where

import Prelude

import Effect.Aff.Class (class MonadAff)
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Properties as HP
import Hydrogen.Query as Q
import Straylight.API.Client as Api
import Straylight.Components.Icon as Icon
import Straylight.Components.UI as UI


type Input = { health :: Q.QueryState String Api.HealthResponse }
type State = Input

data Action = Receive Input

component :: forall q o m. MonadAff m => H.Component q Input o m
component = H.mkComponent
  { initialState: identity
  , render
  , eval: H.mkEval H.defaultEval
      { handleAction = \(Receive i) -> H.put i
      , receive = Just <<< Receive
      }
  }

render :: forall m. State -> H.ComponentHTML Action () m
render state =
  HH.div [ HP.class_ (H.ClassName "dashboard-panel") ]
    [ HH.div [ HP.class_ (H.ClassName "panel-header") ]
        [ Icon.icon "gauge"
        , HH.span [ HP.class_ (H.ClassName "panel-title") ] [ HH.text "Gateway Health" ]
        , if state.health.isFetching && Q.hasData state.health
            then UI.loadingInline
            else HH.text ""
        ]
    , HH.div [ HP.class_ (H.ClassName "panel-body") ]
        [ UI.renderQuery "Checking gateway health..." renderHealth state.health ]
    ]

renderHealth :: forall w i. Api.HealthResponse -> HH.HTML w i
renderHealth h =
  HH.div [ HP.class_ (H.ClassName "health-grid") ]
    [ statusCard "success" "Status" h.status
    , infoCard "Version" h.version true
    , infoCard "Architecture" "aleph cube" false
    , infoCard "Effects" "GatewayM graded monad" false
    ]
  where
  statusCard cls label val =
    HH.div [ HP.class_ (H.ClassName $ "status-card " <> cls) ]
      [ HH.div [ HP.class_ (H.ClassName $ "status-indicator " <> cls) ] []
      , HH.div [ HP.class_ (H.ClassName "status-text") ]
          [ HH.div [ HP.class_ (H.ClassName "status-label") ] [ HH.text label ]
          , HH.div [ HP.class_ (H.ClassName "status-value") ] [ HH.text val ]
          ]
      ]
  infoCard label val isMono =
    HH.div [ HP.class_ (H.ClassName "status-card") ]
      [ HH.div [ HP.class_ (H.ClassName "status-text") ]
          [ HH.div [ HP.class_ (H.ClassName "status-label") ] [ HH.text label ]
          , HH.div [ HP.class_ (H.ClassName $ "status-value" <> if isMono then " mono" else "") ]
              [ HH.text val ]
          ]
      ]
