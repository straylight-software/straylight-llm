-- | Request timeline component
-- |
-- | Chronological view of gateway requests with filtering, pagination,
-- | and drill-down to request details including coeffects and retry history.
module Straylight.Components.RequestTimeline
  ( component
  , Input
  , Output(..)
  , ExportFormat(..)
  ) where

import Prelude

import Data.Array as Array
import Data.Int as Int
import Data.Maybe (Maybe(..), fromMaybe, isJust)
import Data.Number.Format (toStringWith, fixed)
import Data.String as String
import Effect.Aff.Class (class MonadAff, liftAff)
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Straylight.API.Client as Api
import Straylight.Components.Icon as Icon


-- ════════════════════════════════════════════════════════════════════════════
--                                                                     // types
-- ════════════════════════════════════════════════════════════════════════════

type Input =
  { requests :: Maybe Api.RequestsResponse
  , selectedRequest :: Maybe Api.RequestDetail
  , filter :: Api.RequestFilter
  }

-- | Output events for parent component
data Output
  = FilterChanged Api.RequestFilter
  | RequestSelected String
  | RefreshRequested
  | LoadMore
  | ExportRequested ExportFormat

data ExportFormat = ExportJSON | ExportCSV

type State =
  { requests :: Maybe Api.RequestsResponse
  , selectedRequest :: Maybe Api.RequestDetail
  , filter :: Api.RequestFilter
  , filterExpanded :: Boolean
  , detailExpanded :: Boolean
  , providerFilter :: String
  , modelFilter :: String
  , statusFilter :: String
  }

data Action
  = Receive Input
  | ToggleFilterExpanded
  | SetProviderFilter String
  | SetModelFilter String
  | SetStatusFilter String
  | ApplyFilters
  | ClearFilters
  | SelectRequest String
  | CloseDetail
  | RequestRefresh
  | RequestLoadMore
  | RequestExport ExportFormat
  | ToggleDetailSection String


-- ════════════════════════════════════════════════════════════════════════════
--                                                                 // component
-- ════════════════════════════════════════════════════════════════════════════

component :: forall q m. MonadAff m => H.Component q Input Output m
component = H.mkComponent
  { initialState
  , render
  , eval: H.mkEval H.defaultEval
      { handleAction = handleAction
      , receive = Just <<< Receive
      }
  }

initialState :: Input -> State
initialState input =
  { requests: input.requests
  , selectedRequest: input.selectedRequest
  , filter: input.filter
  , filterExpanded: false
  , detailExpanded: false
  , providerFilter: fromMaybe "" input.filter.provider
  , modelFilter: fromMaybe "" input.filter.model
  , statusFilter: ""
  }


-- ════════════════════════════════════════════════════════════════════════════
--                                                                    // render
-- ════════════════════════════════════════════════════════════════════════════

render :: forall m. State -> H.ComponentHTML Action () m
render state =
  HH.div [ HP.class_ (H.ClassName "dashboard-panel timeline-panel") ]
    [ renderHeader state
    , if state.filterExpanded then renderFilterBar state else HH.text ""
    , renderBody state
    , case state.selectedRequest of
        Just detail -> renderDetailModal detail state
        Nothing -> HH.text ""
    ]

