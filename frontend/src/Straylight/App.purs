-- | Main application component — straylight-llm gateway dashboard
-- |
-- | Full Hydrogen integration:
-- |
-- | • Router — URL-based tab navigation. Browser back/forward works.
-- |   ProofLookup has shareable URLs (/proofs/:id).
-- |
-- | • Query — All API fetches go through QueryClient for caching,
-- |   deduplication, and stale-while-revalidate. 10s stale time means
-- |   switching tabs shows cached data instantly, refetches in background.
-- |
-- | • Tabs — ARIA-compliant keyboard navigation (Arrow keys, Home, End)
-- |   in the sidebar. Vertical orientation, loop enabled.
-- |
-- | • SSE → Query — Server-Sent Events update the query cache directly:
-- |   provider.status → setQueryData (immediate display)
-- |   request.completed → invalidate (trigger refetch)
-- |   metrics.update → direct state (ephemeral, not cached)
module Straylight.App where

import Prelude

import Data.Array as Array
import Data.Const (Const)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..), fromMaybe)
import Data.Time.Duration (Milliseconds(..))
import Effect.Aff.Class (class MonadAff, liftAff)
import Effect.Class (liftEffect)
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Halogen.Subscription as HS
import Hydrogen.Data.RemoteData (RemoteData(..))
import Hydrogen.Data.RemoteData as RD
import Hydrogen.Data.Format as Fmt
import Hydrogen.Query as Q
import Hydrogen.Router as Router
import Hydrogen.UI.Tabs as Tabs
import Type.Proxy (Proxy(..))

import Straylight.API.Client as Api
import Straylight.Components.HealthPanel as HealthPanel
import Straylight.Components.ProvidersPanel as ProvidersPanel
import Straylight.Components.ProviderHealthDashboard as ProviderHealthDashboard
import Straylight.Components.ModelsPanel as ModelsPanel
import Straylight.Components.TimelinePanel as TimelinePanel
import Straylight.Components.ProofPanel as ProofPanel
import Straylight.Components.Icon as Icon
import Straylight.Components.Splash as Splash
import Straylight.Route as Route
import Straylight.QueryKeys as QK
import Straylight.Streaming as Stream


-- ════════════════════════════════════════════════════════════════════════════
--                                                                     // types
-- ════════════════════════════════════════════════════════════════════════════

type Input =
  { queryClient :: Q.QueryClient
  , initialRoute :: Route.Route
  }

type State =
  { config :: Api.Config
  , queryClient :: Q.QueryClient
  , route :: Route.Route
  -- Query states
  , health :: Q.QueryState String Api.HealthResponse
  , models :: Q.QueryState String Api.ModelList
  , requests :: Q.QueryState String Api.RequestsResponse
  , dashboard :: Q.QueryState String Api.DashboardResponse
  , requestFilter :: Api.RequestFilter
  -- Direct state (not cached)
  , providers :: Array ProvidersPanel.ProviderInfo
  , selectedRequest :: Maybe Api.RequestDetail
  -- Proof
  , proofId :: String
  , proof :: Q.QueryState String Api.DischargeProof
  -- SSE
  , sseState :: Stream.ConnectionState
  , eventEmitter :: Maybe Stream.EventEmitter
  -- Live metrics (from SSE, ephemeral)
  , requestsLastMinute :: Int
  , errorRate :: Number
  , avgLatencyMs :: Int
  -- Toast
  , toastError :: Maybe String
  }

data Action
  = Initialize
  | Finalize
  -- Routing
  | Navigate Route.Route
  | HandlePopState String
  | HandleTabChange Tabs.Output
  -- Data
  | FetchHealth
  | FetchModels
  | FetchRequests
  | FetchRequestDetail String
  | FetchProof
  | FetchDashboard
  -- SSE
  | HandleSSE Stream.GatewayEvent
  -- Proof
  | SetProofId String
  -- Timeline
  | HandleTimelineOutput TimelinePanel.Output
  | HandleProofOutput ProofPanel.Output
  -- Toast
  | DismissToast


