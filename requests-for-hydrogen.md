# Requests for Hydrogen — straylight-llm Frontend TODO

> "The sky above the port was the color of television, tuned to a dead channel."

This document outlines all frontend components, features, and integration work needed to complete the **aleph cube architecture** dashboard for straylight-llm.

---

## Current State

### What Exists

The PureScript/Halogen + Tauri frontend is **partially complete**:

| Component | File | Status |
|-----------|------|--------|
| Main App Shell | `App.purs` | Complete - Tab navigation (Health/Models/Proofs) |
| API Client | `API/Client.purs` | Complete - Full type definitions |
| Health Status | `Components/HealthStatus.purs` | Complete - Basic status cards |
| Models Panel | `Components/ModelsPanel.purs` | Complete - Model listing |
| Proof Viewer | `Components/ProofViewer.purs` | Complete - Basic proof display |
| Theme System | `themes.css` | Complete - 14 themes |
| Tauri Desktop | `src-tauri/` | Complete - deb/appimage builds |

### What's Missing

The dashboard needs significant work to fully visualize the aleph cube architecture.

---

## Phase 6: Frontend Components

### 1. Provider Status Dashboard (HIGH PRIORITY)

**File:** `frontend/src/Straylight/Components/ProviderStatus.purs`

Display real-time status of all LLM providers with circuit breaker visualization.

- [ ] **Provider Card Component**
  - Provider name, endpoint, status (healthy/degraded/down)
  - Last successful request timestamp
  - Average latency (p50, p95, p99)
  - Error rate percentage
  - Request count (last hour/day)

- [ ] **Circuit Breaker Visualization**
  - State indicator: Closed (green) / Open (red) / Half-Open (yellow)
  - Failure count / threshold display
  - Time until half-open transition
  - Manual reset button

- [ ] **Provider Priority Display**
  - Drag-and-drop reordering (updates config)
  - Fallback chain visualization
  - Active/disabled toggle per provider

**Backend API needed:**
```
GET /v1/providers/status
{
  "providers": [
    {
      "name": "vertex",
      "status": "healthy",
      "circuitBreaker": { "state": "closed", "failures": 0, "threshold": 5 },
      "metrics": { "latencyP50": 120, "latencyP95": 450, "errorRate": 0.02 }
    }
  ]
}
```

---

### 2. Request/Response Timeline (HIGH PRIORITY)

**File:** `frontend/src/Straylight/Components/RequestTimeline.purs`

Chronological view of gateway requests with filtering and drill-down.

- [ ] **Timeline List View**
  - Request ID, timestamp, model, provider
  - Status indicator (success/error/pending)
  - Token usage (prompt/completion)
  - Latency badge
  - Infinite scroll with virtual list

- [ ] **Request Detail Modal**
  - Full request/response JSON (syntax highlighted)
  - Coeffects used (network, auth, etc.)
  - Discharge proof link
  - Retry history (if fallback occurred)
  - Provider chain visualization

- [ ] **Filtering & Search**
  - Filter by provider, model, status
  - Date range picker
  - Search by request ID or content hash
  - Filter by coeffect type

- [ ] **Export Functionality**
  - Export filtered requests as JSON
  - Export as CSV for analysis

**Backend API needed:**
```
GET /v1/requests?limit=50&offset=0&provider=vertex&status=success
GET /v1/requests/:requestId
```

---

### 3. WebSocket/SSE Real-Time Updates (HIGH PRIORITY)

**File:** `frontend/src/Straylight/Streaming.purs`

Real-time updates without polling.

- [ ] **SSE Connection Manager**
  - Connect to `/v1/events` SSE endpoint
  - Automatic reconnection with exponential backoff
  - Connection status indicator in UI

- [ ] **Event Types**
  - `request.started` — new request in progress
  - `request.completed` — request finished (success/error)
  - `proof.generated` — discharge proof ready
  - `provider.status` — circuit breaker state change
  - `metrics.update` — periodic metrics push

- [ ] **Live Updates Integration**
  - Timeline auto-updates with new requests
  - Provider status cards update in real-time
  - Toast notifications for errors
  - Sound/visual alert for critical events

**Backend API needed:**
```
GET /v1/events (SSE stream)
event: request.completed
data: {"requestId": "abc", "provider": "vertex", "status": "success"}
```

---

### 4. Coeffect Graph Visualization (MEDIUM PRIORITY)

**File:** `frontend/src/Straylight/Components/CoeffectGraph.purs`

Visual DAG showing coeffect relationships and data flow.