renderHeader :: forall m. State -> H.ComponentHTML Action () m
renderHeader state =
  HH.div [ HP.class_ (H.ClassName "panel-header") ]
    [ HH.div [ HP.class_ (H.ClassName "panel-header-left") ]
        [ Icon.icon "list-checks"
        , HH.span [ HP.class_ (H.ClassName "panel-title") ] [ HH.text "Request Timeline" ]
        , case state.requests of
            Nothing -> HH.text ""
            Just r -> HH.span [ HP.class_ (H.ClassName "panel-badge") ]
              [ HH.text $ show r.total <> " total" ]
        ]
    , HH.div [ HP.class_ (H.ClassName "panel-header-right") ]
        [ HH.button 
            [ HP.classes $ map H.ClassName $ ["btn", "btn-sm"] 
                <> if state.filterExpanded then ["active"] else []
            , HE.onClick \_ -> ToggleFilterExpanded
            ]
            [ Icon.iconSm "settings"
            , HH.text "Filter"
            ]
        , HH.button 
            [ HP.class_ (H.ClassName "btn btn-sm")
            , HE.onClick \_ -> RequestRefresh
            ]
            [ Icon.iconSm "arrow-up"
            , HH.text "Refresh"
            ]
        , HH.button 
            [ HP.class_ (H.ClassName "btn btn-sm")
            , HE.onClick \_ -> RequestExport ExportJSON
            ]
            [ Icon.iconSm "folder"
            , HH.text "Export"
            ]
        ]
    ]

renderFilterBar :: forall m. State -> H.ComponentHTML Action () m
renderFilterBar state =
  HH.div [ HP.class_ (H.ClassName "filter-bar") ]
    [ HH.div [ HP.class_ (H.ClassName "filter-row") ]
        [ HH.div [ HP.class_ (H.ClassName "filter-group") ]
            [ HH.label [ HP.class_ (H.ClassName "filter-label") ] [ HH.text "Provider" ]
            , HH.input 
                [ HP.type_ HP.InputText
                , HP.class_ (H.ClassName "filter-input")
                , HP.placeholder "e.g. vertex, openrouter"
                , HP.value state.providerFilter
                , HE.onValueInput SetProviderFilter
                ]
            ]
        , HH.div [ HP.class_ (H.ClassName "filter-group") ]
            [ HH.label [ HP.class_ (H.ClassName "filter-label") ] [ HH.text "Model" ]
            , HH.input 
                [ HP.type_ HP.InputText
                , HP.class_ (H.ClassName "filter-input")
                , HP.placeholder "e.g. claude-3-opus"
                , HP.value state.modelFilter
                , HE.onValueInput SetModelFilter
                ]
            ]
        , HH.div [ HP.class_ (H.ClassName "filter-group") ]
            [ HH.label [ HP.class_ (H.ClassName "filter-label") ] [ HH.text "Status" ]
            , HH.select 
                [ HP.class_ (H.ClassName "filter-select")
                , HE.onValueChange SetStatusFilter
                ]
                [ HH.option [ HP.value "" ] [ HH.text "All" ]
                , HH.option [ HP.value "success" ] [ HH.text "Success" ]
                , HH.option [ HP.value "error" ] [ HH.text "Error" ]
                , HH.option [ HP.value "pending" ] [ HH.text "Pending" ]
                , HH.option [ HP.value "retrying" ] [ HH.text "Retrying" ]
                ]
            ]
        ]
    , HH.div [ HP.class_ (H.ClassName "filter-actions") ]
        [ HH.button 
            [ HP.class_ (H.ClassName "btn btn-sm btn-primary")
            , HE.onClick \_ -> ApplyFilters
            ]
            [ HH.text "Apply" ]
        , HH.button 
            [ HP.class_ (H.ClassName "btn btn-sm")
            , HE.onClick \_ -> ClearFilters
            ]
            [ HH.text "Clear" ]
        ]
    ]

renderBody :: forall m. State -> H.ComponentHTML Action () m
renderBody state =
  HH.div [ HP.class_ (H.ClassName "panel-body timeline-body") ]
    [ case state.requests of
        Nothing -> renderEmpty
        Just response -> 
          if Array.null response.requests
            then renderNoResults
            else renderRequestList state response
    ]

renderEmpty :: forall m. H.ComponentHTML Action () m
renderEmpty =
  HH.div [ HP.class_ (H.ClassName "empty-state") ]
    [ HH.div [ HP.class_ (H.ClassName "empty-icon") ] [ Icon.icon "list-checks" ]
    , HH.div [ HP.class_ (H.ClassName "empty-text") ] [ HH.text "No requests yet" ]
    , HH.div [ HP.class_ (H.ClassName "empty-subtext") ] 
        [ HH.text "Requests will appear here as they flow through the gateway" ]
    ]

