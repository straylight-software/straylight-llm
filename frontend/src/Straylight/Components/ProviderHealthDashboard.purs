-- | Provider Health Dashboard — rich provider health view with latency percentiles
-- |
-- | Uses the /v1/admin/dashboard endpoint for aggregated health data including
-- | latency percentiles, error rates, and health scores.
module Straylight.Components.ProviderHealthDashboard
  ( component
  , Input
  ) where

import Prelude

import Data.Maybe (Maybe(..), fromMaybe)
import Effect.Aff.Class (class MonadAff)
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Properties as HP
import Hydrogen.Data.Format as Fmt
import Hydrogen.Query as Q
import Straylight.API.Client as Api
import Straylight.Components.Icon as Icon
import Straylight.Components.UI as UI
import Unsafe.Coerce (unsafeCoerce)


type Input =
  { dashboard :: Q.QueryState String Api.DashboardResponse
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
        , HH.span [ HP.class_ (H.ClassName "panel-title") ] [ HH.text "Provider Health" ]
        ]
    , HH.div [ HP.class_ (H.ClassName "panel-body") ]
        [ UI.renderQuery "Loading dashboard..." renderDashboard state.dashboard ]
    ]

renderDashboard :: forall w i. Api.DashboardResponse -> HH.HTML w i
renderDashboard dashWrapped =
  let dash = Api.unwrapDashboardResponse dashWrapped
  in HH.div [ HP.class_ (H.ClassName "health-dashboard") ]
    [ renderSummary dashWrapped
    , HH.div [ HP.class_ (H.ClassName "providers-grid") ]
        (map renderProviderHealth dash.providers)
    ]

renderSummary :: forall w i. Api.DashboardResponse -> HH.HTML w i
renderSummary dashWrapped =
  let dash = Api.unwrapDashboardResponse dashWrapped
  in HH.div [ HP.class_ (H.ClassName "dashboard-summary") ]
    [ summaryCard "Total Requests" (show dash.total_requests) "hash"
    , summaryCard "Active" (show dash.active_requests) "loader"
    , summaryCard "Uptime" (formatUptime dash.uptime_seconds) "clock"
    , case dash.cache_hit_rate of
        Nothing -> HH.text ""
        Just rate -> summaryCard "Cache Hit" (Fmt.formatPercent rate) "database"
    ]

summaryCard :: forall w i. String -> String -> String -> HH.HTML w i
summaryCard label value iconName =
  HH.div [ HP.class_ (H.ClassName "summary-card") ]
    [ HH.div [ HP.class_ (H.ClassName "summary-icon") ] [ Icon.iconSm iconName ]
    , HH.div [ HP.class_ (H.ClassName "summary-content") ]
        [ HH.div [ HP.class_ (H.ClassName "summary-value mono") ] [ HH.text value ]
        , HH.div [ HP.class_ (H.ClassName "summary-label") ] [ HH.text label ]
        ]
    ]

renderProviderHealth :: forall w i. Api.ProviderHealth -> HH.HTML w i
renderProviderHealth phWrapped =
  let ph = Api.unwrapProviderHealth phWrapped
  in HH.div [ HP.class_ (H.ClassName $ "provider-health-card " <> healthClass) ]
    [ HH.div [ HP.class_ (H.ClassName "provider-health-header") ]
        [ HH.div [ HP.class_ (H.ClassName $ "health-indicator " <> healthClass) ]
            [ HH.text $ show (round ph.health_score) ]
        , HH.div [ HP.class_ (H.ClassName "provider-name") ] [ HH.text ph.name ]
        , HH.div [ HP.class_ (H.ClassName $ "circuit-badge " <> circuitClass) ]
            [ HH.text circuitLabel ]
        ]
    , HH.div [ HP.class_ (H.ClassName "provider-health-stats") ]
        [ statRow "Requests" (show ph.request_count) ""
        , statRow "Errors" (show ph.error_count) (if ph.error_count > 0 then "error" else "")
        , statRow "Error Rate" (Fmt.formatPercent ph.error_rate) (errorRateClass ph.error_rate)
        ]
    , HH.div [ HP.class_ (H.ClassName "provider-latency") ]
        [ HH.div [ HP.class_ (H.ClassName "latency-header") ] [ HH.text "Latency (ms)" ]
        , HH.div [ HP.class_ (H.ClassName "latency-bars") ]
            [ latencyBar "avg" (fromMaybe 0.0 ph.latency_avg_ms)
            , latencyBar "p50" (fromMaybe 0.0 ph.latency_p50_ms)
            , latencyBar "p95" (fromMaybe 0.0 ph.latency_p95_ms)
            , latencyBar "p99" (fromMaybe 0.0 ph.latency_p99_ms)
            ]
        ]
    , HH.div [ HP.class_ (H.ClassName "provider-ttft") ]
        [ HH.div [ HP.class_ (H.ClassName "latency-header") ] [ HH.text "TTFT (ms)" ]
        , HH.div [ HP.class_ (H.ClassName "latency-bars") ]
            [ ttftBar "avg" (fromMaybe 0.0 ph.ttft_avg_ms)
            , ttftBar "p50" (fromMaybe 0.0 ph.ttft_p50_ms)
            , ttftBar "p95" (fromMaybe 0.0 ph.ttft_p95_ms)
            , ttftBar "p99" (fromMaybe 0.0 ph.ttft_p99_ms)
            ]
        ]
    , case ph.last_error of
        Nothing -> HH.text ""
        Just err -> HH.div [ HP.class_ (H.ClassName "provider-last-error") ]
            [ Icon.iconSm "alert-triangle"
            , HH.text err
            ]
    ]
  where
  ph = Api.unwrapProviderHealth phWrapped
  
  healthClass
    | ph.health_score >= 80.0 = "healthy"
    | ph.health_score >= 50.0 = "degraded"
    | otherwise = "unhealthy"
  
  circuitClass = case ph.circuit_state of
    Api.CBClosed -> "closed"
    Api.CBOpen -> "open"
    Api.CBHalfOpen -> "half-open"
  
  circuitLabel = case ph.circuit_state of
    Api.CBClosed -> "Closed"
    Api.CBOpen -> "Open"
    Api.CBHalfOpen -> "Half-Open"

