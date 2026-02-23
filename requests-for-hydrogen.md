# Requests for Hydrogen — straylight-llm Frontend TODO

> "The sky above the port was the color of television, tuned to a dead channel."

This document outlines all frontend components, features, and integration work needed to complete the **aleph cube architecture** dashboard for straylight-llm.

---

## UI Atoms & Components Needed

These are the fundamental building blocks we need from hydrogen to construct the dashboard.

### Layout Atoms

| Atom | Description | Props |
|------|-------------|-------|
| `Container` | Max-width centered container | `size: sm/md/lg/xl/full` |
| `Grid` | CSS Grid wrapper | `cols: 1-12`, `gap: sm/md/lg` |
| `Flex` | Flexbox wrapper | `direction`, `justify`, `align`, `gap` |
| `Stack` | Vertical stack with consistent spacing | `gap: sm/md/lg` |
| `Sidebar` | Collapsible sidebar panel | `collapsed`, `onToggle` |
| `Panel` | Content panel with optional header | `title`, `actions`, `collapsible` |
| `Divider` | Horizontal/vertical divider | `orientation`, `label` |

### Typography Atoms

| Atom | Description | Props |
|------|-------------|-------|
| `Heading` | h1-h6 headings | `level: 1-6`, `size`, `weight` |
| `Text` | Paragraph/span text | `size: xs/sm/md/lg`, `weight`, `color`, `truncate` |
| `Code` | Inline code | `language` |
| `CodeBlock` | Multi-line code with syntax highlighting | `language`, `lineNumbers`, `copyable` |
| `Label` | Form label | `required`, `htmlFor` |
| `Badge` | Status badge | `variant: success/warning/error/info`, `size` |
| `Timestamp` | Relative/absolute time display | `value`, `format: relative/absolute` |

### Form Atoms

| Atom | Description | Props |
|------|-------------|-------|
| `Input` | Text input | `type`, `placeholder`, `disabled`, `error` |
| `TextArea` | Multi-line input | `rows`, `resize` |
| `Select` | Dropdown select | `options`, `multiple`, `searchable` |
| `Checkbox` | Checkbox input | `checked`, `indeterminate` |
| `Toggle` | Toggle switch | `checked`, `size` |
| `Slider` | Range slider | `min`, `max`, `step`, `value` |
| `Button` | Action button | `variant: primary/secondary/ghost/danger`, `size`, `loading`, `icon` |
| `IconButton` | Icon-only button | `icon`, `label` (for a11y), `size` |
| `ButtonGroup` | Grouped buttons | `attached` |

### Data Display Atoms

| Atom | Description | Props |
|------|-------------|-------|
| `Card` | Content card with shadow | `padding`, `hoverable`, `onClick` |
| `Table` | Data table | `columns`, `data`, `sortable`, `selectable` |
| `List` | Vertical list | `items`, `renderItem`, `dividers` |
| `VirtualList` | Virtualized list for large datasets | `items`, `itemHeight`, `renderItem` |
| `KeyValue` | Key-value pair display | `label`, `value`, `copyable` |
| `Stat` | Statistic display | `label`, `value`, `change`, `changeType: up/down` |
| `Progress` | Progress bar | `value`, `max`, `variant`, `showLabel` |
| `Meter` | Gauge/meter display | `value`, `min`, `max`, `thresholds` |
| `Avatar` | User/provider avatar | `src`, `fallback`, `size` |
| `Icon` | SVG icon | `name`, `size`, `color` |

### Feedback Atoms

| Atom | Description | Props |
|------|-------------|-------|
| `Spinner` | Loading spinner | `size`, `label` |
| `Skeleton` | Loading skeleton placeholder | `variant: text/circle/rect`, `width`, `height` |
| `Toast` | Toast notification | `variant`, `title`, `message`, `action` |
| `Alert` | Inline alert | `variant: info/success/warning/error`, `title`, `dismissible` |
| `Tooltip` | Hover tooltip | `content`, `placement` |
| `Popover` | Click popover | `content`, `trigger`, `placement` |
| `Modal` | Modal dialog | `open`, `onClose`, `title`, `size` |
| `Drawer` | Side drawer | `open`, `onClose`, `position: left/right`, `size` |
| `EmptyState` | Empty state placeholder | `icon`, `title`, `description`, `action` |