renderNoResults :: forall m. H.ComponentHTML Action () m
renderNoResults =
  HH.div [ HP.class_ (H.ClassName "empty-state") ]
    [ HH.div [ HP.class_ (H.ClassName "empty-icon") ] [ Icon.icon "eye" ]
    , HH.div [ HP.class_ (H.ClassName "empty-text") ] [ HH.text "No matching requests" ]
    , HH.div [ HP.class_ (H.ClassName "empty-subtext") ] 
        [ HH.text "Try adjusting your filters" ]
    ]

renderRequestList :: forall m. State -> Api.RequestsResponse -> H.ComponentHTML Action () m
renderRequestList state response =
  HH.div [ HP.class_ (H.ClassName "request-list") ]
    [ HH.div [ HP.class_ (H.ClassName "request-list-header") ]
        [ HH.span [ HP.class_ (H.ClassName "col-time") ] [ HH.text "Time" ]
        , HH.span [ HP.class_ (H.ClassName "col-model") ] [ HH.text "Model" ]
        , HH.span [ HP.class_ (H.ClassName "col-provider") ] [ HH.text "Provider" ]
        , HH.span [ HP.class_ (H.ClassName "col-status") ] [ HH.text "Status" ]
        , HH.span [ HP.class_ (H.ClassName "col-latency") ] [ HH.text "Latency" ]
        , HH.span [ HP.class_ (H.ClassName "col-tokens") ] [ HH.text "Tokens" ]
        ]
    , HH.div [ HP.class_ (H.ClassName "request-list-body") ]
        (map renderRequestRow response.requests)
    , if hasMore response
        then renderLoadMore
        else HH.text ""
    ]

renderRequestRow :: forall m. Api.GatewayRequest -> H.ComponentHTML Action () m
renderRequestRow req =
  HH.div 
    [ HP.classes $ map H.ClassName ["request-row", statusRowClass req.status]
    , HE.onClick \_ -> SelectRequest req.requestId
    ]
    [ HH.span [ HP.class_ (H.ClassName "col-time mono") ] 
        [ HH.text $ formatTimestamp req.timestamp ]
    , HH.span [ HP.class_ (H.ClassName "col-model") ] 
        [ HH.text $ truncateModel req.model ]
    , HH.span [ HP.class_ (H.ClassName "col-provider") ] 
        [ HH.text req.provider ]
    , HH.span [ HP.class_ (H.ClassName $ "col-status " <> statusClass req.status) ] 
        [ HH.div [ HP.class_ (H.ClassName "status-badge") ]
            [ Icon.iconSm (statusIcon req.status)
            , HH.text $ statusLabel req.status
            ]
        ]
    , HH.span [ HP.class_ (H.ClassName "col-latency mono") ] 
        [ HH.text $ show req.latencyMs <> "ms" ]
    , HH.span [ HP.class_ (H.ClassName "col-tokens mono") ] 
        [ HH.text $ show (req.promptTokens + req.completionTokens) ]
    ]

renderLoadMore :: forall m. H.ComponentHTML Action () m
renderLoadMore =
  HH.div [ HP.class_ (H.ClassName "load-more") ]
    [ HH.button 
        [ HP.class_ (H.ClassName "btn")
        , HE.onClick \_ -> RequestLoadMore
        ]
        [ HH.text "Load More" ]
    ]


-- ════════════════════════════════════════════════════════════════════════════
--                                                              // detail modal
-- ════════════════════════════════════════════════════════════════════════════

