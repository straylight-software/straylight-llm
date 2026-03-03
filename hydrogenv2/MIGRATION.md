# Straylight Dashboard — Full Hydrogen Integration

## What Changed

Every Hydrogen module earns its keep.

| Module | What It Does |
|--------|-------------|
| `Hydrogen.Query` | All API fetches go through QueryClient. 10s stale for health, 30s for models, 5s for requests, 60s for proofs. SWR: switching tabs shows cached data instantly, refetches in background. Deduplication prevents double-fetches. |
| `Hydrogen.Data.RemoteData` | All async state is `RemoteData String X`. Eliminates impossible states. Used inside QueryState for the data field. |
| `Hydrogen.Router` | URL-based navigation. Browser back/forward works. Proof links are shareable: `/proofs/:requestId`. Routes are an ADT with `IsRoute` + `RouteMetadata` instances. |
| `Hydrogen.UI.Tabs` | ARIA-compliant sidebar nav. Keyboard: Arrow Up/Down, Home, End. Focus management. Vertical orientation, loop enabled. |
| `Hydrogen.Data.Format` | `formatCount` for tokens/totals. `formatPercent` for error rates. |

## Architecture

```
                         ┌─────────────────┐
                         │   Main.purs     │
                         │                 │
                         │ QueryClient ←───┤── 10s stale / 5min cache
                         │ initialRoute ←──┤── Router.getPathname
                         └────────┬────────┘
                                  │ Input
                         ┌────────▼────────┐
                         │    App.purs     │
                         │                 │
   ┌─────────────────────┤  QueryClient    │
   │                     │  Route          │───── Router.navigate / onPopState
   │    ┌────────────────┤  QueryState × 4 │
   │    │                │  SSE emitter    │───── Stream.EventEmitter
   │    │                └────────┬────────┘
   │    │                         │
   │    │           ┌─────────────┼─────────────┐
   │    │           │             │             │
   │    ▼           ▼             ▼             ▼
   │  Tabs ───► Navigate    SSE events    Panel slots
   │  (sidebar)   │          │               │
   │              │   ┌──────┴──────┐        │
   │              │   │provider.status│       │
   │              │   │  → direct    │       │
   │              │   │  state update│       │
   │              │   │             │       │
   │              │   │request.completed    │
   │              │   │  → Q.invalidate    │
   │              │   │  → refetch if tab  │
   │              │   │             │       │
   │              │   │metrics.update│      │
   │              │   │  → direct   │      │
   │              │   └─────────────┘      │
   │              │                         │
   │              ▼                         ▼
   │         URL update              Panel renders
   │         pushState               QueryState.data
   │         popstate listener       (SWR: stale → show cached + spinner)
   │
   └──► Q.query → check cache → fresh? return
                               → stale? return stale + refetch
                               → missing? fetch + cache + return
```

## Route ADT

```purescript
data Route
  = Health            -- /  or /health
  | Providers         -- /providers
  | Models            -- /models
  | Timeline          -- /timeline
  | Proofs            -- /proofs
  | ProofLookup String -- /proofs/:requestId  (shareable!)
  | NotFound          -- anything else → redirect to /
```

`IsRoute` instance gives you `parseRoute "/proofs/abc" = ProofLookup "abc"` and
`routeToPath (ProofLookup "abc") = "/proofs/abc"`. Bidirectional, no string manipulation
at call sites.

## Query Cache Strategy

| Endpoint | Stale Time | Rationale |
|----------|-----------|-----------|
| `/health` | 10s | Changes rarely, but we want reasonably fresh status |
| `/models` | 30s | Model list is near-static |
| `/requests` | 5s | Changes frequently, SSE also invalidates |
| `/proofs/:id` | 60s | Proofs are immutable once generated |

Cache time is 5 minutes for all queries (unused data is evicted after 5min).

Retries: health gets 2 retries (2s delay), others get 1 retry.

## SSE → Query Integration

```
SSE event               Action
─────────────           ──────
provider.status    →    Direct state update (providers aren't query-backed)
request.completed  →    Q.invalidate(["requests"]) + refetch if Timeline active
metrics.update     →    Direct state update (ephemeral)
proof.generated    →    No-op (proofs fetched on demand)
connection.open    →    Update sseState
connection.error   →    Update sseState
```