- [ ] **Graph Rendering**
  - Use purescript-d3 or similar for visualization
  - Nodes: Network, Auth, Filesystem, Pure, Combined
  - Edges: Data flow connections
  - Color coding by coeffect type

- [ ] **Interactive Features**
  - Click node to see details
  - Hover for tooltips
  - Zoom/pan controls
  - Filter by coeffect type

- [ ] **Build Context View**
  - Show which inputs were declared
  - Highlight accessed vs declared (hermeticity)
  - Visual diff: expected vs actual

---

### 5. Enhanced Proof Inspector (MEDIUM PRIORITY)

**File:** `frontend/src/Straylight/Components/ProofViewer.purs` (enhance existing)

Full-featured discharge proof viewer with verification.

- [ ] **Signature Verification**
  - Verify ed25519 signature client-side
  - Show verification status (valid/invalid/unsigned)
  - Display public key (truncated with copy)

- [ ] **Hash Verification**
  - Recompute SHA256 of derivation
  - Compare with stored hash
  - Show match/mismatch status

- [ ] **Evidence Browser**
  - Expandable sections for each evidence type
  - Network access: URL, method, response hash, timestamp
  - Filesystem access: path, mode, content hash
  - Auth usage: provider, scope, timestamp

- [ ] **Export & Share**
  - Copy proof as JSON
  - Download as `.proof.json` file
  - Generate shareable link (if backend supports)

- [ ] **Lean4 Proof Link**
  - Link to corresponding Lean4 theorem
  - Show proof obligation text
  - "Verified by Lean4" badge

---

### 6. Metrics Dashboard (MEDIUM PRIORITY)

**File:** `frontend/src/Straylight/Components/MetricsDashboard.purs`

Observability and performance monitoring.

- [ ] **Token Usage Charts**
  - Line chart: tokens over time
  - Breakdown by model/provider
  - Cost estimation (if rates configured)

- [ ] **Latency Graphs**
  - Histogram of response times
  - P50/P95/P99 trend lines
  - Per-provider latency comparison

- [ ] **Cache Performance**
  - Hit/miss ratio pie chart
  - Cache size usage
  - Top cached requests

- [ ] **Gateway Grade Display**
  - GatewayGrade enum visualization (Safe/Moderate/Hostile)
  - Explanation of current grade
  - Improvement suggestions

**Backend API needed:**
```
GET /v1/metrics
{
  "tokenUsage": { "prompt": 10000, "completion": 5000 },
  "cacheHitRate": 0.75,
  "latency": { "p50": 120, "p95": 450, "p99": 1200 }
}
```

---

### 7. Configuration Panel (LOW PRIORITY)

**File:** `frontend/src/Straylight/Components/ConfigPanel.purs`

View and modify gateway configuration.

- [ ] **Provider Configuration**
  - Enable/disable providers
  - Edit API keys (masked input)
  - Set priority order
  - Configure retry limits

- [ ] **Gateway Settings**
  - Port, host configuration
  - Logging level
  - Cache settings (max size, TTL)
  - Rate limiting

- [ ] **Theme & Preferences**
  - Theme selector (14 themes available)
  - Compact/comfortable density
  - Auto-refresh interval

---

### 8. Model Registry Browser (LOW PRIORITY)

**File:** `frontend/src/Straylight/Components/ModelRegistry.purs`

Browse available models with metadata.

- [ ] **Model Cards**
  - Model name, provider, context window
  - Pricing (input/output per 1k tokens)
  - Capabilities (vision, function calling, etc.)
  - Last used timestamp

- [ ] **Model Search**
  - Filter by provider
  - Filter by capability
  - Sort by price/context/popularity

- [ ] **Model Comparison**
  - Side-by-side comparison view
  - Benchmark results (if available)

---

## Phase 7: Integration Components

### 9. Playwright E2E Test Runner (MEDIUM PRIORITY)

**File:** `frontend/src/Straylight/Components/TestRunner.purs`

UI for running and viewing E2E test results.

- [ ] **Test Suite Browser**
  - List available test suites
  - Run individual tests or full suite
  - Test history with pass/fail trends

- [ ] **Test Result Viewer**
  - Detailed failure messages
  - Screenshot on failure
  - Video playback (if captured)
  - Flaky test detection

---

### 10. Lean4 Proof Browser (LOW PRIORITY)

**File:** `frontend/src/Straylight/Components/ProofBrowser.purs`

Browse and understand the Lean4 proofs.

- [ ] **Theorem List**
  - List all theorems from `proofs/`
  - Group by file (Coeffect, Gateway, Hermetic)
  - Search by name