-- ════════════════════════════════════════════════════════════════════════════
--                                                                     // slots
-- ════════════════════════════════════════════════════════════════════════════

type Slots =
  ( tabs :: Tabs.Slot Unit
  , healthPanel :: H.Slot (Const Void) Void Unit
  , providersPanel :: H.Slot (Const Void) Void Unit
  , dashboardPanel :: H.Slot (Const Void) Void Unit
  , modelsPanel :: H.Slot (Const Void) Void Unit
  , timelinePanel :: H.Slot (Const Void) TimelinePanel.Output Unit
  , proofPanel :: H.Slot (Const Void) ProofPanel.Output Unit
  )

_tabs = Proxy :: Proxy "tabs"
_healthPanel = Proxy :: Proxy "healthPanel"
_providersPanel = Proxy :: Proxy "providersPanel"
_dashboardPanel = Proxy :: Proxy "dashboardPanel"
_modelsPanel = Proxy :: Proxy "modelsPanel"
_timelinePanel = Proxy :: Proxy "timelinePanel"
_proofPanel = Proxy :: Proxy "proofPanel"


-- ════════════════════════════════════════════════════════════════════════════
--                                                                 // component
-- ════════════════════════════════════════════════════════════════════════════

component :: forall q o m. MonadAff m => H.Component q Input o m
component = H.mkComponent
  { initialState
  , render
  , eval: H.mkEval H.defaultEval
      { handleAction = handleAction
      , initialize = Just Initialize
      , finalize = Just Finalize
      }
  }

initialState :: Input -> State
initialState input =
  { config: Api.defaultConfig
  , queryClient: input.queryClient
  , route: input.initialRoute
  , health: Q.initialQueryState
  , models: Q.initialQueryState
  , requests: Q.initialQueryState
  , dashboard: Q.initialQueryState
  , requestFilter: Api.defaultFilter
  , providers: []
  , selectedRequest: Nothing
  , proofId: extractProofId input.initialRoute
  , proof: Q.initialQueryState
  , sseState: Stream.Connecting
  , eventEmitter: Nothing
  , requestsLastMinute: 0
  , errorRate: 0.0
  , avgLatencyMs: 0
  , toastError: Nothing
  }
  where
  extractProofId (Route.ProofLookup rid) = rid
  extractProofId _ = ""


-- ════════════════════════════════════════════════════════════════════════════
--                                                                    // render
-- ════════════════════════════════════════════════════════════════════════════

render :: forall m. MonadAff m => State -> H.ComponentHTML Action Slots m
render state =
  HH.div [ HP.class_ (H.ClassName "layout dashboard-layout") ]
    [ renderTitlebar state
    , renderSidebar state
    , renderMain state
    , renderFooter state
    , renderToast state
    ]

renderTitlebar :: forall m. MonadAff m => State -> H.ComponentHTML Action Slots m
renderTitlebar state =
  HH.div [ HP.class_ (H.ClassName "titlebar") ]
    [ HH.div [ HP.class_ (H.ClassName "titlebar-left") ]
        [ HH.button [ HP.class_ (H.ClassName "titlebar-btn") ] [ Icon.icon "menu" ]
        ]
    , HH.div [ HP.class_ (H.ClassName "titlebar-center") ]
        [ HH.text "straylight gateway" ]
    , HH.div [ HP.class_ (H.ClassName "titlebar-right") ]
        [ HH.span [ HP.class_ (H.ClassName $ "sse-indicator " <> sseClass state.sseState) ]
            [ HH.span [ HP.class_ (H.ClassName $ "status-dot " <> sseClass state.sseState) ] []
            , HH.text $ sseLabel state.sseState
            ]
        , swr state
        , HH.button [ HP.class_ (H.ClassName "titlebar-btn") ] [ Icon.icon "settings" ]
        ]
    ]
  where
  -- Show a subtle "refreshing" indicator when any query is fetching with stale data
  swr s =
    let fetching = s.health.isFetching || s.models.isFetching || s.requests.isFetching
        hasStale = s.health.isStale || s.models.isStale || s.requests.isStale
    in if fetching && hasStale
      then HH.span [ HP.class_ (H.ClassName "swr-indicator") ]
        [ HH.span [ HP.class_ (H.ClassName "loading-spinner-sm") ] []
        , HH.text "refreshing"
        ]
      else HH.text ""

