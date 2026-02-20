-- | Main application component for the straylight-llm gateway dashboard
module Straylight.App where

import Prelude

import Data.Const (Const)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..))

import Effect.Aff.Class (class MonadAff, liftAff)
import Effect.Class (liftEffect)
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Type.Proxy (Proxy(..))
import Straylight.API.Client as Api
import Straylight.Components.ProofViewer as ProofViewer
import Straylight.Components.HealthStatus as HealthStatus
import Straylight.Components.ModelsPanel as ModelsPanel
import Straylight.Components.Icon as Icon
import Straylight.Components.Splash as Splash


-- ════════════════════════════════════════════════════════════════════════════
--                                                                     // state
-- ════════════════════════════════════════════════════════════════════════════

data Tab = Health | Models | Proofs

derive instance eqTab :: Eq Tab

type State =
  { config :: Api.Config
  , activeTab :: Tab
  , health :: Maybe Api.HealthResponse
  , models :: Maybe Api.ModelList
  , proofId :: String
  , proof :: Maybe Api.DischargeProof
  , error :: Maybe String
  }

data Action
  = Initialize
  | SwitchTab Tab
  | RefreshHealth
  | RefreshModels
  | SetProofId String
  | LookupProof


-- ════════════════════════════════════════════════════════════════════════════
--                                                                     // slots
-- ════════════════════════════════════════════════════════════════════════════

type Slots =
  ( healthStatus :: H.Slot (Const Void) Void Unit
  , modelsPanel :: H.Slot (Const Void) Void Unit
  , proofViewer :: H.Slot (Const Void) Void Unit
  )

_healthStatus = Proxy :: Proxy "healthStatus"
_modelsPanel = Proxy :: Proxy "modelsPanel"
_proofViewer = Proxy :: Proxy "proofViewer"


-- ════════════════════════════════════════════════════════════════════════════
--                                                                 // component
-- ════════════════════════════════════════════════════════════════════════════

component :: forall q i o m. MonadAff m => H.Component q i o m
component = H.mkComponent
  { initialState: \_ ->
      { config: Api.defaultConfig
      , activeTab: Health
      , health: Nothing
      , models: Nothing
      , proofId: ""
      , proof: Nothing
      , error: Nothing
      }
  , render
  , eval: H.mkEval H.defaultEval
      { handleAction = handleAction
      , initialize = Just Initialize
      }
  }


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
    ]

renderTitlebar :: forall m. State -> H.ComponentHTML Action Slots m
renderTitlebar _ =
  HH.div [ HP.class_ (H.ClassName "titlebar") ]
    [ HH.div [ HP.class_ (H.ClassName "titlebar-left") ]
        [ HH.button [ HP.class_ (H.ClassName "titlebar-btn") ]
            [ Icon.icon "menu" ]
        ]
    , HH.div [ HP.class_ (H.ClassName "titlebar-center") ]
        [ HH.text "straylight gateway" ]
    , HH.div [ HP.class_ (H.ClassName "titlebar-right") ]
        [ HH.button [ HP.class_ (H.ClassName "titlebar-btn") ]
            [ Icon.icon "settings" ]
        ]
    ]

renderSidebar :: forall m. State -> H.ComponentHTML Action Slots m
renderSidebar state =
  HH.div [ HP.class_ (H.ClassName "sidebar") ]
    [ HH.div [ HP.class_ (H.ClassName "sidebar-label") ] [ HH.text "Dashboard" ]
    , HH.div [ HP.class_ (H.ClassName "sidebar-nav") ]
        [ navItem Health "gauge" "Health" state.activeTab
        , navItem Models "list-checks" "Models" state.activeTab
        , navItem Proofs "git-compare" "Proofs" state.activeTab
        ]
    ]
  where
  navItem tab iconName label activeTab =
    HH.button
      [ HP.classes $ map H.ClassName $ ["nav-item"] <> if tab == activeTab then ["active"] else []
      , HE.onClick \_ -> SwitchTab tab
      ]
      [ Icon.icon iconName
      , HH.span [ HP.class_ (H.ClassName "nav-label") ] [ HH.text label ]
      ]

renderMain :: forall m. MonadAff m => State -> H.ComponentHTML Action Slots m
renderMain state =
  HH.div [ HP.class_ (H.ClassName "thread") ]
    [ HH.div [ HP.class_ (H.ClassName "thread-content") ]
        [ HH.div [ HP.class_ (H.ClassName "messages dashboard-content") ]
            [ case state.activeTab of
                Health -> HH.slot _healthStatus unit HealthStatus.component
                  { health: state.health } absurd
                Models -> HH.slot _modelsPanel unit ModelsPanel.component
                  { models: state.models } absurd
                Proofs -> HH.slot _proofViewer unit ProofViewer.component
                  { proof: state.proof, proofId: state.proofId } absurd
            ]
        ]
    , case state.error of
        Nothing -> HH.text ""
        Just err ->
          HH.div [ HP.class_ (H.ClassName "error-toast") ]
            [ HH.span [ HP.class_ (H.ClassName "error-toast-text") ] [ HH.text err ]
            ]
    ]

renderFooter :: forall m. State -> H.ComponentHTML Action Slots m
renderFooter state =
  HH.div [ HP.class_ (H.ClassName "footer") ]
    [ HH.div [ HP.class_ (H.ClassName "footer-left") ]
        [ HH.span [ HP.class_ (H.ClassName "footer-status") ]
            [ HH.span [ HP.class_ (H.ClassName $ "status-dot " <> connectionStatus) ] []
            , HH.text $ case state.health of
                Just h -> "v" <> h.version
                Nothing -> "disconnected"
            ]
        ]
    , HH.div [ HP.class_ (H.ClassName "footer-right") ]
        [ HH.text "aleph cube architecture" ]
    ]
  where
  connectionStatus = case state.health of
    Just _ -> "idle"
    Nothing -> "error"


-- ════════════════════════════════════════════════════════════════════════════
--                                                                   // actions
-- ════════════════════════════════════════════════════════════════════════════

handleAction :: forall o m. MonadAff m => Action -> H.HalogenM State Action Slots o m Unit
handleAction = case _ of
  Initialize -> do
    liftEffect Splash.dismiss
    handleAction RefreshHealth
    handleAction RefreshModels

  SwitchTab tab ->
    H.modify_ _ { activeTab = tab }

  RefreshHealth -> do
    state <- H.get
    result <- liftAff $ Api.healthCheck state.config
    case result of
      Left err -> H.modify_ _ { error = Just err, health = Nothing }
      Right h -> H.modify_ _ { health = Just h, error = Nothing }

  RefreshModels -> do
    state <- H.get
    result <- liftAff $ Api.getModels state.config
    case result of
      Left err -> H.modify_ _ { error = Just err, models = Nothing }
      Right m -> H.modify_ _ { models = Just m, error = Nothing }

  SetProofId id ->
    H.modify_ _ { proofId = id }

  LookupProof -> do
    state <- H.get
    if state.proofId == ""
      then H.modify_ _ { error = Just "Enter a request ID" }
      else do
        result <- liftAff $ Api.getProof state.config state.proofId
        case result of
          Left err -> H.modify_ _ { error = Just err, proof = Nothing }
          Right p -> H.modify_ _ { proof = Just p, error = Nothing }