renderDetailModal :: forall m. Api.RequestDetail -> State -> H.ComponentHTML Action () m
renderDetailModal detail state =
  HH.div [ HP.class_ (H.ClassName "modal-overlay") ]
    [ HH.div [ HP.class_ (H.ClassName "modal request-detail-modal") ]
        [ renderDetailHeader detail
        , renderDetailBody detail
        , renderDetailFooter detail
        ]
    ]

renderDetailHeader :: forall m. Api.RequestDetail -> H.ComponentHTML Action () m
renderDetailHeader detail =
  HH.div [ HP.class_ (H.ClassName "modal-header") ]
    [ HH.div [ HP.class_ (H.ClassName "modal-title") ]
        [ HH.text "Request Detail"
        , HH.span [ HP.class_ (H.ClassName $ "status-badge " <> statusClass detail.status) ]
            [ HH.text $ statusLabel detail.status ]
        ]
    , HH.button 
        [ HP.class_ (H.ClassName "modal-close")
        , HE.onClick \_ -> CloseDetail
        ]
        [ Icon.icon "x" ]
    ]

renderDetailBody :: forall m. Api.RequestDetail -> H.ComponentHTML Action () m
renderDetailBody detail =
  HH.div [ HP.class_ (H.ClassName "modal-body") ]
    [ -- Overview section
      HH.div [ HP.class_ (H.ClassName "detail-section") ]
        [ HH.div [ HP.class_ (H.ClassName "detail-section-header") ] 
            [ HH.text "Overview" ]
        , HH.div [ HP.class_ (H.ClassName "detail-grid") ]
            [ renderDetailItem "Request ID" detail.requestId true
            , renderDetailItem "Timestamp" detail.timestamp true
            , renderDetailItem "Model" detail.model false
            , renderDetailItem "Provider" detail.provider false
            , renderDetailItem "Latency" (show detail.latencyMs <> "ms") true
            , renderDetailItem "Prompt Tokens" (show detail.promptTokens) true
            , renderDetailItem "Completion Tokens" (show detail.completionTokens) true
            , renderDetailItem "Total Tokens" (show (detail.promptTokens + detail.completionTokens)) true
            ]
        ]
    
    -- Error message (if present)
    , case detail.errorMessage of
        Just err -> 
          HH.div [ HP.class_ (H.ClassName "detail-section error-section") ]
            [ HH.div [ HP.class_ (H.ClassName "detail-section-header") ] 
                [ HH.text "Error" ]
            , HH.div [ HP.class_ (H.ClassName "error-message") ]
                [ HH.code [] [ HH.text err ] ]
            ]
        Nothing -> HH.text ""
    
    -- Coeffects section
    , HH.div [ HP.class_ (H.ClassName "detail-section") ]
        [ HH.div [ HP.class_ (H.ClassName "detail-section-header") ] 
            [ HH.text "Coeffects"
            , HH.span [ HP.class_ (H.ClassName "badge") ]
                [ HH.text $ show (Array.length detail.coeffects) ]
            ]
        , HH.div [ HP.class_ (H.ClassName "coeffect-list") ]
            (map renderCoeffect detail.coeffects)
        ]
    
    -- Retry history (if present)
    , if Array.null detail.retryHistory
        then HH.text ""
        else HH.div [ HP.class_ (H.ClassName "detail-section") ]
          [ HH.div [ HP.class_ (H.ClassName "detail-section-header") ] 
              [ HH.text "Retry History"
              , HH.span [ HP.class_ (H.ClassName "badge") ]
                  [ HH.text $ show (Array.length detail.retryHistory) ]
              ]
          , HH.div [ HP.class_ (H.ClassName "retry-list") ]
              (map renderRetryAttempt detail.retryHistory)
          ]
    
    -- Request/Response bodies
    , HH.div [ HP.class_ (H.ClassName "detail-section") ]
        [ HH.div [ HP.class_ (H.ClassName "detail-section-header collapsible") ] 
            [ HH.text "Request Body" ]
        , HH.pre [ HP.class_ (H.ClassName "json-viewer") ]
            [ HH.code [] [ HH.text detail.requestBody ] ]
        ]
    
    , HH.div [ HP.class_ (H.ClassName "detail-section") ]
        [ HH.div [ HP.class_ (H.ClassName "detail-section-header collapsible") ] 
            [ HH.text "Response Body" ]
        , HH.pre [ HP.class_ (H.ClassName "json-viewer") ]
            [ HH.code [] [ HH.text detail.responseBody ] ]
        ]
    
    -- Proof link (if present)
    , case detail.proofId of
        Just proofId -> 
          HH.div [ HP.class_ (H.ClassName "detail-section") ]
            [ HH.div [ HP.class_ (H.ClassName "detail-section-header") ] 
                [ HH.text "Discharge Proof" ]
            , HH.div [ HP.class_ (H.ClassName "proof-link") ]
                [ Icon.iconSm "git-compare"
                , HH.span [ HP.class_ (H.ClassName "mono") ] [ HH.text proofId ]
                ]
            ]
        Nothing -> HH.text ""
    ]