### Navigation Atoms

| Atom | Description | Props |
|------|-------------|-------|
| `Tabs` | Tab navigation | `tabs`, `activeTab`, `onChange` |
| `TabPanel` | Tab content panel | `value` |
| `Breadcrumb` | Breadcrumb navigation | `items` |
| `Menu` | Dropdown menu | `items`, `trigger` |
| `MenuItem` | Menu item | `icon`, `label`, `shortcut`, `danger` |
| `Nav` | Vertical navigation | `items`, `activeItem` |
| `NavItem` | Navigation item | `icon`, `label`, `badge`, `active` |

### Chart Atoms

| Atom | Description | Props |
|------|-------------|-------|
| `LineChart` | Time series line chart | `data`, `xAxis`, `yAxis`, `series` |
| `BarChart` | Bar chart | `data`, `orientation: horizontal/vertical` |
| `PieChart` | Pie/donut chart | `data`, `donut` |
| `Sparkline` | Inline sparkline | `data`, `color`, `type: line/bar` |
| `Histogram` | Histogram distribution | `data`, `bins` |

### Specialized Atoms (straylight-specific)

| Atom | Description | Props |
|------|-------------|-------|
| `CircuitBreakerIndicator` | Circuit breaker state viz | `state: closed/open/half-open`, `failures`, `threshold` |
| `ProviderCard` | LLM provider status card | `provider`, `status`, `metrics` |
| `RequestRow` | Request history row | `request`, `onClick`, `selected` |
| `ProofBadge` | Discharge proof indicator | `hasProof`, `verified` |
| `LatencyBadge` | Latency with color coding | `ms`, `thresholds` |
| `TokenUsage` | Token usage display | `prompt`, `completion`, `total` |
| `ModelSelector` | Model picker dropdown | `models`, `selected`, `onChange` |
| `SSEIndicator` | SSE connection status | `connected`, `reconnecting` |
| `CoeffectNode` | Coeffect graph node | `type`, `label`, `active` |
| `HashDisplay` | Truncated hash with copy | `hash`, `truncate` |

---

## Current State

### What Exists

The PureScript/Halogen + Tauri frontend is **partially complete**:

| Component | File | Status |
|-----------|------|--------|
| Main App Shell | `App.purs` | **Complete** - Tab navigation (Health/Models/Proofs) |
| API Client | `API/Client.purs` | **Complete** - Full type definitions |
| Health Status | `Components/HealthStatus.purs` | **Complete** - Basic status cards |
| Models Panel | `Components/ModelsPanel.purs` | **Complete** - Model listing |
| Proof Viewer | `Components/ProofViewer.purs` | **Complete** - Basic proof display |
| Theme System | `themes.css` | **Complete** - 14 themes |
| Tauri Desktop | `src-tauri/` | **Complete** - deb/appimage builds |
| Icon Component | `Components/Icon.purs` | **Complete** - SVG icons |
| Splash Screen | `Components/Splash.purs` | **Complete** - Loading splash |

### Backend Support (Complete)

| Endpoint | Status | Notes |
|----------|--------|-------|
| `GET /health` | **Complete** | Health check |
| `GET /v1/models` | **Complete** | Model listing from all providers |
| `GET /v1/proof/:requestId` | **Complete** | Discharge proof retrieval |
| `POST /v1/chat/completions` | **Complete** | Returns `X-Request-Id` header |
| `POST /v1/chat/completions/stream` | **Complete** | SSE streaming with `X-Request-Id` |
| `POST /v1/completions` | **Complete** | Legacy completions |
| `POST /v1/embeddings` | **Complete** | Embeddings |
| `GET /v1/admin/providers/status` | **Complete** | Provider health + circuit breakers |
| `GET /v1/admin/metrics` | **Complete** | Aggregated metrics |
| `GET /v1/admin/requests?limit=N` | **Complete** | Request history |

### What's Missing

The dashboard needs additional work to fully visualize the aleph cube architecture.

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

