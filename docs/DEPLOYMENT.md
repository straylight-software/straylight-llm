# Deployment Guide

This guide covers production deployment of straylight-llm.

## Deployment Options

### 1. Container (Recommended)

```bash
# Build container image
nix build .#straylight-llm

# Load into Docker
docker load < result

# Run
docker run -d \
  --name straylight-llm \
  -p 8080:8080 \
  -e OPENROUTER_API_KEY=sk-or-... \
  -e ANTHROPIC_API_KEY=sk-ant-... \
  --restart unless-stopped \
  straylight-llm:latest
```

### 2. Kubernetes

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: straylight-llm
spec:
  replicas: 3
  selector:
    matchLabels:
      app: straylight-llm
  template:
    metadata:
      labels:
        app: straylight-llm
    spec:
      containers:
      - name: straylight-llm
        image: ghcr.io/justinfleek/straylight-llm:latest
        ports:
        - containerPort: 8080
        env:
        - name: OPENROUTER_API_KEY
          valueFrom:
            secretKeyRef:
              name: straylight-secrets
              key: openrouter-api-key
        resources:
          requests:
            memory: "256Mi"
            cpu: "500m"
          limits:
            memory: "1Gi"
            cpu: "2000m"
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: straylight-llm
spec:
  selector:
    app: straylight-llm
  ports:
  - port: 80
    targetPort: 8080
  type: ClusterIP
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: straylight-llm
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  rules:
  - host: llm.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: straylight-llm
            port:
              number: 80
  tls:
  - hosts:
    - llm.example.com
    secretName: straylight-llm-tls
```

### 3. NixOS Module

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    straylight-llm.url = "github:justinfleek/straylight-llm";
    agenix.url = "github:ryantm/agenix";
  };
  
  outputs = { self, nixpkgs, straylight-llm, agenix, ... }: {
    nixosConfigurations.myserver = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        agenix.nixosModules.default
        straylight-llm.nixosModules.default
        ./configuration.nix
      ];
    };
  };
}

# configuration.nix
{ config, ... }: {
  age.secrets.openrouter-api-key.file = ./secrets/openrouter-api-key.age;
  
  services.straylight-llm = {
    enable = true;
    port = 8080;
    environmentFile = config.age.secrets.openrouter-api-key.path;
  };
  
  # Reverse proxy with TLS
  services.caddy = {
    enable = true;
    virtualHosts."llm.example.com".extraConfig = ''
      reverse_proxy localhost:8080
    '';
  };
  
  networking.firewall.allowedTCPPorts = [ 80 443 ];
}
```

### 4. Systemd Service (Binary)

```bash
# Build binary
nix build .#straylight-llm
sudo cp result/bin/straylight-llm /usr/local/bin/

# Create systemd service
sudo tee /etc/systemd/system/straylight-llm.service << 'EOF'
[Unit]
Description=straylight-llm LLM Gateway
After=network.target

[Service]
Type=simple
User=straylight
Group=straylight
ExecStart=/usr/local/bin/straylight-llm
Restart=always
RestartSec=5

EnvironmentFile=/etc/straylight-llm/env
Environment=STRAYLIGHT_PORT=8080

# Hardening
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes

[Install]
WantedBy=multi-user.target
EOF

# Create env file
sudo mkdir -p /etc/straylight-llm
sudo tee /etc/straylight-llm/env << 'EOF'
OPENROUTER_API_KEY=sk-or-...
ANTHROPIC_API_KEY=sk-ant-...
EOF
sudo chmod 600 /etc/straylight-llm/env

# Enable and start
sudo systemctl daemon-reload
sudo systemctl enable straylight-llm
sudo systemctl start straylight-llm
```

## Production Checklist

### Security

- [ ] **TLS Termination** — Use a reverse proxy (Caddy, nginx, Traefik) for HTTPS
- [ ] **API Keys in Secrets** — Use Kubernetes secrets, agenix, or Vault
- [ ] **Network Isolation** — Run in private network, expose only via load balancer
- [ ] **Request Authentication** — Add auth at the reverse proxy level
- [ ] **Rate Limiting** — Configure rate limits for public endpoints