renderDetailItem :: forall m. String -> String -> Boolean -> H.ComponentHTML Action () m
renderDetailItem label value isMono =
  HH.div [ HP.class_ (H.ClassName "detail-item") ]
    [ HH.span [ HP.class_ (H.ClassName "detail-label") ] [ HH.text label ]
    , HH.span [ HP.classes $ map H.ClassName $ ["detail-value"] <> if isMono then ["mono"] else [] ] 
        [ HH.text value ]
    ]

renderCoeffect :: forall m. Api.Coeffect -> H.ComponentHTML Action () m
renderCoeffect coeff =
  HH.div [ HP.class_ (H.ClassName "coeffect-badge") ]
    [ HH.text $ coeffectLabel coeff ]
  where
  coeffectLabel = case _ of
    Api.Pure -> "Pure"
    Api.Network -> "Network"
    Api.Auth p -> "Auth(" <> p <> ")"
    Api.Sandbox p -> "Sandbox(" <> p <> ")"
    Api.Filesystem p -> "Filesystem(" <> p <> ")"
    Api.Combined cs -> "Combined[" <> show (Array.length cs) <> "]"

renderRetryAttempt :: forall m. Api.RetryAttempt -> H.ComponentHTML Action () m
renderRetryAttempt attempt =
  HH.div [ HP.class_ (H.ClassName $ "retry-item " <> statusRowClass attempt.status) ]
    [ HH.div [ HP.class_ (H.ClassName "retry-main") ]
        [ HH.span [ HP.class_ (H.ClassName "retry-provider") ] [ HH.text attempt.provider ]
        , HH.span [ HP.class_ (H.ClassName $ "status-badge " <> statusClass attempt.status) ]
            [ HH.text $ statusLabel attempt.status ]
        ]
    , HH.div [ HP.class_ (H.ClassName "retry-meta") ]
        [ HH.span [ HP.class_ (H.ClassName "retry-latency mono") ] 
            [ HH.text $ show attempt.latencyMs <> "ms" ]
        , HH.span [ HP.class_ (H.ClassName "retry-time mono") ] 
            [ HH.text $ formatTimestamp attempt.timestamp ]
        ]
    , case attempt.errorMessage of
        Just err -> HH.div [ HP.class_ (H.ClassName "retry-error") ] 
            [ HH.text err ]
        Nothing -> HH.text ""
    ]

renderDetailFooter :: forall m. Api.RequestDetail -> H.ComponentHTML Action () m
renderDetailFooter detail =
  HH.div [ HP.class_ (H.ClassName "modal-footer") ]
    [ HH.button 
        [ HP.class_ (H.ClassName "btn")
        , HE.onClick \_ -> CloseDetail
        ]
        [ HH.text "Close" ]
    , HH.button 
        [ HP.class_ (H.ClassName "btn btn-primary")
        , HE.onClick \_ -> RequestExport ExportJSON
        ]
        [ Icon.iconSm "folder"
        , HH.text "Export JSON"
        ]
    ]


