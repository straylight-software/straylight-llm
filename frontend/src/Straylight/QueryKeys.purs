-- | Centralized query key definitions for Hydrogen.Query
-- |
-- | All cache keys are defined here so invalidation is consistent.
-- | Convention: ["resource"] for lists, ["resource", id] for singles.
module Straylight.QueryKeys where

import Prelude

import Hydrogen.Query (QueryKey)


-- | Health endpoint cache key
health :: QueryKey
health = ["health"]

-- | Models list cache key
models :: QueryKey
models = ["models"]

-- | Requests list cache key (filtered)
requests :: QueryKey
requests = ["requests"]

-- | Requests with filter parameters baked into the key
requestsWithFilter :: { provider :: String, model :: String, status :: String, offset :: Int } -> QueryKey
requestsWithFilter f =
  ["requests", f.provider, f.model, f.status, show f.offset]

-- | Single request detail
requestDetail :: String -> QueryKey
requestDetail rid = ["request", rid]

-- | Single discharge proof
proof :: String -> QueryKey
proof rid = ["proof", rid]

-- | Providers (invalidated by SSE, not directly fetched)
providers :: QueryKey
providers = ["providers"]

-- | Dashboard (aggregate provider health)
dashboard :: QueryKey
dashboard = ["dashboard"]