### Reliability

- [ ] **Multiple Replicas** — Run 2+ instances for high availability
- [ ] **Health Checks** — Configure liveness and readiness probes
- [ ] **Circuit Breakers** — Tune `STRAYLIGHT_CIRCUIT_*` settings
- [ ] **Timeouts** — Set appropriate `STRAYLIGHT_REQUEST_TIMEOUT_S`

### Observability

- [ ] **Logging** — Aggregate logs to centralized system
- [ ] **Metrics** — Scrape `/metrics` with Prometheus
- [ ] **Tracing** — Request IDs are included in responses
- [ ] **Alerting** — Alert on circuit breaker state, error rates

### Performance

- [ ] **Resource Limits** — Set memory and CPU limits
- [ ] **Connection Pooling** — Built-in, no configuration needed
- [ ] **CDN/Caching** — Not applicable (dynamic responses)

## Reverse Proxy Configuration

### Caddy

```
llm.example.com {
    reverse_proxy localhost:8080
}
```

### Nginx

```nginx
upstream straylight {
    server localhost:8080;
    keepalive 32;
}

server {
    listen 443 ssl http2;
    server_name llm.example.com;
    
    ssl_certificate /etc/letsencrypt/live/llm.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/llm.example.com/privkey.pem;
    
    location / {
        proxy_pass http://straylight;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_read_timeout 300s;
    }
    
    # SSE endpoints need special handling
    location ~ ^/v1/(events|chat/completions/stream) {
        proxy_pass http://straylight;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_buffering off;
        proxy_cache off;
        proxy_read_timeout 86400s;
    }
}
```

### Traefik

```yaml
http:
  routers:
    straylight:
      rule: "Host(`llm.example.com`)"
      service: straylight
      tls:
        certResolver: letsencrypt
  services:
    straylight:
      loadBalancer:
        servers:
          - url: "http://localhost:8080"
```

## Monitoring

### Prometheus

```yaml
scrape_configs:
  - job_name: 'straylight-llm'
    static_configs:
      - targets: ['localhost:8080']
    metrics_path: /metrics
```

### Grafana Dashboard

Key metrics to monitor:

- `straylight_requests_total` — Request rate by provider
- `straylight_request_latency_seconds` — Latency distribution
- `straylight_circuit_breaker_state` — Circuit breaker health
- `straylight_provider_errors_total` — Error rate by provider

### Alerting Rules

```yaml
groups:
- name: straylight
  rules:
  - alert: StraylightAllCircuitsOpen
    expr: sum(straylight_circuit_breaker_state{state="open"}) == count(straylight_circuit_breaker_state)
    for: 1m
    labels:
      severity: critical
    annotations:
      summary: All straylight-llm circuit breakers are open
      
  - alert: StraylightHighErrorRate
    expr: rate(straylight_provider_errors_total[5m]) > 0.1
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: High error rate in straylight-llm
```

## Scaling

### Horizontal Scaling

straylight-llm is stateless and can be horizontally scaled. State (circuit breaker state, proof cache) is per-instance.

For shared state across instances, consider:
- Redis for proof cache
- etcd for circuit breaker coordination

### Vertical Scaling

- **Memory**: ~256MB base, +1MB per 1000 concurrent connections
- **CPU**: Linear scaling with request rate
- **Recommended**: 2 CPU cores, 1GB RAM per instance for typical workloads

## Upgrades

### Rolling Updates

```bash
# Build new version
nix build .#straylight-llm

# Kubernetes
kubectl set image deployment/straylight-llm \
  straylight-llm=ghcr.io/justinfleek/straylight-llm:v0.2.0

# Docker
docker pull straylight-llm:latest
docker-compose up -d
```

### Blue-Green Deployment

1. Deploy new version alongside existing
2. Test new version
3. Switch traffic at load balancer
4. Drain and remove old version