renderSidebar :: forall m. MonadAff m => State -> H.ComponentHTML Action Slots m
renderSidebar state =
  HH.div [ HP.class_ (H.ClassName "sidebar") ]
    [ -- Hydrogen.UI.Tabs for keyboard-accessible ARIA navigation
      -- Vertical orientation, controlled value from router
      HH.slot _tabs unit Tabs.component tabsInput HandleTabChange

      -- Live metrics (from SSE, below tabs)
    , HH.div [ HP.class_ (H.ClassName "sidebar-metrics") ]
        [ HH.div [ HP.class_ (H.ClassName "sidebar-label") ] [ HH.text "Live" ]
        , metricRow "Req/min" (show state.requestsLastMinute) ""
        , metricRow "Avg latency" (show state.avgLatencyMs <> "ms") ""
        , metricRow "Error rate" (Fmt.formatPercent state.errorRate)
            (errorRateClass state.errorRate)
        ]
    ]
  where
  tabsInput :: Tabs.Input
  tabsInput =
    { tabs: map routeToTab Route.allTabs
    , value: Just (Route.routeToTabValue state.route)  -- Controlled: synced with router
    , defaultValue: Nothing
    , orientation: Tabs.Vertical
    , activationMode: Tabs.Automatic
    , loop: true
    }
  routeToTab route =
    { value: Route.routeToTabValue route
    , label: Route.routeLabel route
    , disabled: false
    }

metricRow :: forall w i. String -> String -> String -> HH.HTML w i
metricRow label value extraClass =
  HH.div [ HP.class_ (H.ClassName "metric-item") ]
    [ HH.span [ HP.class_ (H.ClassName "metric-label") ] [ HH.text label ]
    , HH.span [ HP.class_ (H.ClassName $ "metric-value mono " <> extraClass) ]
        [ HH.text value ]
    ]

renderMain :: forall m. MonadAff m => State -> H.ComponentHTML Action Slots m
renderMain state =
  HH.div [ HP.class_ (H.ClassName "thread") ]
    [ HH.div [ HP.class_ (H.ClassName "thread-content") ]
        [ HH.div [ HP.class_ (H.ClassName "messages dashboard-content") ]
            [ renderPanel state ]
        ]
    ]

renderPanel :: forall m. MonadAff m => State -> H.ComponentHTML Action Slots m
renderPanel state = case state.route of
  Route.Health ->
    HH.slot _healthPanel unit HealthPanel.component
      { health: state.health } absurd

  Route.Providers ->
    HH.slot _providersPanel unit ProvidersPanel.component
      { providers: state.providers
      , connectionState: state.sseState
      } absurd

  Route.Dashboard ->
    HH.slot _dashboardPanel unit ProviderHealthDashboard.component
      { dashboard: state.dashboard } absurd

  Route.Models ->
    HH.slot _modelsPanel unit ModelsPanel.component
      { models: state.models } absurd

  Route.Timeline ->
    HH.slot _timelinePanel unit TimelinePanel.component
      { requests: state.requests
      , selectedRequest: state.selectedRequest
      , filter: state.requestFilter
      } HandleTimelineOutput

  Route.Proofs ->
    HH.slot _proofPanel unit ProofPanel.component
      { proof: state.proof
      , proofId: state.proofId
      } HandleProofOutput

  Route.ProofLookup _rid ->
    HH.slot _proofPanel unit ProofPanel.component
      { proof: state.proof
      , proofId: state.proofId
      } HandleProofOutput

  Route.NotFound ->
    HH.slot _healthPanel unit HealthPanel.component
      { health: state.health } absurd

