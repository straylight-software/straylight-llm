-- | Discharge proof viewer — cryptographic evidence of resource access
-- |
-- | Uses QueryState for SWR-aware proof loading. Emits Output to parent
-- | so proof lookup updates the URL (shareable /proofs/:id links).
module Straylight.Components.ProofPanel
  ( component
  , Input
  , Output(..)
  ) where

import Prelude

import Data.Array as Array
import Data.Maybe (Maybe(..))
import Data.String as String
import Effect.Aff.Class (class MonadAff)
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Hydrogen.Data.RemoteData (RemoteData(..))
import Hydrogen.Query as Q
import Straylight.API.Client as Api
import Straylight.Components.Icon as Icon
import Straylight.Components.UI as UI


type Input =
  { proof :: Q.QueryState String Api.DischargeProof
  , proofId :: String
  }

data Output
  = ProofIdChanged String
  | LookupRequested

type State =
  { proof :: Q.QueryState String Api.DischargeProof
  , proofId :: String
  }

data Action
  = Receive Input
  | UpdateProofId String
  | RequestLookup

component :: forall q m. MonadAff m => H.Component q Input Output m
component = H.mkComponent
  { initialState: \i -> { proof: i.proof, proofId: i.proofId }
  , render
  , eval: H.mkEval H.defaultEval
      { handleAction = handleAction
      , receive = Just <<< Receive
      }
  }

handleAction :: forall m. MonadAff m => Action -> H.HalogenM State Action () Output m Unit
handleAction = case _ of
  Receive i -> H.modify_ _ { proof = i.proof, proofId = i.proofId }
  UpdateProofId pid -> do
    H.modify_ _ { proofId = pid }
    H.raise $ ProofIdChanged pid
  RequestLookup -> H.raise LookupRequested


render :: forall m. State -> H.ComponentHTML Action () m
render state =
  HH.div [ HP.class_ (H.ClassName "dashboard-panel") ]
    [ HH.div [ HP.class_ (H.ClassName "panel-header") ]
        [ Icon.icon "git-compare"
        , HH.span [ HP.class_ (H.ClassName "panel-title") ] [ HH.text "Discharge Proofs" ]
        ]
    , HH.div [ HP.class_ (H.ClassName "panel-body") ]
        [ HH.div [ HP.class_ (H.ClassName "proof-search") ]
            [ HH.div [ HP.class_ (H.ClassName "search-label") ]
                [ HH.text "Enter a request ID to view its discharge proof" ]
            , HH.div [ HP.class_ (H.ClassName "search-input-wrap") ]
                [ HH.input
                    [ HP.type_ HP.InputText
                    , HP.class_ (H.ClassName "search-input")
                    , HP.placeholder "request-id-here"
                    , HP.value state.proofId
                    , HE.onValueInput UpdateProofId
                    ]
                , HH.button
                    [ HP.class_ (H.ClassName "btn"), HE.onClick \_ -> RequestLookup ]
                    [ HH.text "Lookup" ]
                ]
            ]
        , renderProofState state.proof
        ]
    ]

renderProofState :: forall m. Q.QueryState String Api.DischargeProof -> H.ComponentHTML Action () m
renderProofState qs =
  case Q.getData qs of
    Just p -> renderProof p
    Nothing -> case qs.data of
      NotAsked ->
        HH.div [ HP.class_ (H.ClassName "proof-empty") ]
          [ HH.div [ HP.class_ (H.ClassName "empty-icon") ] [ Icon.icon "git-compare" ]
          , HH.div [ HP.class_ (H.ClassName "empty-text") ] [ HH.text "No proof loaded" ]
          , HH.div [ HP.class_ (H.ClassName "empty-subtext") ]
              [ HH.text "Discharge proofs provide cryptographic evidence that a request accessed only declared resources." ]
          ]
      Loading -> UI.loadingPanel "Looking up discharge proof..."
      Failure err -> UI.errorPanel err
      Success _ -> UI.loadingPanel "Looking up discharge proof..."


-- ════════════════════════════════════════════════════════════════════════════
--                                                              // proof display
-- ════════════════════════════════════════════════════════════════════════════

