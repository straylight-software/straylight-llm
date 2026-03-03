-- | Type-safe route definitions for the straylight dashboard
-- |
-- | Routes are an ADT, not strings. URL parsing and serialization is
-- | defined once via IsRoute, used everywhere — navigation, SSG metadata,
-- | active-tab highlighting, and URL bar sync.
module Straylight.Route
  ( Route(..)
  , allTabs
  , routeToTabValue
  , tabValueToRoute
  , routeIcon
  , routeLabel
  ) where

import Prelude

import Data.Maybe (Maybe(..))
import Data.String (Pattern(..), indexOf, drop, take) as S
import Hydrogen.Router (class IsRoute, class RouteMetadata)


-- | Dashboard routes.
-- |
-- | Each constructor maps to a sidebar tab. ProofLookup carries the
-- | request ID in the URL so proof links are shareable.
data Route
  = Health
  | Providers
  | Models
  | Timeline
  | Proofs
  | ProofLookup String  -- /proofs/:requestId
  | NotFound

derive instance eqRoute :: Eq Route

-- | All tab routes in sidebar order (excludes ProofLookup and NotFound).
allTabs :: Array Route
allTabs = [ Health, Providers, Models, Timeline, Proofs ]


-- ════════════════════════════════════════════════════════════════════════════
--                                                           // IsRoute instance
-- ════════════════════════════════════════════════════════════════════════════

instance isRouteRoute :: IsRoute Route where
  parseRoute "/" = Health
  parseRoute "/health" = Health
  parseRoute "/providers" = Providers
  parseRoute "/models" = Models
  parseRoute "/timeline" = Timeline
  parseRoute "/proofs" = Proofs
  parseRoute path
    | isProofPath path = ProofLookup (extractProofId path)
    | otherwise = NotFound

  routeToPath Health = "/"
  routeToPath Providers = "/providers"
  routeToPath Models = "/models"
  routeToPath Timeline = "/timeline"
  routeToPath Proofs = "/proofs"
  routeToPath (ProofLookup rid) = "/proofs/" <> rid
  routeToPath NotFound = "/"

isProofPath :: String -> Boolean
isProofPath path = case S.indexOf (S.Pattern "/proofs/") path of
  Just 0 -> true
  _ -> false

extractProofId :: String -> String
extractProofId path = S.drop 8 path  -- drop "/proofs/"


-- ════════════════════════════════════════════════════════════════════════════
--                                                      // RouteMetadata instance
-- ════════════════════════════════════════════════════════════════════════════

instance routeMetadataRoute :: RouteMetadata Route where
  isProtected _ = false  -- Dashboard is local-only, no auth
  isStaticRoute Health = true
  isStaticRoute _ = false
  routeTitle Health = "Gateway Health — Straylight"
  routeTitle Providers = "Providers — Straylight"
  routeTitle Models = "Models — Straylight"
  routeTitle Timeline = "Request Timeline — Straylight"
  routeTitle Proofs = "Discharge Proofs — Straylight"
  routeTitle (ProofLookup _) = "Proof Detail — Straylight"
  routeTitle NotFound = "Straylight Gateway"
  routeDescription _ = "Straylight LLM Gateway Dashboard"
  routeOgImage _ = Nothing


-- ════════════════════════════════════════════════════════════════════════════
--                                                         // tab ↔ route bridge
-- ════════════════════════════════════════════════════════════════════════════

-- | Convert route to Hydrogen.UI.Tabs value string.
routeToTabValue :: Route -> String
routeToTabValue Health = "health"
routeToTabValue Providers = "providers"
routeToTabValue Models = "models"
routeToTabValue Timeline = "timeline"
routeToTabValue Proofs = "proofs"
routeToTabValue (ProofLookup _) = "proofs"
routeToTabValue NotFound = "health"

-- | Convert Hydrogen.UI.Tabs value string back to route.
tabValueToRoute :: String -> Route
tabValueToRoute "health" = Health
tabValueToRoute "providers" = Providers
tabValueToRoute "models" = Models
tabValueToRoute "timeline" = Timeline
tabValueToRoute "proofs" = Proofs
tabValueToRoute _ = Health

-- | Icon name for each route (matches existing Icon.purs sprites).
routeIcon :: Route -> String
routeIcon Health = "gauge"
routeIcon Providers = "activity"
routeIcon Models = "list-checks"
routeIcon Timeline = "clock"
routeIcon Proofs = "git-compare"
routeIcon (ProofLookup _) = "git-compare"
routeIcon NotFound = "gauge"

-- | Human label for each route.
routeLabel :: Route -> String
routeLabel Health = "Health"
routeLabel Providers = "Providers"
routeLabel Models = "Models"
routeLabel Timeline = "Timeline"
routeLabel Proofs = "Proofs"
routeLabel (ProofLookup _) = "Proofs"
routeLabel NotFound = "Health"