renderFooter :: forall m. MonadAff m => State -> H.ComponentHTML Action Slots m
renderFooter state =
  HH.div [ HP.class_ (H.ClassName "footer") ]
    [ HH.div [ HP.class_ (H.ClassName "footer-left") ]
        [ HH.span [ HP.class_ (H.ClassName "footer-status") ]
            [ HH.span [ HP.class_ (H.ClassName $ "status-dot " <> connDot) ] []
            , HH.text versionText
            ]
        ]
    , HH.div [ HP.class_ (H.ClassName "footer-center") ]
        [ HH.text $ show (Array.length state.providers) <> " providers" ]
    , HH.div [ HP.class_ (H.ClassName "footer-right") ]
        [ HH.text "aleph cube architecture" ]
    ]
  where
  connDot = case state.health.data of
    Success _ -> "idle"
    Loading -> "connecting"
    _ -> "error"
  versionText = case state.health.data of
    Success h -> "v" <> h.version
    Loading -> "connecting..."
    Failure _ -> "disconnected"
    NotAsked -> "—"

renderToast :: forall m. MonadAff m => State -> H.ComponentHTML Action Slots m
renderToast state = case state.toastError of
  Nothing -> HH.text ""
  Just err ->
    HH.div [ HP.class_ (H.ClassName "error-toast"), HE.onClick \_ -> DismissToast ]
      [ HH.span [ HP.class_ (H.ClassName "error-toast-text") ] [ HH.text err ]
      , HH.button [ HP.class_ (H.ClassName "error-toast-close") ] [ Icon.iconSm "x" ]
      ]


-- ════════════════════════════════════════════════════════════════════════════
--                                                                   // actions
-- ════════════════════════════════════════════════════════════════════════════

