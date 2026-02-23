-- | Models panel component
module Straylight.Components.ModelsPanel
  ( component
  , Input
  ) where

import Prelude

import Data.Array as Array
import Data.Maybe (Maybe(Nothing, Just))
import Effect.Aff.Class (class MonadAff)
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Properties as HP
import Straylight.API.Client as Api
import Straylight.Components.Icon as Icon


type Input =
  { models :: Maybe Api.ModelList
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
        [ Icon.icon "list-checks"
        , HH.span [ HP.class_ (H.ClassName "panel-title") ] [ HH.text "Available Models" ]
        , case state.models of
            Nothing -> HH.text ""
            Just m -> HH.span [ HP.class_ (H.ClassName "panel-badge") ]
              [ HH.text $ show (Array.length m.data) <> " models" ]
        ]
    , HH.div [ HP.class_ (H.ClassName "panel-body") ]
        [ case state.models of
            Nothing ->
              HH.div [ HP.class_ (H.ClassName "empty-state") ]
                [ HH.text "No models loaded" ]
            Just m ->
              HH.div [ HP.class_ (H.ClassName "models-list") ]
                (map renderModel m.data)
        ]
    ]

renderModel :: forall w i. Api.Model -> HH.HTML w i
renderModel model =
  HH.div [ HP.class_ (H.ClassName "model-item") ]
    [ HH.div [ HP.class_ (H.ClassName "model-id") ] [ HH.text model.id ]
    , HH.div [ HP.class_ (H.ClassName "model-meta") ]
        [ HH.span [ HP.class_ (H.ClassName "model-owner") ] [ HH.text model.ownedBy ]
        ]
    ]