renderProof :: forall m. Api.DischargeProof -> H.ComponentHTML Action () m
renderProof proof =
  HH.div [ HP.class_ (H.ClassName "proof-details") ]
    [ -- Header
      HH.div [ HP.class_ (H.ClassName "proof-header") ]
        [ HH.div [ HP.class_ (H.ClassName "proof-id") ]
            [ HH.span [ HP.class_ (H.ClassName "proof-label") ] [ HH.text "Build ID" ]
            , HH.span [ HP.class_ (H.ClassName "proof-value mono") ] [ HH.text proof.buildId ]
            ]
        , HH.div [ HP.class_ (H.ClassName $ "proof-sig " <> sigCls) ]
            [ Icon.iconSm sigIcon, HH.text $ " " <> sigText ]
        ]
    -- Timing
    , proofSection "Timing"
        [ HH.div [ HP.class_ (H.ClassName "proof-grid") ]
            [ pc "Start" proof.startTime, pc "End" proof.endTime ] ]
    -- Coeffects
    , proofSection "Coeffects"
        [ UI.badge $ show (Array.length proof.coeffects)
        , HH.div [ HP.class_ (H.ClassName "coeffect-list") ]
            (map renderCoeffect proof.coeffects)
        ]
    -- Network
    , if Array.null proof.networkAccess then HH.text ""
      else proofSection "Network Access"
        [ UI.badge $ show (Array.length proof.networkAccess)
        , HH.div [ HP.class_ (H.ClassName "access-list") ]
            (map renderNetworkAccess proof.networkAccess)
        ]
    -- Auth
    , if Array.null proof.authUsage then HH.text ""
      else proofSection "Auth Usage"
        [ UI.badge $ show (Array.length proof.authUsage)
        , HH.div [ HP.class_ (H.ClassName "access-list") ]
            (map renderAuthUsage proof.authUsage)
        ]
    -- Hashes
    , proofSection "Hashes"
        [ HH.div [ HP.class_ (H.ClassName "hash-item") ]
            [ HH.span [ HP.class_ (H.ClassName "hash-label") ] [ HH.text "Derivation" ]
            , HH.code [ HP.class_ (H.ClassName "hash-value") ] [ HH.text proof.derivationHash ]
            ]
        , HH.div [ HP.class_ (H.ClassName "hash-list") ]
            (map renderOutputHash proof.outputHashes)
        ]
    -- Signature
    , case proof.signature of
        Nothing -> HH.text ""
        Just sig -> proofSection "Cryptographic Signature"
          [ HH.div [ HP.class_ (H.ClassName "signature-details") ]
              [ si "Algorithm" "Ed25519"
              , si "Public Key" (truncHash sig.publicKey)
              , si "Signature" (truncHash sig.signature)
              ]
          ]
    ]
  where
  sigCls = case proof.signature of
    Just _ -> "signed"
    Nothing -> "unsigned"
  sigIcon = case proof.signature of
    Just _ -> "shield-check"
    Nothing -> "minus"
  sigText = case proof.signature of
    Just _ -> "Signed"
    Nothing -> "Unsigned"

proofSection :: forall m. String -> Array (H.ComponentHTML Action () m) -> H.ComponentHTML Action () m
proofSection title kids =
  HH.div [ HP.class_ (H.ClassName "proof-section") ]
    ([ HH.div [ HP.class_ (H.ClassName "proof-section-header") ] [ HH.text title ] ] <> kids)

pc :: forall m. String -> String -> H.ComponentHTML Action () m
pc label value =
  HH.div [ HP.class_ (H.ClassName "proof-cell") ]
    [ HH.span [ HP.class_ (H.ClassName "proof-label") ] [ HH.text label ]
    , HH.span [ HP.class_ (H.ClassName "proof-value mono") ] [ HH.text value ]
    ]

si :: forall m. String -> String -> H.ComponentHTML Action () m
si label value =
  HH.div [ HP.class_ (H.ClassName "sig-item") ]
    [ HH.span [ HP.class_ (H.ClassName "sig-label") ] [ HH.text label ]
    , HH.code [ HP.class_ (H.ClassName "sig-value mono") ] [ HH.text value ]
    ]

renderCoeffect :: forall m. Api.Coeffect -> H.ComponentHTML Action () m
renderCoeffect coeff =
  HH.div [ HP.class_ (H.ClassName $ "coeffect-badge " <> cls coeff) ] [ HH.text $ lbl coeff ]
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

renderNetworkAccess :: forall m. Api.NetworkAccess -> H.ComponentHTML Action () m
renderNetworkAccess na =
  HH.div [ HP.class_ (H.ClassName "access-item") ]
    [ HH.div [ HP.class_ (H.ClassName "access-main") ]
        [ HH.span [ HP.class_ (H.ClassName "access-method") ] [ HH.text na.method ]
        , HH.span [ HP.class_ (H.ClassName "access-url mono") ] [ HH.text na.url ] ]
    , HH.div [ HP.class_ (H.ClassName "access-meta") ]
        [ HH.span [ HP.class_ (H.ClassName "access-time mono") ] [ HH.text na.timestamp ] ]
    ]

renderAuthUsage :: forall m. Api.AuthUsage -> H.ComponentHTML Action () m
renderAuthUsage au =
  HH.div [ HP.class_ (H.ClassName "access-item") ]
    [ HH.div [ HP.class_ (H.ClassName "access-main") ]
        [ HH.span [ HP.class_ (H.ClassName "access-provider") ] [ HH.text au.provider ]
        , case au.scope of
            Just s -> HH.span [ HP.class_ (H.ClassName "access-scope") ] [ HH.text s ]
            Nothing -> HH.text ""
        ]
    , HH.div [ HP.class_ (H.ClassName "access-meta") ]
        [ HH.span [ HP.class_ (H.ClassName "access-time mono") ] [ HH.text au.timestamp ] ]
    ]

renderOutputHash :: forall m. Api.OutputHash -> H.ComponentHTML Action () m
renderOutputHash oh =
  HH.div [ HP.class_ (H.ClassName "hash-item") ]
    [ HH.span [ HP.class_ (H.ClassName "hash-label") ] [ HH.text oh.name ]
    , HH.code [ HP.class_ (H.ClassName "hash-value") ] [ HH.text oh.hash ]
    ]

truncHash :: String -> String
truncHash s =
  if String.length s <= 28 then s
  else String.take 16 s <> "..." <> String.drop (String.length s - 8) s