handleAction :: forall o m. MonadAff m => Action -> H.HalogenM State Action Slots o m Unit
handleAction = case _ of

  -- ── Lifecycle ─────────────────────────────────────────────────────────

  Initialize -> do
    liftEffect Splash.dismiss

    -- Subscribe to browser back/forward
    { emitter, listener } <- H.liftEffect HS.create
    liftEffect $ Router.onPopState \path ->
      HS.notify listener (HandlePopState path)
    _ <- H.subscribe (identity <$> emitter)

    -- Intercept internal <a> clicks for SPA navigation
    { emitter: linkEmitter, listener: linkListener } <- H.liftEffect HS.create
    liftEffect $ Router.interceptLinks \path ->
      HS.notify linkListener (HandlePopState path)
    _ <- H.subscribe (identity <$> linkEmitter)

    -- Start SSE connection
    state <- H.get
    let streamConfig = Stream.defaultStreamConfig
          { baseUrl = state.config.baseUrl
          , port = state.config.port
          }
    ee <- liftEffect $ Stream.createEventEmitter streamConfig
    H.modify_ _ { eventEmitter = Just ee }
    sseEmitter <- liftEffect $ Stream.subscribeToEvents ee
    _ <- H.subscribe (HandleSSE <$> sseEmitter)

    -- Initial data fetches via Query
    handleAction FetchHealth
    handleAction FetchModels

    -- If initial route is a data-bearing tab, fetch its data
    s <- H.get
    case s.route of
      Route.Timeline -> handleAction FetchRequests
      Route.ProofLookup rid -> do
        H.modify_ _ { proofId = rid }
        handleAction FetchProof
      _ -> pure unit

  Finalize -> do
    state <- H.get
    case state.eventEmitter of
      Nothing -> pure unit
      Just ee -> liftEffect $ Stream.closeEventEmitter ee

  -- ── Routing ───────────────────────────────────────────────────────────

  Navigate route -> do
    state <- H.get
    when (route /= state.route) do
      liftEffect $ Router.navigate route
      H.modify_ _ { route = route }
      -- Lazy-fetch data for the target tab
      ensureDataForRoute route

  HandlePopState path -> do
    let route = Router.parseRoute path :: Route.Route
    state <- H.get
    when (route /= state.route) do
      H.modify_ _ { route = route }
      ensureDataForRoute route

  HandleTabChange (Tabs.ValueChanged value) -> do
    let route = Route.tabValueToRoute value
    handleAction (Navigate route)

  -- ── Query-backed data fetching ────────────────────────────────────────

  FetchHealth -> do
    state <- H.get
    H.modify_ _ { health = state.health { isFetching = true } }
    qs <- liftAff $ Q.query state.queryClient
      (Q.defaultQueryOptions QK.health (Api.healthCheck state.config))
        { staleTime = Just (Milliseconds 10000.0)   -- 10s fresh
        , retry = 2
        , retryDelay = Milliseconds 2000.0
        }
    H.modify_ _ { health = qs }

  FetchModels -> do
    state <- H.get
    H.modify_ _ { models = state.models { isFetching = true } }
    qs <- liftAff $ Q.query state.queryClient
      (Q.defaultQueryOptions QK.models (Api.getModels state.config))
        { staleTime = Just (Milliseconds 30000.0)   -- 30s fresh (models change rarely)
        , retry = 1
        , retryDelay = Milliseconds 3000.0
        }
    H.modify_ _ { models = qs }

  FetchRequests -> do
    state <- H.get
    H.modify_ _ { requests = state.requests { isFetching = true } }
    let filterKey = QK.requestsWithFilter
          { provider: fromMaybe "" state.requestFilter.provider
          , model: fromMaybe "" state.requestFilter.model
          , status: ""
          , offset: state.requestFilter.offset
          }
    qs <- liftAff $ Q.query state.queryClient
      (Q.defaultQueryOptions filterKey
        (Api.getRequests state.config state.requestFilter))
        { staleTime = Just (Milliseconds 5000.0)   -- 5s fresh (requests change often)
        , retry = 1
        , retryDelay = Milliseconds 1000.0
        }
    H.modify_ _ { requests = qs }

  FetchRequestDetail rid -> do
    state <- H.get
    result <- liftAff $ Api.getRequestDetail state.config rid
    case result of
      Left err -> H.modify_ _ { toastError = Just err }
      Right detail -> H.modify_ _ { selectedRequest = Just detail }

  FetchDashboard -> do
    state <- H.get
    H.modify_ _ { dashboard = state.dashboard { isFetching = true } }
    result <- liftAff $ Api.getDashboard state.config
    case result of
      Left err -> H.modify_ _ { dashboard = { data: Failure err, isFetching: false, isStale: false } }
      Right dash -> H.modify_ _ { dashboard = { data: Success dash, isFetching: false, isStale: false } }

  FetchProof -> do
    state <- H.get
    when (state.proofId /= "") do
      H.modify_ _ { proof = state.proof { isFetching = true } }
      qs <- liftAff $ Q.query state.queryClient
        (Q.defaultQueryOptions (QK.proof state.proofId)
          (Api.getProof state.config state.proofId))
          { staleTime = Just (Milliseconds 60000.0)  -- 1min (proofs are immutable)
          , retry = 1
          , retryDelay = Milliseconds 2000.0
          }
      H.modify_ _ { proof = qs }

  -- ── SSE → Query integration ───────────────────────────────────────────

  HandleSSE event -> case event of
    Stream.ConnectionOpened ->
      H.modify_ _ { sseState = Stream.Connected }

    Stream.ConnectionClosed ->
      H.modify_ _ { sseState = Stream.Disconnected }

    Stream.ConnectionError err ->
      H.modify_ _ { sseState = Stream.Failed err }

    Stream.ProviderStatusChanged pse -> do
      -- Direct state update (providers aren't query-backed, they're SSE-only)
      state <- H.get
      let existing = Array.filter (\p -> p.name /= pse.provider) state.providers
          newProvider =
            { name: pse.provider
            , status: pse.status
            , circuitState: cbStateToString pse.circuitBreakerState
            , failureCount: 0
            , lastSuccess: Nothing
            , lastFailure: Nothing
            }
      H.modify_ _ { providers = existing <> [newProvider] }

    Stream.RequestCompleted _ -> do
      -- Invalidate requests cache → stale-while-revalidate kicks in
      state <- H.get
      liftEffect $ Q.invalidate state.queryClient QK.requests
      -- If Timeline is active, immediately refetch
      when (isTimelineRoute state.route) do
        handleAction FetchRequests

    Stream.RequestStarted _ ->
      pure unit  -- Could show "in-flight" indicator

    Stream.ProofGenerated _ ->
      pure unit  -- Proofs are fetched on demand

    Stream.MetricsUpdated me ->
      H.modify_ _
        { requestsLastMinute = me.requestsLastMinute
        , errorRate = me.errorRate
        , avgLatencyMs = me.avgLatencyMs
        }

    _ -> pure unit

  -- ── Proof ─────────────────────────────────────────────────────────────

  SetProofId pid ->
    H.modify_ _ { proofId = pid }

  HandleProofOutput output -> case output of
    ProofPanel.ProofIdChanged pid ->
      H.modify_ _ { proofId = pid }
    ProofPanel.LookupRequested -> do
      state <- H.get
      when (state.proofId /= "") do
        -- Update URL to shareable proof link
        liftEffect $ Router.pushState ("/proofs/" <> state.proofId)
        H.modify_ _ { route = Route.ProofLookup state.proofId }
        handleAction FetchProof

  -- ── Timeline ──────────────────────────────────────────────────────────

  HandleTimelineOutput output -> case output of
    TimelinePanel.FilterChanged newFilter -> do
      -- Changing filter → new cache key → fresh fetch
      H.modify_ _ { requestFilter = newFilter }
      handleAction FetchRequests

    TimelinePanel.RequestSelected rid ->
      handleAction (FetchRequestDetail rid)

    TimelinePanel.RefreshRequested -> do
      -- Force invalidate + refetch
      state <- H.get
      liftEffect $ Q.invalidate state.queryClient QK.requests
      handleAction FetchRequests

    TimelinePanel.LoadMore -> do
      state <- H.get
      let newFilter = state.requestFilter
            { offset = state.requestFilter.offset + state.requestFilter.limit }
      H.modify_ _ { requestFilter = newFilter }
      handleAction FetchRequests

    TimelinePanel.ExportRequested _ ->
      pure unit  -- Future: trigger download

  -- ── Toast ─────────────────────────────────────────────────────────────

  DismissToast ->
    H.modify_ _ { toastError = Nothing }


