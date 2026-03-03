# Roadmap

## Current Status: Production Ready

straylight-llm is a production-grade OpenAI-compatible LLM gateway with:
- Multi-provider fallback (Venice, Vertex, Baseten, OpenRouter, Anthropic)
- Circuit breakers and automatic failover
- Ed25519 discharge proofs for every request
- io_uring backend for high-throughput
- 270 tests passing
- Formal verification via Lean4 proofs

---

## v0.1 - Core Gateway (Complete)

- [x] OpenAI-compatible API (`/v1/chat/completions`, `/v1/models`, etc.)
- [x] Multi-provider routing with fallback chain
- [x] Circuit breakers per provider
- [x] Streaming SSE support
- [x] Health checks and metrics
- [x] Discharge proofs (ed25519 signed)
- [x] Effect tracking via graded monads
- [x] Nix build and NixOS module
- [x] 270 tests (property, integration, adversarial, formal)

## v0.2 - Performance & Observability

- [x] Prometheus metrics endpoint (`/metrics`)
- [x] OpenTelemetry tracing (via `OTEL_ENABLED=true`)
- [x] Request/response logging with configurable redaction (via `LOG_LEVEL`)
- [x] Rate limiting per API key (via `RATE_LIMIT_ENABLED=true`, `RATE_LIMIT_RPM`, `RATE_LIMIT_BURST`)
- [x] Request caching (via `CACHE_ENABLED=true`, `CACHE_MAX_SIZE`, `CACHE_TTL_SECONDS`)
- [x] Connection pooling configurable (via `POOL_CONNECTIONS_PER_HOST`, `POOL_IDLE_CONNECTIONS`, `POOL_IDLE_TIMEOUT_SECONDS`)

## v0.3 - Provider Expansion

- [ ] AWS Bedrock provider
- [ ] Azure OpenAI provider
- [ ] Groq provider
- [ ] Together AI provider
- [ ] Custom provider plugin system
- [ ] Provider health dashboard

## v0.4 - Enterprise Features

- [ ] Multi-tenant API key management
- [ ] Usage tracking and billing hooks
- [ ] Admin API for runtime configuration
- [ ] Audit logging
- [ ] RBAC for admin operations

## v0.5 - Advanced Routing

- [ ] Cost-based routing (cheapest available)
- [ ] Latency-based routing (fastest available)
- [ ] Model capability routing (automatic model selection)
- [ ] A/B testing support
- [ ] Canary deployments

## Future

- [ ] WebSocket support for bidirectional streaming
- [ ] Function calling normalization across providers
- [ ] Vision/multimodal request routing
- [ ] Embeddings caching and vector store integration
- [ ] Edge deployment (WASM compilation)

---

## Contributing

See the main [README.md](../README.md) for contribution guidelines.

Priorities are determined by production needs. Open an issue to discuss features.
