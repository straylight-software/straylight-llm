-- | Request timeline — chronological request view with filters + drill-down
-- |
-- | Receives QueryState from parent. Emits Output events for filter changes,
-- | selection, refresh, pagination. Uses Hydrogen.Data.Format for display.
module Straylight.Components.TimelinePanel
  ( component
  , Input
  , Output(..)
  , ExportFormat(..)
  ) where

import Prelude

import Data.Array as Array
import Data.Maybe (Maybe(..), fromMaybe)
import Data.String as String
import Effect.Aff.Class (class MonadAff)
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Hydrogen.Data.RemoteData (RemoteData(..))
import Hydrogen.Data.Format as Fmt
import Hydrogen.Query as Q
import Straylight.API.Client as Api
import Straylight.Components.Icon as Icon
import Straylight.Components.UI as UI


type Input =
  { requests :: Q.QueryState String Api.RequestsResponse
  , selectedRequest :: Maybe Api.RequestDetail
  , filter :: Api.RequestFilter
  }

data Output
  = FilterChanged Api.RequestFilter
  | RequestSelected String
  | RefreshRequested
  | LoadMore
  | ExportRequested ExportFormat

data ExportFormat = ExportJSON | ExportCSV

type State =
  { requests :: Q.QueryState String Api.RequestsResponse
  , selectedRequest :: Maybe Api.RequestDetail
  , filter :: Api.RequestFilter
  , filterExpanded :: Boolean
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


component :: forall q m. MonadAff m => H.Component q Input Output m
component = H.mkComponent
  { initialState: \i ->
      { requests: i.requests
      , selectedRequest: i.selectedRequest
      , filter: i.filter
      , filterExpanded: false
      , providerFilter: fromMaybe "" i.filter.provider
      , modelFilter: fromMaybe "" i.filter.model
      , statusFilter: ""
      }
  , render
  , eval: H.mkEval H.defaultEval
      { handleAction = handleAction
      , receive = Just <<< Receive
      }
  }


-- ════════════════════════════════════════════════════════════════════════════
--                                                                    // render
-- ════════════════════════════════════════════════════════════════════════════

render :: forall m. State -> H.ComponentHTML Action () m
render state =
  HH.div [ HP.class_ (H.ClassName "dashboard-panel timeline-panel") ]
    [ renderHeader state
    , if state.filterExpanded then renderFilterBar state else HH.text ""
    , HH.div [ HP.class_ (H.ClassName "panel-body timeline-body") ]
        [ UI.renderQueryWith
            { loading: UI.loadingPanel "Loading requests..."
            , failure: UI.errorPanel
            , success: \resp ->
                if Array.null resp.requests
                  then UI.emptyPanel "clock" "No requests yet"
                    "Requests will appear here as they flow through the gateway."
                  else renderRequestList state resp
            }
            state.requests
        ]
    , case state.selectedRequest of
        Just detail -> renderDetailModal detail
        Nothing -> HH.text ""
    ]

renderHeader :: forall m. State -> H.ComponentHTML Action () m
renderHeader state =
  HH.div [ HP.class_ (H.ClassName "panel-header") ]
    [ HH.div [ HP.class_ (H.ClassName "panel-header-left") ]
        [ Icon.icon "clock"
        , HH.span [ HP.class_ (H.ClassName "panel-title") ] [ HH.text "Request Timeline" ]
        , case Q.getData state.requests of
            Just r -> HH.span [ HP.class_ (H.ClassName "panel-badge") ]
              [ HH.text $ Fmt.formatCount r.total <> " total" ]
            Nothing -> HH.text ""
        , if state.requests.isFetching && Q.hasData state.requests
            then UI.loadingInline
            else HH.text ""
        ]
    , HH.div [ HP.class_ (H.ClassName "panel-header-right") ]
        [ btn state.filterExpanded ToggleFilterExpanded "settings" "Filter"
        , btn false RequestRefresh "arrow-up" "Refresh"
        , btn false (RequestExport ExportJSON) "folder" "Export"
        ]
    ]
  where
  btn active act iconName label =
    HH.button
      [ HP.classes $ map H.ClassName $ ["btn", "btn-sm"] <> if active then ["active"] else []
      , HE.onClick \_ -> act
      ]
      [ Icon.iconSm iconName, HH.text $ " " <> label ]

renderFilterBar :: forall m. State -> H.ComponentHTML Action () m
renderFilterBar state =
  HH.div [ HP.class_ (H.ClassName "filter-bar") ]
    [ HH.div [ HP.class_ (H.ClassName "filter-row") ]
        [ textFilter "Provider" state.providerFilter "e.g. vertex" SetProviderFilter
        , textFilter "Model" state.modelFilter "e.g. claude-3-opus" SetModelFilter
        , selectFilter
        ]
    , HH.div [ HP.class_ (H.ClassName "filter-actions") ]
        [ HH.button [ HP.class_ (H.ClassName "btn btn-sm btn-primary"), HE.onClick \_ -> ApplyFilters ]
            [ HH.text "Apply" ]
        , HH.button [ HP.class_ (H.ClassName "btn btn-sm"), HE.onClick \_ -> ClearFilters ]
            [ HH.text "Clear" ]
        ]
    ]
  where
  textFilter label value placeholder onChange =
    HH.div [ HP.class_ (H.ClassName "filter-group") ]
      [ HH.label [ HP.class_ (H.ClassName "filter-label") ] [ HH.text label ]
      , HH.input
          [ HP.type_ HP.InputText, HP.class_ (H.ClassName "filter-input")
          , HP.placeholder placeholder, HP.value value
          , HE.onValueInput onChange
          ]
      ]
  selectFilter =
    HH.div [ HP.class_ (H.ClassName "filter-group") ]
      [ HH.label [ HP.class_ (H.ClassName "filter-label") ] [ HH.text "Status" ]
      , HH.select [ HP.class_ (H.ClassName "filter-select"), HE.onValueChange SetStatusFilter ]
          [ HH.option [ HP.value "" ] [ HH.text "All" ]
          , HH.option [ HP.value "success" ] [ HH.text "Success" ]
          , HH.option [ HP.value "error" ] [ HH.text "Error" ]
          , HH.option [ HP.value "pending" ] [ HH.text "Pending" ]
          , HH.option [ HP.value "retrying" ] [ HH.text "Retrying" ]
          ]
      ]

renderRequestList :: forall m. State -> Api.RequestsResponse -> H.ComponentHTML Action () m
renderRequestList state response =
  HH.div [ HP.class_ (H.ClassName "request-list") ]
    [ HH.div [ HP.class_ (H.ClassName "request-list-header") ]
        (map (\c -> HH.span [ HP.class_ (H.ClassName $ "col-" <> c) ] [ HH.text c ])
          ["time", "model", "provider", "status", "latency", "tokens"])
    , HH.div [ HP.class_ (H.ClassName "request-list-body") ]
        (map renderRequestRow response.requests)
    , if response.offset + Array.length response.requests < response.total
        then HH.div [ HP.class_ (H.ClassName "load-more") ]
          [ HH.button [ HP.class_ (H.ClassName "btn"), HE.onClick \_ -> RequestLoadMore ]
              [ HH.text "Load More" ] ]
        else HH.text ""
    ]

renderRequestRow :: forall m. Api.GatewayRequest -> H.ComponentHTML Action () m
renderRequestRow req =
  HH.div
    [ HP.classes $ map H.ClassName ["request-row", statusRowClass req.status]
    , HE.onClick \_ -> SelectRequest req.requestId
    ]
    [ HH.span [ HP.class_ (H.ClassName "col-time mono") ] [ HH.text $ fmtTs req.timestamp ]
    , HH.span [ HP.class_ (H.ClassName "col-model") ] [ HH.text $ truncModel req.model ]
    , HH.span [ HP.class_ (H.ClassName "col-provider") ] [ HH.text req.provider ]
    , HH.span [ HP.class_ (H.ClassName $ "col-status " <> statusClass req.status) ]
        [ HH.div [ HP.class_ (H.ClassName "status-badge") ]
            [ Icon.iconSm (statusIcon req.status)
            , HH.text $ " " <> statusLabel req.status
            ] ]
    , HH.span [ HP.class_ (H.ClassName "col-latency mono") ] [ HH.text $ show req.latencyMs <> "ms" ]
    , HH.span [ HP.class_ (H.ClassName "col-tokens mono") ]
        [ HH.text $ Fmt.formatCount (req.promptTokens + req.completionTokens) ]
    ]


-- ════════════════════════════════════════════════════════════════════════════
--                                                              // detail modal
-- ════════════════════════════════════════════════════════════════════════════

renderDetailModal :: forall m. Api.RequestDetail -> H.ComponentHTML Action () m
renderDetailModal d =
  HH.div [ HP.class_ (H.ClassName "modal-overlay"), HE.onClick \_ -> CloseDetail ]
    [ HH.div [ HP.class_ (H.ClassName "modal request-detail-modal") ]
        [ HH.div [ HP.class_ (H.ClassName "modal-header") ]
            [ HH.div [ HP.class_ (H.ClassName "modal-title") ]
                [ HH.text "Request Detail"
                , HH.span [ HP.class_ (H.ClassName $ "status-badge " <> statusClass d.status) ]
                    [ HH.text $ statusLabel d.status ]
                ]
            , HH.button [ HP.class_ (H.ClassName "modal-close"), HE.onClick \_ -> CloseDetail ]
                [ Icon.icon "x" ]
            ]
        , HH.div [ HP.class_ (H.ClassName "modal-body") ]
            [ detailSection "Overview"
                [ HH.div [ HP.class_ (H.ClassName "detail-grid") ]
                    [ di "Request ID" d.requestId true
                    , di "Timestamp" d.timestamp true
                    , di "Model" d.model false
                    , di "Provider" d.provider false
                    , di "Latency" (show d.latencyMs <> "ms") true
                    , di "Prompt" (Fmt.formatCount d.promptTokens) true
                    , di "Completion" (Fmt.formatCount d.completionTokens) true
                    , di "Total" (Fmt.formatCount (d.promptTokens + d.completionTokens)) true
                    ]
                ]
            , case d.errorMessage of
                Just err -> HH.div [ HP.class_ (H.ClassName "detail-section error-section") ]
                  [ HH.div [ HP.class_ (H.ClassName "detail-section-header") ] [ HH.text "Error" ]
                  , HH.div [ HP.class_ (H.ClassName "error-message") ]
                      [ HH.code [] [ HH.text err ] ]
                  ]
                Nothing -> HH.text ""
            , detailSection "Coeffects"
                [ HH.div [ HP.class_ (H.ClassName "coeffect-list") ]
                    (map renderCoeffect d.coeffects) ]
            , if Array.null d.retryHistory then HH.text ""
              else detailSection "Retry History"
                [ HH.div [ HP.class_ (H.ClassName "retry-list") ]
                    (map renderRetry d.retryHistory) ]
            , detailSection "Request Body"
                [ HH.pre [ HP.class_ (H.ClassName "json-viewer") ]
                    [ HH.code [] [ HH.text d.requestBody ] ] ]
            , detailSection "Response Body"
                [ HH.pre [ HP.class_ (H.ClassName "json-viewer") ]
                    [ HH.code [] [ HH.text d.responseBody ] ] ]
            , case d.proofId of
                Just pid -> detailSection "Discharge Proof"
                  [ HH.a
                      [ HP.class_ (H.ClassName "proof-link")
                      , HP.href $ "/proofs/" <> pid
                      ]
                      [ Icon.iconSm "git-compare"
                      , HH.span [ HP.class_ (H.ClassName "mono") ] [ HH.text pid ]
                      ]
                  ]
                Nothing -> HH.text ""
            ]
        , HH.div [ HP.class_ (H.ClassName "modal-footer") ]
            [ HH.button [ HP.class_ (H.ClassName "btn"), HE.onClick \_ -> CloseDetail ]
                [ HH.text "Close" ]
            , HH.button [ HP.class_ (H.ClassName "btn btn-primary"), HE.onClick \_ -> RequestExport ExportJSON ]
                [ Icon.iconSm "folder", HH.text " Export JSON" ]
            ]
        ]
    ]

detailSection :: forall m. String -> Array (H.ComponentHTML Action () m) -> H.ComponentHTML Action () m
detailSection title kids =
  HH.div [ HP.class_ (H.ClassName "detail-section") ]
    ([ HH.div [ HP.class_ (H.ClassName "detail-section-header") ] [ HH.text title ] ] <> kids)

di :: forall m. String -> String -> Boolean -> H.ComponentHTML Action () m
di label value isMono =
  HH.div [ HP.class_ (H.ClassName "detail-item") ]
    [ HH.span [ HP.class_ (H.ClassName "detail-label") ] [ HH.text label ]
    , HH.span [ HP.classes $ map H.ClassName $ ["detail-value"] <> if isMono then ["mono"] else [] ]
        [ HH.text value ]
    ]

renderCoeffect :: forall m. Api.Coeffect -> H.ComponentHTML Action () m
renderCoeffect coeff =
  HH.div [ HP.class_ (H.ClassName $ "coeffect-badge " <> cls coeff) ]
    [ HH.text $ lbl coeff ]
  where
  lbl = case _ of
    Api.Pure -> "Pure"
    Api.Network -> "Network"
    Api.Auth p -> "Auth(" <> p <> ")"
    Api.Sandbox p -> "Sandbox(" <> p <> ")"
    Api.Filesystem p -> "Filesystem(" <> p <> ")"
    Api.Combined cs -> "Combined[" <> show (Array.length cs) <> "]"
  cls = case _ of
    Api.Pure -> "coeffect-pure"
    Api.Network -> "coeffect-net"
    Api.Auth _ -> "coeffect-auth"
    Api.Sandbox _ -> "coeffect-sandbox"
    Api.Filesystem _ -> "coeffect-fs"
    Api.Combined _ -> "coeffect-combined"

renderRetry :: forall m. Api.RetryAttempt -> H.ComponentHTML Action () m
renderRetry a =
  HH.div [ HP.class_ (H.ClassName $ "retry-item " <> statusRowClass a.status) ]
    [ HH.div [ HP.class_ (H.ClassName "retry-main") ]
        [ HH.span [ HP.class_ (H.ClassName "retry-provider") ] [ HH.text a.provider ]
        , HH.span [ HP.class_ (H.ClassName $ "status-badge " <> statusClass a.status) ]
            [ HH.text $ statusLabel a.status ]
        ]
    , HH.div [ HP.class_ (H.ClassName "retry-meta") ]
        [ HH.span [ HP.class_ (H.ClassName "retry-latency mono") ] [ HH.text $ show a.latencyMs <> "ms" ]
        , HH.span [ HP.class_ (H.ClassName "retry-time mono") ] [ HH.text $ fmtTs a.timestamp ]
        ]
    , case a.errorMessage of
        Just err -> HH.div [ HP.class_ (H.ClassName "retry-error") ] [ HH.text err ]
        Nothing -> HH.text ""
    ]


-- ════════════════════════════════════════════════════════════════════════════
--                                                                  // handlers
-- ════════════════════════════════════════════════════════════════════════════

handleAction :: forall m. MonadAff m => Action -> H.HalogenM State Action () Output m Unit
handleAction = case _ of
  Receive i -> H.modify_ _ { requests = i.requests, selectedRequest = i.selectedRequest, filter = i.filter }
  ToggleFilterExpanded -> H.modify_ \s -> s { filterExpanded = not s.filterExpanded }
  SetProviderFilter v -> H.modify_ _ { providerFilter = v }
  SetModelFilter v -> H.modify_ _ { modelFilter = v }
  SetStatusFilter v -> H.modify_ _ { statusFilter = v }
  ApplyFilters -> do
    s <- H.get
    H.raise $ FilterChanged s.filter
      { provider = if s.providerFilter == "" then Nothing else Just s.providerFilter
      , model = if s.modelFilter == "" then Nothing else Just s.modelFilter
      , status = parseStatus s.statusFilter
      , offset = 0
      }
  ClearFilters -> do
    H.modify_ _ { providerFilter = "", modelFilter = "", statusFilter = "" }
    H.raise $ FilterChanged Api.defaultFilter
  SelectRequest rid -> H.raise $ RequestSelected rid
  CloseDetail -> H.modify_ _ { selectedRequest = Nothing }
  RequestRefresh -> H.raise RefreshRequested
  RequestLoadMore -> H.raise LoadMore
  RequestExport fmt -> H.raise $ ExportRequested fmt


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

fmtTs :: String -> String
fmtTs ts = case String.indexOf (String.Pattern "T") ts of
  Just idx -> String.take 8 (String.drop (idx + 1) ts)
  Nothing -> ts

truncModel :: String -> String
truncModel m = if String.length m > 25 then String.take 22 m <> "..." else m