- [ ] **Theorem Detail**
  - Display theorem statement
  - Show proof (formatted)
  - Link to corresponding Haskell code

- [ ] **Proof Coverage**
  - Which Haskell types have Lean4 proofs
  - Which invariants are proven
  - Gap analysis

---

### 11. SearXNG Search Integration (LOW PRIORITY)

**File:** `frontend/src/Straylight/Components/SearchPanel.purs`

Integrate with gVisor-sandboxed SearXNG for web search.

- [ ] **Search Interface**
  - Search input with autocomplete
  - Category filters (general, images, news)
  - Safe search toggle

- [ ] **Results Display**
  - Result cards with title, snippet, URL
  - Source badges
  - Click to open in browser

- [ ] **Sandbox Status**
  - gVisor sandbox health indicator
  - Resource usage (memory, CPU)
  - Isolation verification

---

## Backend API Additions Required

The following backend endpoints are needed to support the frontend:

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/v1/providers/status` | GET | Provider health, circuit breaker state, metrics |
| `/v1/requests` | GET | Paginated request history with filters |
| `/v1/requests/:id` | GET | Single request detail with full context |
| `/v1/events` | GET (SSE) | Real-time event stream |
| `/v1/metrics` | GET | Aggregated metrics (tokens, latency, cache) |
| `/v1/config` | GET/PUT | Gateway configuration |
| `/v1/models` | GET | Available models with metadata |
| `/v1/proofs/:id/verify` | POST | Server-side signature verification |

---

## UI/UX Improvements

### General Enhancements

- [ ] **Loading States**
  - Skeleton loaders for all data-fetching components
  - Optimistic updates where appropriate

- [ ] **Error Handling**
  - Error boundary components
  - Retry buttons on failed requests
  - User-friendly error messages

- [ ] **Accessibility**
  - ARIA labels on all interactive elements
  - Keyboard navigation
  - Screen reader support
  - High contrast theme

- [ ] **Responsive Design**
  - Mobile-friendly layouts
  - Collapsible sidebar
  - Touch-friendly controls

### Performance

- [ ] **Virtual Scrolling**
  - Use virtual list for timeline/logs
  - Lazy loading for large datasets

- [ ] **Caching**
  - Client-side cache for static data
  - IndexedDB for offline support

- [ ] **Bundle Optimization**
  - Code splitting by route
  - Tree shaking
  - Minification

---

## File Structure (Target)

```
frontend/
├── src/
│   ├── Main.purs
│   └── Straylight/
│       ├── App.purs                      # Main app (exists)
│       ├── Streaming.purs                # SSE/WebSocket (new)
│       ├── API/
│       │   └── Client.purs               # API client (exists)
│       └── Components/
│           ├── ProofViewer.purs          # Proof viewer (enhance)
│           ├── HealthStatus.purs         # Health status (exists)
│           ├── ModelsPanel.purs          # Models list (exists)
│           ├── ProviderStatus.purs       # Provider dashboard (new)
│           ├── RequestTimeline.purs      # Request timeline (new)
│           ├── CoeffectGraph.purs        # Coeffect visualization (new)
│           ├── MetricsDashboard.purs     # Metrics charts (new)
│           ├── ConfigPanel.purs          # Configuration (new)
│           ├── ModelRegistry.purs        # Model browser (new)
│           ├── TestRunner.purs           # E2E test UI (new)
│           ├── ProofBrowser.purs         # Lean4 proofs (new)
│           ├── SearchPanel.purs          # SearXNG (new)
│           ├── Icon.purs                 # Icons (exists)
│           └── Splash.purs               # Splash (exists)
├── test/
│   └── e2e/
│       └── *.spec.ts                     # Playwright tests (new)
└── ...
```

---

## Priority Summary

### Immediate (This Sprint)
1. Provider Status Dashboard
2. Request/Response Timeline
3. WebSocket/SSE Integration

### Next Sprint
4. Coeffect Graph Visualization
5. Enhanced Proof Inspector
6. Metrics Dashboard

### Future
7. Configuration Panel
8. Model Registry Browser
9. Playwright Test Runner
10. Lean4 Proof Browser
11. SearXNG Integration

---

## Notes for Implementation

- Use **hydrogen** package from weyl-ai-machine-city for shared components
- Follow existing code style: explicit imports, no wildcards, no partial functions
- All new components should have corresponding property tests
- Prefer Halogen hooks over class-based components
- Use Argonaut for JSON, not simple-json
- SSE parsing can use `purescript-web-events` or similar

---

*Last updated: 2026-02-23*
