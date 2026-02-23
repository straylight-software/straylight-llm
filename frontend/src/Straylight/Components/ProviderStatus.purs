-- | Provider status dashboard component
-- | Displays real-time provider health and circuit breaker state
module Straylight.Components.ProviderStatus
  ( component
  , Input
  , ProviderInfo
  ) where

import Prelude

import Data.Array as Array
import Data.Maybe (Maybe(Nothing, Just))
import Effect.Aff.Class (class MonadAff)
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Properties as HP
import Straylight.Components.Icon as Icon


-- | Provider health information
type ProviderInfo =
  { name :: String
  , status :: String        -- "healthy" | "degraded" | "open"
  , circuitState :: String  -- "closed" | "open" | "half-open"
  , failureCount :: Int
  , lastSuccess :: Maybe String
  , lastFailure :: Maybe String
  }

type Input =
  { providers :: Maybe (Array ProviderInfo)
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
        [ Icon.icon "activity"
        , HH.span [ HP.class_ (H.ClassName "panel-title") ] [ HH.text "Provider Status" ]
        , case state.providers of
            Nothing -> HH.text ""
            Just ps -> HH.span [ HP.class_ (H.ClassName "panel-badge") ]
              [ HH.text $ show (Array.length ps) <> " providers" ]
        ]
    , HH.div [ HP.class_ (H.ClassName "panel-body") ]
        [ case state.providers of
            Nothing ->
              HH.div [ HP.class_ (H.ClassName "empty-state") ]
                [ HH.text "Connecting to event stream..." ]
            Just ps ->
              if Array.null ps
                then HH.div [ HP.class_ (H.ClassName "empty-state") ]
                  [ HH.text "No providers configured" ]
                else HH.div [ HP.class_ (H.ClassName "providers-grid") ]
                  (map renderProvider ps)
        ]
    ]

renderProvider :: forall w i. ProviderInfo -> HH.HTML w i
renderProvider p =
  HH.div [ HP.class_ (H.ClassName $ "provider-card " <> statusClass) ]
    [ HH.div [ HP.class_ (H.ClassName "provider-header") ]
        [ HH.div [ HP.class_ (H.ClassName $ "circuit-indicator " <> circuitClass) ] []
        , HH.div [ HP.class_ (H.ClassName "provider-name") ] [ HH.text p.name ]
        ]
    , HH.div [ HP.class_ (H.ClassName "provider-details") ]
        [ HH.div [ HP.class_ (H.ClassName "provider-stat") ]
            [ HH.span [ HP.class_ (H.ClassName "stat-label") ] [ HH.text "Circuit" ]
            , HH.span [ HP.class_ (H.ClassName "stat-value") ] [ HH.text circuitLabel ]
            ]
        , HH.div [ HP.class_ (H.ClassName "provider-stat") ]
            [ HH.span [ HP.class_ (H.ClassName "stat-label") ] [ HH.text "Failures" ]
            , HH.span [ HP.class_ (H.ClassName "stat-value") ] [ HH.text $ show p.failureCount ]
            ]
        ]
    , case p.lastFailure of
        Nothing -> HH.text ""
        Just ts -> HH.div [ HP.class_ (H.ClassName "provider-last-failure") ]
          [ HH.text $ "Last failure: " <> ts ]
    ]
  where
  statusClass = case p.status of
    "healthy" -> "healthy"
    "degraded" -> "degraded"
    "open" -> "error"
    _ -> ""
  circuitClass = case p.circuitState of
    "closed" -> "closed"
    "open" -> "open"
    "half-open" -> "half-open"
    _ -> ""
  circuitLabel = case p.circuitState of
    "closed" -> "Closed"
    "open" -> "Open"
    "half-open" -> "Half-Open"
    _ -> p.circuitState
