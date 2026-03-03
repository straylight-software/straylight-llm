-- | Provider status — real-time circuit breaker state from SSE
module Straylight.Components.ProvidersPanel
  ( component
  , Input
  , ProviderInfo
  ) where

import Prelude

import Data.Array as Array
import Data.Maybe (Maybe(..))
import Effect.Aff.Class (class MonadAff)
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Properties as HP
import Straylight.Components.Icon as Icon
import Straylight.Components.UI as UI
import Straylight.Streaming as Stream


type ProviderInfo =
  { name :: String
  , status :: String
  , circuitState :: String
  , failureCount :: Int
  , lastSuccess :: Maybe String
  , lastFailure :: Maybe String
  }

type Input =
  { providers :: Array ProviderInfo
  , connectionState :: Stream.ConnectionState
  }

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
        [ Icon.icon "activity"
        , HH.span [ HP.class_ (H.ClassName "panel-title") ] [ HH.text "Provider Status" ]
        , if not (Array.null state.providers)
            then HH.span [ HP.class_ (H.ClassName "panel-badge") ]
              [ HH.text $ show (Array.length state.providers) <> " providers" ]
            else HH.text ""
        ]
    , HH.div [ HP.class_ (H.ClassName "panel-body") ]
        [ if not (Array.null state.providers)
            then HH.div [ HP.class_ (H.ClassName "providers-grid") ]
              (map renderProvider state.providers)
            else renderEmpty state.connectionState
        ]
    ]

renderEmpty :: forall m. Stream.ConnectionState -> H.ComponentHTML Action () m
renderEmpty = case _ of
  Stream.Connecting -> UI.loadingPanel "Connecting to event stream..."
  Stream.Connected ->
    UI.emptyPanel "activity" "No providers yet"
      "Provider status appears as requests flow through the gateway."
  Stream.Reconnecting n ->
    UI.loadingPanel $ "Reconnecting... (attempt " <> show n <> ")"
  Stream.Disconnected ->
    UI.emptyPanel "activity" "Stream disconnected"
      "The SSE connection was lost. Provider data may be stale."
  Stream.Failed err ->
    UI.errorPanel $ "Event stream failed: " <> err

renderProvider :: forall w i. ProviderInfo -> HH.HTML w i
renderProvider p =
  HH.div [ HP.class_ (H.ClassName $ "provider-card " <> statusCls) ]
    [ HH.div [ HP.class_ (H.ClassName "provider-header") ]
        [ HH.div [ HP.class_ (H.ClassName $ "circuit-indicator " <> circuitCls) ] []
        , HH.div [ HP.class_ (H.ClassName "provider-name") ] [ HH.text p.name ]
        , HH.div [ HP.class_ (H.ClassName $ "provider-status-badge " <> statusCls) ]
            [ HH.text $ statusLabel p.status ]
        ]
    , HH.div [ HP.class_ (H.ClassName "provider-details") ]
        [ stat "Circuit" circuitLabel circuitCls
        , stat "Failures" (show p.failureCount) ""
        ]
    , timestamp "Last failure" p.lastFailure
    , timestamp "Last success" p.lastSuccess
    ]
  where
  statusCls = case p.status of
    "healthy" -> "healthy"
    "degraded" -> "degraded"
    _ -> "error"
  circuitCls = case p.circuitState of
    "CBClosed" -> "closed"
    "CBOpen" -> "open"
    "CBHalfOpen" -> "half-open"
    _ -> ""
  circuitLabel = case p.circuitState of
    "CBClosed" -> "Closed"
    "CBOpen" -> "Open"
    "CBHalfOpen" -> "Half-Open"
    _ -> p.circuitState
  statusLabel = case _ of
    "healthy" -> "Healthy"
    "degraded" -> "Degraded"
    "down" -> "Down"
    s -> s
  stat label val cls =
    HH.div [ HP.class_ (H.ClassName "provider-stat") ]
      [ HH.span [ HP.class_ (H.ClassName "stat-label") ] [ HH.text label ]
      , HH.span [ HP.class_ (H.ClassName $ "stat-value " <> cls) ] [ HH.text val ]
      ]
  timestamp label = case _ of
    Nothing -> HH.text ""
    Just ts -> HH.div [ HP.class_ (H.ClassName "provider-last-success") ]
      [ HH.text $ label <> ": " <> ts ]