**Backend API:** `GET /v1/admin/providers/status` — **Already implemented!**

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

**Backend API:** 
- `GET /v1/admin/requests?limit=N` — **Already implemented!**
- `GET /v1/admin/requests/:requestId` — Still needed (single request detail)

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

**Backend API:** `GET /v1/events` (SSE stream) — **Complete**
```
event: request.started
data: {"request_id":"req_abc","model":"gpt-4","timestamp":"..."}

event: request.completed
data: {"request_id":"req_abc","model":"gpt-4","provider":"venice","success":true,"latency_ms":123.45}

event: proof.generated
data: {"request_id":"req_abc","coeffects":["network","auth:venice"],"signed":true}

event: provider.status
data: {"provider":"vertex","state":"open","failures":5,"threshold":5}
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

**Backend API:** `GET /v1/admin/metrics` — **Already implemented!**

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

## Backend API Status

### All Endpoints Implemented

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Health check |
| `/v1/chat/completions` | POST | Chat completion (returns `X-Request-Id` header) |
| `/v1/chat/completions/stream` | POST | SSE streaming chat |
| `/v1/completions` | POST | Legacy completions |
| `/v1/embeddings` | POST | Embeddings |
| `/v1/models` | GET | Available models from all providers |
| `/v1/proof/:requestId` | GET | Discharge proof retrieval |
| `/v1/proof/:requestId/verify` | POST | Signature verification |
| `/v1/admin/providers/status` | GET | Provider health, circuit breaker state |
| `/v1/admin/metrics` | GET | Aggregated metrics |
| `/v1/admin/requests?limit=N` | GET | Request history with pagination |
| `/v1/admin/requests/:id` | GET | Single request detail with embedded proof |
| `/v1/admin/config` | GET | Current gateway configuration |
| `/v1/admin/config` | PUT | Update config (stub - logs but no-op) |
| `/v1/events` | GET (SSE) | Real-time event stream (keepalive only for now) |

**Note:** Admin endpoints require `Authorization: Bearer <ADMIN_API_KEY>` header.

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

### Dhall Typed Config Available
The backend now exports typed build configuration via Dhall:
```bash
nix build .#dhall-config   # Exports straylight-llm.json with all typed config
nix build .#dhall-verify   # Verifies 37 source files match manifest
```

The Dhall config includes:
- GHC version (GHC912)
- Optimization level (O2)
- All extensions and warning flags
- Complete source manifest (no globs)

---

*Last updated: February 23, 2026*

---

## Summary

### Backend (Complete)
- All core endpoints: health, models, chat, stream, embeddings, completions
- Admin endpoints: providers/status, metrics, requests, requests/:id, config
- Proof endpoints: retrieval, verification
- SSE events endpoint with keepalive
- `X-Request-Id` header on all chat responses
- Discharge proof generation with ed25519 signing
- 213 tests passing, Venice AI live integration verified

### Frontend Components Needed
| Priority | Component | Backend Ready? |
|----------|-----------|----------------|
| HIGH | Provider Status Dashboard | Yes |
| HIGH | Request/Response Timeline | Yes |
| HIGH | SSE Real-Time Updates | Yes |
| MEDIUM | Coeffect Graph Visualization | Yes |
| MEDIUM | Enhanced Proof Inspector | Yes |
| MEDIUM | Metrics Dashboard | Yes |
| LOW | Configuration Panel | Yes (read-only, PUT is stub) |
| LOW | Model Registry Browser | Yes |
| LOW | Playwright Test Runner | N/A |
| LOW | Lean4 Proof Browser | N/A (static files) |
| LOW | SearXNG Integration | No (separate service) |

### UI Atoms Needed from Hydrogen
See "UI Atoms & Components Needed" section above for the full list. Key categories:
- **Layout:** Container, Grid, Flex, Stack, Panel, Sidebar
- **Data Display:** Card, Table, VirtualList, Stat, Badge, KeyValue
- **Feedback:** Toast, Modal, Skeleton, Spinner, Alert
- **Charts:** LineChart, Sparkline, Histogram
- **Specialized:** CircuitBreakerIndicator, ProviderCard, RequestRow, ProofBadge
