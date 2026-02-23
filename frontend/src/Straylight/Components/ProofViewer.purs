-- | Discharge proof viewer component
module Straylight.Components.ProofViewer
  ( component
  , Input
  ) where

import Prelude

import Data.Array as Array
import Data.Maybe (Maybe(Nothing, Just))
import Data.String as String
import Effect.Aff.Class (class MonadAff)
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Properties as HP
import Straylight.API.Client as Api
import Straylight.Components.Icon as Icon


type Input =
  { proof :: Maybe Api.DischargeProof
  , proofId :: String
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
                    ]
                , HH.button [ HP.class_ (H.ClassName "btn") ] [ HH.text "Lookup" ]
                ]
            ]
        , case state.proof of
            Nothing ->
              HH.div [ HP.class_ (H.ClassName "proof-empty") ]
                [ HH.div [ HP.class_ (H.ClassName "empty-icon") ]
                    [ Icon.icon "git-compare" ]
                , HH.div [ HP.class_ (H.ClassName "empty-text") ]
                    [ HH.text "No proof loaded" ]
                , HH.div [ HP.class_ (H.ClassName "empty-subtext") ]
                    [ HH.text "Discharge proofs provide cryptographic evidence that a request accessed only declared resources." ]
                ]
            Just p -> renderProof p
        ]
    ]

renderProof :: forall w i. Api.DischargeProof -> HH.HTML w i
renderProof proof =
  HH.div [ HP.class_ (H.ClassName "proof-details") ]
    [ -- Header with build ID and signature status
      HH.div [ HP.class_ (H.ClassName "proof-header") ]
        [ HH.div [ HP.class_ (H.ClassName "proof-id") ]
            [ HH.span [ HP.class_ (H.ClassName "proof-label") ] [ HH.text "Build ID" ]
            , HH.span [ HP.class_ (H.ClassName "proof-value mono") ] [ HH.text proof.buildId ]
            ]
        , HH.div [ HP.class_ (H.ClassName $ "proof-sig " <> sigClass) ]
            [ Icon.iconSm sigIcon
            , HH.text sigText
            ]
        ]
    
    -- Timing
    , HH.div [ HP.class_ (H.ClassName "proof-section") ]
        [ HH.div [ HP.class_ (H.ClassName "proof-section-header") ] [ HH.text "Timing" ]
        , HH.div [ HP.class_ (H.ClassName "proof-grid") ]
            [ HH.div [ HP.class_ (H.ClassName "proof-cell") ]
                [ HH.span [ HP.class_ (H.ClassName "proof-label") ] [ HH.text "Start" ]
                , HH.span [ HP.class_ (H.ClassName "proof-value mono") ] [ HH.text proof.startTime ]
                ]
            , HH.div [ HP.class_ (H.ClassName "proof-cell") ]
                [ HH.span [ HP.class_ (H.ClassName "proof-label") ] [ HH.text "End" ]
                , HH.span [ HP.class_ (H.ClassName "proof-value mono") ] [ HH.text proof.endTime ]
                ]
            ]
        ]
    
    -- Coeffects
    , HH.div [ HP.class_ (H.ClassName "proof-section") ]
        [ HH.div [ HP.class_ (H.ClassName "proof-section-header") ]
            [ HH.text "Coeffects"
            , HH.span [ HP.class_ (H.ClassName "badge") ]
                [ HH.text $ show (Array.length proof.coeffects) ]
            ]
        , HH.div [ HP.class_ (H.ClassName "coeffect-list") ]
            (map renderCoeffect proof.coeffects)
        ]
    
    -- Network Access
    , if Array.null proof.networkAccess
        then HH.text ""
        else HH.div [ HP.class_ (H.ClassName "proof-section") ]
          [ HH.div [ HP.class_ (H.ClassName "proof-section-header") ]
              [ HH.text "Network Access"
              , HH.span [ HP.class_ (H.ClassName "badge") ]
                  [ HH.text $ show (Array.length proof.networkAccess) ]
              ]
          , HH.div [ HP.class_ (H.ClassName "access-list") ]
              (map renderNetworkAccess proof.networkAccess)
          ]
    
    -- Auth Usage
    , if Array.null proof.authUsage
        then HH.text ""
        else HH.div [ HP.class_ (H.ClassName "proof-section") ]
          [ HH.div [ HP.class_ (H.ClassName "proof-section-header") ]
              [ HH.text "Auth Usage"
              , HH.span [ HP.class_ (H.ClassName "badge") ]
                  [ HH.text $ show (Array.length proof.authUsage) ]
              ]
          , HH.div [ HP.class_ (H.ClassName "access-list") ]
              (map renderAuthUsage proof.authUsage)
          ]
    
    -- Hashes
    , HH.div [ HP.class_ (H.ClassName "proof-section") ]
        [ HH.div [ HP.class_ (H.ClassName "proof-section-header") ] [ HH.text "Hashes" ]
        , HH.div [ HP.class_ (H.ClassName "hash-item") ]
            [ HH.span [ HP.class_ (H.ClassName "hash-label") ] [ HH.text "Derivation" ]
            , HH.code [ HP.class_ (H.ClassName "hash-value") ] [ HH.text proof.derivationHash ]
            ]
        , HH.div [ HP.class_ (H.ClassName "hash-list") ]
            (map renderOutputHash proof.outputHashes)
        ]
    
    -- Signature Details (if signed)
    , case proof.signature of
        Nothing -> HH.text ""
        Just sig -> HH.div [ HP.class_ (H.ClassName "proof-section signature-section") ]
          [ HH.div [ HP.class_ (H.ClassName "proof-section-header") ]
              [ Icon.iconSm "shield-check"
              , HH.text " Cryptographic Signature"
              ]
          , HH.div [ HP.class_ (H.ClassName "signature-details") ]
              [ HH.div [ HP.class_ (H.ClassName "sig-item") ]
                  [ HH.span [ HP.class_ (H.ClassName "sig-label") ] [ HH.text "Algorithm" ]
                  , HH.span [ HP.class_ (H.ClassName "sig-value") ] [ HH.text "Ed25519" ]
                  ]
              , HH.div [ HP.class_ (H.ClassName "sig-item") ]
                  [ HH.span [ HP.class_ (H.ClassName "sig-label") ] [ HH.text "Public Key" ]
                  , HH.code [ HP.class_ (H.ClassName "sig-value mono") ] 
                      [ HH.text $ truncateHash sig.publicKey ]
                  ]
              , HH.div [ HP.class_ (H.ClassName "sig-item") ]
                  [ HH.span [ HP.class_ (H.ClassName "sig-label") ] [ HH.text "Signature" ]
                  , HH.code [ HP.class_ (H.ClassName "sig-value mono") ] 
                      [ HH.text $ truncateHash sig.signature ]
                  ]
              ]
          ]
    ]
  where
  sigClass = case proof.signature of
    Just _ -> "signed"
    Nothing -> "unsigned"
  sigIcon = case proof.signature of
    Just _ -> "check"
    Nothing -> "minus"
  sigText = case proof.signature of
    Just _ -> "Signed"
    Nothing -> "Unsigned"

