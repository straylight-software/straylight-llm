-- | Shared UI primitives for the straylight dashboard
-- |
-- | Loading, error, and empty states matching the OmegaCode CSS.
-- | Works with both Hydrogen.Query.QueryState (full metadata) and
-- | bare RemoteData (for components that don't need SWR indicators).
module Straylight.Components.UI
  ( -- * Loading states
    loadingPanel
  , loadingInline
  , skeletonCard
  , skeletonCards
    -- * Error states
  , errorPanel
    -- * Empty states
  , emptyPanel
    -- * RemoteData rendering
  , renderRemote
    -- * QueryState rendering
  , renderQuery
  , renderQueryWith
    -- * Formatting helpers
  , statusDot
  , badge
  , mono
  ) where

import Prelude

import Data.Array (range)
import Halogen.HTML as HH
import Halogen.HTML.Properties as HP
import Hydrogen.Data.RemoteData (RemoteData(..))
import Hydrogen.Query as Q
import Straylight.Components.Icon as Icon


-- ════════════════════════════════════════════════════════════════════════════
--                                                             // loading states
-- ════════════════════════════════════════════════════════════════════════════

loadingPanel :: forall w i. String -> HH.HTML w i
loadingPanel message =
  HH.div [ HP.class_ (HH.ClassName "loading-state") ]
    [ HH.div [ HP.class_ (HH.ClassName "loading-spinner") ] []
    , HH.div [ HP.class_ (HH.ClassName "loading-text") ] [ HH.text message ]
    ]

loadingInline :: forall w i. HH.HTML w i
loadingInline =
  HH.div [ HP.class_ (HH.ClassName "loading-inline") ]
    [ HH.div [ HP.class_ (HH.ClassName "loading-spinner-sm") ] []
    , HH.span [ HP.class_ (HH.ClassName "loading-text-sm") ] [ HH.text "Loading..." ]
    ]

skeletonCard :: forall w i. HH.HTML w i
skeletonCard =
  HH.div [ HP.class_ (HH.ClassName "skeleton-card") ]
    [ HH.div [ HP.class_ (HH.ClassName "skeleton-line skeleton-short") ] []
    , HH.div [ HP.class_ (HH.ClassName "skeleton-line skeleton-wide") ] []
    , HH.div [ HP.class_ (HH.ClassName "skeleton-line skeleton-med") ] []
    ]

skeletonCards :: forall w i. Int -> HH.HTML w i
skeletonCards n =
  HH.div [ HP.class_ (HH.ClassName "skeleton-grid") ]
    (map (\_ -> skeletonCard) (range 1 n))


-- ════════════════════════════════════════════════════════════════════════════
--                                                        // error / empty states
-- ════════════════════════════════════════════════════════════════════════════

errorPanel :: forall w i. String -> HH.HTML w i
errorPanel message =
  HH.div [ HP.class_ (HH.ClassName "error-state") ]
    [ HH.div [ HP.class_ (HH.ClassName "error-icon") ] [ Icon.icon "alert-triangle" ]
    , HH.div [ HP.class_ (HH.ClassName "error-text") ] [ HH.text "Failed to load" ]
    , HH.div [ HP.class_ (HH.ClassName "error-detail") ] [ HH.text message ]
    ]

emptyPanel :: forall w i. String -> String -> String -> HH.HTML w i
emptyPanel iconName title description =
  HH.div [ HP.class_ (HH.ClassName "empty-state") ]
    [ HH.div [ HP.class_ (HH.ClassName "empty-icon") ] [ Icon.icon iconName ]
    , HH.div [ HP.class_ (HH.ClassName "empty-text") ] [ HH.text title ]
    , HH.div [ HP.class_ (HH.ClassName "empty-subtext") ] [ HH.text description ]
    ]


-- ════════════════════════════════════════════════════════════════════════════
--                                                       // RemoteData rendering
-- ════════════════════════════════════════════════════════════════════════════

-- | Render bare RemoteData with loading/error chrome.
renderRemote
  :: forall w i a
   . String
  -> (a -> HH.HTML w i)
  -> RemoteData String a
  -> HH.HTML w i
renderRemote loadMsg render = case _ of
  NotAsked  -> loadingPanel loadMsg
  Loading   -> loadingPanel loadMsg
  Failure e -> errorPanel e
  Success a -> render a


-- ════════════════════════════════════════════════════════════════════════════
--                                                        // QueryState rendering
-- ════════════════════════════════════════════════════════════════════════════

-- | Render a QueryState with stale-while-revalidate awareness.
-- |
-- | When data exists but is stale and refetching, shows data + subtle spinner.
-- | When no data yet, shows loading panel.
-- | When failed and no stale data, shows error panel.
renderQuery
  :: forall w i a
   . String
  -> (a -> HH.HTML w i)
  -> Q.QueryState String a
  -> HH.HTML w i
renderQuery loadMsg render qs =
  case Q.getData qs of
    -- Have data (fresh or stale) → render it
    -- If stale & fetching, the SWR indicator in the titlebar handles it
    Just a -> render a
    -- No data
    Nothing -> case qs.data of
      NotAsked  -> loadingPanel loadMsg
      Loading   -> loadingPanel loadMsg
      Failure e -> errorPanel e
      Success _ -> loadingPanel loadMsg  -- Shouldn't happen, but safe

-- | Render QueryState with custom handlers for each state.
renderQueryWith
  :: forall w i a
   . { loading :: HH.HTML w i
     , failure :: String -> HH.HTML w i
     , success :: a -> HH.HTML w i
     }
  -> Q.QueryState String a
  -> HH.HTML w i
renderQueryWith handlers qs =
  case Q.getData qs of
    Just a -> handlers.success a
    Nothing -> case qs.data of
      NotAsked  -> handlers.loading
      Loading   -> handlers.loading
      Failure e -> handlers.failure e
      Success _ -> handlers.loading


-- ════════════════════════════════════════════════════════════════════════════
--                                                         // formatting helpers
-- ════════════════════════════════════════════════════════════════════════════

statusDot :: forall w i. String -> HH.HTML w i
statusDot status =
  HH.span [ HP.class_ (HH.ClassName $ "status-dot " <> status) ] []

badge :: forall w i. String -> HH.HTML w i
badge text =
  HH.span [ HP.class_ (HH.ClassName "badge") ] [ HH.text text ]

mono :: forall w i. String -> HH.HTML w i
mono text =
  HH.span [ HP.class_ (HH.ClassName "mono") ] [ HH.text text ]