## Tabs → Router Integration

```
User clicks "Models" tab (or presses Arrow Down → Enter)
  → Tabs emits ValueChanged "models"
  → App.HandleTabChange
  → Navigate Models
  → Router.navigate (pushState "/models")
  → App.ensureDataForRoute Models
  → Q.query for models (returns cached if fresh, or fetches)

User clicks browser Back button
  → onPopState fires
  → HandlePopState "/providers"
  → parseRoute → Providers
  → App.ensureDataForRoute Providers
  → Tabs receives controlled value = Just "providers"
  → Tab highlight updates
```

## Bugs Fixed

| Bug | Before | After |
|-----|--------|-------|
| ProofViewer lookup button | No `onClick` | Emits `LookupRequested` → parent fetches via Query |
| ProofViewer input field | No `onValueInput` | Emits `ProofIdChanged` |
| Providers tab | "Connecting..." forever | Live SSE data + connection state |
| RequestTimeline | Dead code (never mounted) | Timeline tab, lazy-loaded, fully wired |
| Health on error | Shows nothing | Error panel via QueryState |
| Models loading | "No models loaded" | Skeleton loaders |
| SSE connection | Never started | Started on init, closed on finalize |
| No URL routing | Tabs don't update URL | Full URL routing, back/forward works |
| No keyboard nav | Mouse-only | Arrow keys, Home, End, focus management |
| No SWR | Hard refresh only | Stale data shown instantly, background refetch |
| No cache | Every tab switch refetches | QueryClient caches across tab switches |
| Proof links not shareable | No URL for proofs | `/proofs/:id` routes |

## Files

**New files:**
- `src/Straylight/Route.purs` — Route ADT + IsRoute + RouteMetadata
- `src/Straylight/QueryKeys.purs` — Centralized cache key definitions
- `src/Straylight/Components/UI.purs` — Shared primitives (QueryState-aware)
- `hydrogen-additions.css` — All new CSS (tabs, loading, modals, etc.)

**Rewritten files:**
- `src/Main.purs` — Creates QueryClient, reads initial route, mounts App
- `src/Straylight/App.purs` — Router + Query + Tabs + SSE integration
- `src/Straylight/Components/HealthPanel.purs` — QueryState input
- `src/Straylight/Components/ProvidersPanel.purs` — SSE-driven
- `src/Straylight/Components/ModelsPanel.purs` — QueryState + skeletons
- `src/Straylight/Components/TimelinePanel.purs` — QueryState + filters + modal
- `src/Straylight/Components/ProofPanel.purs` — QueryState + fixed handlers

**Unchanged files:**
- `src/Straylight/API/Client.purs`
- `src/Straylight/API/EventStream.purs`
- `src/Straylight/Streaming.purs` + `.js`
- `src/Straylight/Components/Splash.purs` + `.js`
- `src/Straylight/Components/Icon.purs`
- `index.html` (add one `<link>` for `hydrogen-additions.css`)
- `spago.yaml` (hydrogen already in dependencies)

**Delete:**
- `src/Straylight/Components/HealthStatus.purs` → replaced by `HealthPanel.purs`
- `src/Straylight/Components/ProviderStatus.purs` → replaced by `ProvidersPanel.purs`
- `src/Straylight/Components/RequestTimeline.purs` → replaced by `TimelinePanel.purs`
- `src/Straylight/Components/ProofViewer.purs` → replaced by `ProofPanel.purs`

## Integration Steps

1. Copy all files from this package into `frontend/src/`
2. Add CSS: `<link rel="stylesheet" href="hydrogen-additions.css">` in `index.html`
3. Delete old component files (listed above)
4. Build: `npm run build && npm run bundle`
5. Verify:
   - All 5 tabs render with loading states
   - Arrow keys navigate between sidebar tabs
   - URL bar updates when switching tabs
   - Browser back/forward works
   - Proof lookup updates URL to `/proofs/:id`
   - SSE indicator shows "live" when connected
   - Switching tabs shows cached data (no flash)
   - Titlebar shows "refreshing" during SWR background fetches