statRow :: forall w i. String -> String -> String -> HH.HTML w i
statRow label value extraClass =
  HH.div [ HP.class_ (H.ClassName "stat-row") ]
    [ HH.span [ HP.class_ (H.ClassName "stat-label") ] [ HH.text label ]
    , HH.span [ HP.class_ (H.ClassName $ "stat-value mono " <> extraClass) ] [ HH.text value ]
    ]

latencyBar :: forall w i. String -> Number -> HH.HTML w i
latencyBar label valueMs =
  HH.div [ HP.class_ (H.ClassName "latency-item") ]
    [ HH.span [ HP.class_ (H.ClassName "latency-label") ] [ HH.text label ]
    , HH.div [ HP.class_ (H.ClassName "latency-bar-container") ]
        [ HH.div 
            [ HP.class_ (H.ClassName $ "latency-bar " <> latencyClass)
            , HP.style $ "width: " <> show (min 100.0 (valueMs / 10.0)) <> "%"
            ]
            []
        ]
    , HH.span [ HP.class_ (H.ClassName "latency-value mono") ] 
        [ HH.text $ show (round valueMs) ]
    ]
  where
  latencyClass
    | valueMs <= 100.0 = "fast"
    | valueMs <= 500.0 = "medium"
    | otherwise = "slow"

-- | Render a TTFT bar with appropriate thresholds for time-to-first-token
-- | TTFT is typically faster than total latency, so thresholds are tighter
ttftBar :: forall w i. String -> Number -> HH.HTML w i
ttftBar label valueMs =
  HH.div [ HP.class_ (H.ClassName "latency-item ttft-item") ]
    [ HH.span [ HP.class_ (H.ClassName "latency-label") ] [ HH.text label ]
    , HH.div [ HP.class_ (H.ClassName "latency-bar-container") ]
        [ HH.div 
            [ HP.class_ (H.ClassName $ "latency-bar ttft-bar " <> ttftClass)
            , HP.style $ "width: " <> show (min 100.0 (valueMs / 5.0)) <> "%"
            ]
            []
        ]
    , HH.span [ HP.class_ (H.ClassName "latency-value mono") ] 
        [ HH.text $ show (round valueMs) ]
    ]
  where
  -- TTFT thresholds: <50ms fast, <200ms medium, >200ms slow
  ttftClass
    | valueMs <= 50.0 = "fast"
    | valueMs <= 200.0 = "medium"
    | otherwise = "slow"

errorRateClass :: Number -> String
errorRateClass r
  | r > 0.1 = "error-high"
  | r > 0.05 = "error-med"
  | otherwise = ""

formatUptime :: Number -> String
formatUptime seconds =
  let days = toInt (seconds / 86400.0)
      hours = toInt ((seconds - toNumber days * 86400.0) / 3600.0)
      mins = toInt ((seconds - toNumber days * 86400.0 - toNumber hours * 3600.0) / 60.0)
  in if days > 0
       then show days <> "d " <> show hours <> "h"
       else if hours > 0
         then show hours <> "h " <> show mins <> "m"
         else show mins <> "m"

-- | Convert Number to Int by truncating
toInt :: Number -> Int
toInt = unsafeCoerce

-- | Convert Int to Number
toNumber :: Int -> Number
toNumber = unsafeCoerce

-- | Round Number to nearest Int
round :: Number -> Int
round n = toInt (n + 0.5)