-- ════════════════════════════════════════════════════════════════════════════
--                                                                  // handlers
-- ════════════════════════════════════════════════════════════════════════════

handleAction :: forall m. MonadAff m => Action -> H.HalogenM State Action () Output m Unit
handleAction = case _ of
  Receive input -> do
    H.modify_ _ 
      { requests = input.requests
      , selectedRequest = input.selectedRequest
      , filter = input.filter
      }

  ToggleFilterExpanded ->
    H.modify_ \s -> s { filterExpanded = not s.filterExpanded }

  SetProviderFilter val ->
    H.modify_ _ { providerFilter = val }

  SetModelFilter val ->
    H.modify_ _ { modelFilter = val }

  SetStatusFilter val ->
    H.modify_ _ { statusFilter = val }

  ApplyFilters -> do
    state <- H.get
    let newFilter = state.filter
          { provider = if state.providerFilter == "" then Nothing else Just state.providerFilter
          , model = if state.modelFilter == "" then Nothing else Just state.modelFilter
          , status = parseStatus state.statusFilter
          , offset = 0  -- reset pagination
          }
    H.raise $ FilterChanged newFilter

  ClearFilters -> do
    H.modify_ _ 
      { providerFilter = ""
      , modelFilter = ""
      , statusFilter = ""
      }
    H.raise $ FilterChanged Api.defaultFilter

  SelectRequest requestId ->
    H.raise $ RequestSelected requestId

  CloseDetail ->
    H.modify_ _ { selectedRequest = Nothing }

  RequestRefresh ->
    H.raise RefreshRequested

  RequestLoadMore ->
    H.raise LoadMore

  RequestExport format ->
    H.raise $ ExportRequested format

  ToggleDetailSection _ ->
    pure unit  -- Could implement collapsible sections


-- ════════════════════════════════════════════════════════════════════════════
--                                                                   // helpers
-- ════════════════════════════════════════════════════════════════════════════

statusClass :: Api.RequestStatus -> String
statusClass = case _ of
  Api.Pending -> "status-pending"
  Api.Success -> "status-success"
  Api.Error -> "status-error"
  Api.Retrying -> "status-retrying"

statusRowClass :: Api.RequestStatus -> String
statusRowClass = case _ of
  Api.Pending -> "row-pending"
  Api.Success -> "row-success"
  Api.Error -> "row-error"
  Api.Retrying -> "row-retrying"

statusLabel :: Api.RequestStatus -> String
statusLabel = case _ of
  Api.Pending -> "Pending"
  Api.Success -> "Success"
  Api.Error -> "Error"
  Api.Retrying -> "Retrying"

statusIcon :: Api.RequestStatus -> String
statusIcon = case _ of
  Api.Pending -> "circle"
  Api.Success -> "check"
  Api.Error -> "x"
  Api.Retrying -> "arrow-up"

parseStatus :: String -> Maybe Api.RequestStatus
parseStatus = case _ of
  "pending" -> Just Api.Pending
  "success" -> Just Api.Success
  "error" -> Just Api.Error
  "retrying" -> Just Api.Retrying
  _ -> Nothing

hasMore :: Api.RequestsResponse -> Boolean
hasMore response = 
  response.offset + Array.length response.requests < response.total

formatTimestamp :: String -> String
formatTimestamp ts = 
  -- Extract time portion from ISO timestamp
  -- e.g., "2026-02-24T15:30:45Z" -> "15:30:45"
  case String.indexOf (String.Pattern "T") ts of
    Just idx -> 
      let timePart = String.drop (idx + 1) ts
      in String.take 8 timePart
    Nothing -> ts

truncateModel :: String -> String
truncateModel model = 
  if String.length model > 25 
    then String.take 22 model <> "..."
    else model