-- ════════════════════════════════════════════════════════════════════════════
--                                                                   // helpers
-- ════════════════════════════════════════════════════════════════════════════

-- | Ensure data is loaded for a given route (lazy fetch on tab switch)
ensureDataForRoute :: forall o m. MonadAff m => Route.Route -> H.HalogenM State Action Slots o m Unit
ensureDataForRoute = case _ of
  Route.Timeline -> do
    state <- H.get
    when (RD.isNotAsked state.requests.data) do
      handleAction FetchRequests
  Route.Dashboard -> do
    state <- H.get
    when (RD.isNotAsked state.dashboard.data) do
      handleAction FetchDashboard
  Route.ProofLookup rid -> do
    H.modify_ _ { proofId = rid }
    handleAction FetchProof
  _ -> pure unit

isTimelineRoute :: Route.Route -> Boolean
isTimelineRoute Route.Timeline = true
isTimelineRoute _ = false

sseClass :: Stream.ConnectionState -> String
sseClass = case _ of
  Stream.Connecting -> "connecting"
  Stream.Connected -> "idle"
  Stream.Reconnecting _ -> "connecting"
  Stream.Disconnected -> "error"
  Stream.Failed _ -> "error"

sseLabel :: Stream.ConnectionState -> String
sseLabel = case _ of
  Stream.Connecting -> "connecting"
  Stream.Connected -> "live"
  Stream.Reconnecting n -> "reconnecting (" <> show n <> ")"
  Stream.Disconnected -> "offline"
  Stream.Failed _ -> "failed"

errorRateClass :: Number -> String
errorRateClass r
  | r > 0.1 = "error-high"
  | r > 0.05 = "error-med"
  | otherwise = ""

cbStateToString :: Api.CircuitBreakerState -> String
cbStateToString = case _ of
  Api.CBClosed -> "CBClosed"
  Api.CBOpen -> "CBOpen"
  Api.CBHalfOpen -> "CBHalfOpen"