renderCoeffect :: forall w i. Api.Coeffect -> HH.HTML w i
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

renderNetworkAccess :: forall w i. Api.NetworkAccess -> HH.HTML w i
renderNetworkAccess na =
  HH.div [ HP.class_ (H.ClassName "access-item") ]
    [ HH.div [ HP.class_ (H.ClassName "access-main") ]
        [ HH.span [ HP.class_ (H.ClassName "access-method") ] [ HH.text na.method ]
        , HH.span [ HP.class_ (H.ClassName "access-url") ] [ HH.text na.url ]
        ]
    , HH.div [ HP.class_ (H.ClassName "access-meta") ]
        [ HH.span [ HP.class_ (H.ClassName "access-time") ] [ HH.text na.timestamp ]
        ]
    ]

renderAuthUsage :: forall w i. Api.AuthUsage -> HH.HTML w i
renderAuthUsage au =
  HH.div [ HP.class_ (H.ClassName "access-item") ]
    [ HH.div [ HP.class_ (H.ClassName "access-main") ]
        [ HH.span [ HP.class_ (H.ClassName "access-provider") ] [ HH.text au.provider ]
        , case au.scope of
            Just s -> HH.span [ HP.class_ (H.ClassName "access-scope") ] [ HH.text s ]
            Nothing -> HH.text ""
        ]
    , HH.div [ HP.class_ (H.ClassName "access-meta") ]
        [ HH.span [ HP.class_ (H.ClassName "access-time") ] [ HH.text au.timestamp ]
        ]
    ]

renderOutputHash :: forall w i. Api.OutputHash -> HH.HTML w i
renderOutputHash oh =
  HH.div [ HP.class_ (H.ClassName "hash-item") ]
    [ HH.span [ HP.class_ (H.ClassName "hash-label") ] [ HH.text oh.name ]
    , HH.code [ HP.class_ (H.ClassName "hash-value") ] [ HH.text oh.hash ]
    ]

-- | Truncate a hash/key for display (show first 16 + last 8 chars)
truncateHash :: String -> String
truncateHash s =
  if String.length s <= 28
    then s
    else String.take 16 s <> "..." <> String.drop (String.length s - 8) s
