-- | Models panel — available LLM models from the gateway
module Straylight.Components.ModelsPanel
  ( component
  , Input
  ) where

import Prelude

import Data.Array as Array
import Effect.Aff.Class (class MonadAff)
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Properties as HP
import Hydrogen.Query as Q
import Hydrogen.Data.RemoteData (RemoteData(..))
import Straylight.API.Client as Api
import Straylight.Components.Icon as Icon
import Straylight.Components.UI as UI


type Input = { models :: Q.QueryState String Api.ModelList }
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
        [ Icon.icon "list-checks"
        , HH.span [ HP.class_ (H.ClassName "panel-title") ] [ HH.text "Available Models" ]
        , case Q.getData state.models of
            Just m -> HH.span [ HP.class_ (H.ClassName "panel-badge") ]
              [ HH.text $ show (Array.length m.data) <> " models" ]
            Nothing -> HH.text ""
        , if state.models.isFetching && Q.hasData state.models
            then UI.loadingInline
            else HH.text ""
        ]
    , HH.div [ HP.class_ (H.ClassName "panel-body") ]
        [ UI.renderQueryWith
            { loading: UI.skeletonCards 4
            , failure: UI.errorPanel
            , success: renderModelList
            }
            state.models
        ]
    ]

renderModelList :: forall w i. Api.ModelList -> HH.HTML w i
renderModelList ml
  | Array.null ml.data =
      UI.emptyPanel "list-checks" "No models configured"
        "Add provider configurations to expose models through the gateway."
  | otherwise =
      HH.div [ HP.class_ (H.ClassName "models-list") ]
        (map renderModel ml.data)

renderModel :: forall w i. Api.Model -> HH.HTML w i
renderModel model =
  HH.div [ HP.class_ (H.ClassName "model-item") ]
    [ HH.div [ HP.class_ (H.ClassName "model-id mono") ] [ HH.text model.id ]
    , HH.div [ HP.class_ (H.ClassName "model-meta") ]
        [ HH.span [ HP.class_ (H.ClassName "model-owner") ] [ HH.text model.ownedBy ] ]
    ]
