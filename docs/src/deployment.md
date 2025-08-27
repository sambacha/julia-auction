# Production Deployment Guide

## Pre-Deployment Checklist

### System Requirements
- [ ] Julia 1.9+ installed
- [ ] 16GB+ RAM available
- [ ] 50GB+ disk space
- [ ] Network connectivity to DeFi protocols
- [ ] Load balancer configured
- [ ] SSL certificates ready

### Configuration
- [ ] Production config reviewed
- [ ] Secrets stored securely
- [ ] Environment variables set
- [ ] Consensus thresholds configured
- [ ] Circuit breakers tuned

### Testing
- [ ] All tests passing
- [ ] Load testing completed
- [ ] Integration tests verified
- [ ] Security audit performed

## Deployment Strategies

### 1. Blue-Green Deployment

```bash
#!/bin/bash
# blue_green_deploy.sh

BLUE_PORT=8080
GREEN_PORT=8081
CURRENT=$(curl -s http://localhost/health/version | jq -r '.color')

if [ "$CURRENT" = "blue" ]; then
    NEW_COLOR="green"
    NEW_PORT=$GREEN_PORT
else
    NEW_COLOR="blue"
    NEW_PORT=$BLUE_PORT
fi

echo "Deploying to $NEW_COLOR environment on port $NEW_PORT"

# Start new version
AUCTION_PORT=$NEW_PORT \
AUCTION_COLOR=$NEW_COLOR \
JULIA_AUCTION_ENV=production \
julia --project=. --threads=auto src/main.jl &

# Wait for health check
while ! curl -s http://localhost:$NEW_PORT/health/ready > /dev/null; do
    sleep 1
done

# Switch load balancer
echo "Switching traffic to $NEW_COLOR"
curl -X POST http://load-balancer/switch -d "color=$NEW_COLOR"

# Stop old version after grace period
sleep 30
OLD_PID=$(lsof -t -i:$([[ "$CURRENT" = "blue" ]] && echo $BLUE_PORT || echo $GREEN_PORT))
kill -TERM $OLD_PID
```

### 2. Rolling Update (Kubernetes)

```yaml
# k8s/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: julia-auction
  namespace: production
spec:
  replicas: 3
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  selector:
    matchLabels:
      app: julia-auction
  template:
    metadata:
      labels:
        app: julia-auction
        version: v1.0.0
    spec:
      containers:
      - name: auction
        image: julia-auction:1.0.0
        ports:
        - containerPort: 8080
        env:
        - name: JULIA_AUCTION_ENV
          value: production
        - name: JULIA_NUM_THREADS
          value: "auto"
        resources:
          requests:
            memory: "16Gi"
            cpu: "4"
          limits:
            memory: "32Gi"
            cpu: "8"
        readinessProbe:
          httpGet:
            path: /health/ready
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 5
        livenessProbe:
          httpGet:
            path: /health/live
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
        volumeMounts:
        - name: config
          mountPath: /app/config
          readOnly: true
      volumes:
      - name: config
        configMap:
          name: auction-config
```

### 3. Canary Deployment

```yaml
# k8s/canary-deployment.yaml
apiVersion: v1
kind: Service
metadata:
  name: julia-auction
spec:
  selector:
    app: julia-auction
  ports:
  - port: 80
    targetPort: 8080

---
# Stable deployment (90% traffic)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: julia-auction-stable
spec:
  replicas: 9
  selector:
    matchLabels:
      app: julia-auction
      version: stable
  template:
    metadata:
      labels:
        app: julia-auction
        version: stable
    spec:
      containers:
      - name: auction
        image: julia-auction:1.0.0

---
# Canary deployment (10% traffic)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: julia-auction-canary
spec:
  replicas: 1
  selector:
    matchLabels:
      app: julia-auction
      version: canary
  template:
    metadata:
      labels:
        app: julia-auction
        version: canary
    spec:
      containers:
      - name: auction
        image: julia-auction:1.1.0
```

## Infrastructure Setup

### Load Balancer Configuration

```nginx
# nginx.conf
upstream auction_backend {
    least_conn;
    server auction1.example.com:8080 weight=1 max_fails=3 fail_timeout=30s;
    server auction2.example.com:8080 weight=1 max_fails=3 fail_timeout=30s;
    server auction3.example.com:8080 weight=1 max_fails=3 fail_timeout=30s;
}

server {
    listen 443 ssl http2;
    server_name api.auction.example.com;
    
    ssl_certificate /etc/ssl/certs/auction.crt;
    ssl_certificate_key /etc/ssl/private/auction.key;
    
    location / {
        proxy_pass http://auction_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Correlation-ID $request_id;
        
        proxy_connect_timeout 5s;
        proxy_send_timeout 10s;
        proxy_read_timeout 10s;
    }
    
    location /health {
        access_log off;
        proxy_pass http://auction_backend/health;
    }
}
```

### Database Setup

```sql
-- PostgreSQL setup for event storage
CREATE DATABASE julia_auction;

CREATE TABLE IF NOT EXISTS events (
    id SERIAL PRIMARY KEY,
    event_id UUID NOT NULL UNIQUE,
    event_type VARCHAR(100) NOT NULL,
    auction_id UUID,
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    data JSONB NOT NULL,
    correlation_id UUID,
    INDEX idx_auction_id (auction_id),
    INDEX idx_timestamp (timestamp),
    INDEX idx_correlation (correlation_id)
);

-- Partitioning for scale
CREATE TABLE events_2024_01 PARTITION OF events
FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');
```

### Redis Configuration

```conf
# redis.conf
maxmemory 8gb
maxmemory-policy allkeys-lru
save 900 1
save 300 10
save 60 10000
appendonly yes
appendfsync everysec
```

## Monitoring Setup

### Prometheus Configuration

```yaml
# prometheus.yml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'julia-auction'
    static_configs:
      - targets: 
        - 'auction1.example.com:8080'
        - 'auction2.example.com:8080'
        - 'auction3.example.com:8080'
    metrics_path: '/metrics'
```

### Grafana Dashboard

```json
{
  "dashboard": {
    "title": "Julia Auction System",
    "panels": [
      {
        "title": "Request Rate",
        "targets": [
          {
            "expr": "rate(auction_requests_total[5m])"
          }
        ]
      },
      {
        "title": "p99 Latency",
        "targets": [
          {
            "expr": "histogram_quantile(0.99, auction_latency_seconds_bucket)"
          }
        ]
      },
      {
        "title": "Circuit Breaker State",
        "targets": [
          {
            "expr": "auction_circuit_breaker_state"
          }
        ]
      }
    ]
  }
}
```

### Alerting Rules

```yaml
# alerts.yml
groups:
  - name: auction_alerts
    rules:
    - alert: HighLatency
      expr: histogram_quantile(0.99, auction_latency_seconds_bucket) > 0.01
      for: 5m
      annotations:
        summary: "High p99 latency detected"
        
    - alert: CircuitBreakerOpen
      expr: auction_circuit_breaker_state == 2
      for: 1m
      annotations:
        summary: "Circuit breaker is open"
        
    - alert: LowConsensus
      expr: auction_consensus_success_rate < 0.9
      for: 5m
      annotations:
        summary: "Low consensus success rate"
```

## Security Configuration

### Network Security

```bash
# iptables rules
iptables -A INPUT -p tcp --dport 8080 -s 10.0.0.0/8 -j ACCEPT
iptables -A INPUT -p tcp --dport 8080 -j DROP

# Rate limiting
iptables -A INPUT -p tcp --dport 8080 -m limit --limit 100/second --limit-burst 200 -j ACCEPT
iptables -A INPUT -p tcp --dport 8080 -j DROP
```

### TLS Configuration

```julia
# src/security/tls.jl
using HTTP
using MbedTLS

function create_tls_server(port::Int)
    cert = MbedTLS.crt_parse_file("/etc/ssl/certs/auction.crt")
    key = MbedTLS.parse_keyfile("/etc/ssl/private/auction.key")
    
    HTTP.serve(port=port, sslconfig=MbedTLS.SSLConfig(cert, key)) do request
        handle_request(request)
    end
end
```

## Performance Tuning

### Julia Optimization

```bash
# Environment variables for performance
export JULIA_NUM_THREADS=auto
export JULIA_EXCLUSIVE=1
export JULIA_HEAP_SIZE_HINT=8G
export JULIA_CPU_TARGET="native"

# Start with optimizations
julia -O3 --inline=yes --check-bounds=no --math-mode=fast \
      --project=. src/main.jl
```

### System Tuning

```bash
# Increase file descriptors
ulimit -n 65536

# TCP tuning
sysctl -w net.core.somaxconn=65536
sysctl -w net.ipv4.tcp_max_syn_backlog=65536
sysctl -w net.ipv4.ip_local_port_range="1024 65535"

# Memory tuning
echo 'vm.swappiness=10' >> /etc/sysctl.conf
echo 'vm.dirty_ratio=15' >> /etc/sysctl.conf
```

## Backup and Recovery

### Backup Strategy

```bash
#!/bin/bash
# backup.sh

BACKUP_DIR="/backup/auction"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Backup configuration
cp -r /app/config $BACKUP_DIR/config_$TIMESTAMP

# Backup event log
pg_dump -h localhost -U auction -d julia_auction \
        -t events > $BACKUP_DIR/events_$TIMESTAMP.sql

# Backup state snapshots
redis-cli --rdb $BACKUP_DIR/redis_$TIMESTAMP.rdb

# Upload to S3
aws s3 sync $BACKUP_DIR s3://auction-backups/
```

### Disaster Recovery

```bash
#!/bin/bash
# restore.sh

RESTORE_DATE=$1
BACKUP_DIR="/backup/auction"

# Stop services
systemctl stop julia-auction

# Restore database
psql -h localhost -U auction -d julia_auction < $BACKUP_DIR/events_$RESTORE_DATE.sql

# Restore Redis
redis-cli --pipe < $BACKUP_DIR/redis_$RESTORE_DATE.rdb

# Restore configuration
cp -r $BACKUP_DIR/config_$RESTORE_DATE/* /app/config/

# Restart services
systemctl start julia-auction
```

## Operational Runbook

### Health Checks

```bash
# Check system health
curl http://localhost:8080/health/ready
curl http://localhost:8080/health/live

# Check metrics
curl http://localhost:8080/metrics | grep auction_

# Check logs
journalctl -u julia-auction -f
```

### Common Issues

#### High Latency
```bash
# Check slow operations
grep "slow_operation" /var/log/auction/app.log

# Profile application
julia --project=. --track-allocation=user src/profile.jl
```

#### Circuit Breaker Tripped
```bash
# Check circuit breaker state
curl http://localhost:8080/admin/circuit-breaker/status

# Reset if needed
curl -X POST http://localhost:8080/admin/circuit-breaker/reset
```

#### Consensus Failures
```bash
# Check participant health
curl http://localhost:8080/admin/participants/health

# View consensus logs
grep "consensus_failed" /var/log/auction/app.log
```

## Scaling Guidelines

### Vertical Scaling
- Add CPU cores for parallel auction processing
- Increase memory for larger batch sizes
- Use NVMe SSDs for event log storage

### Horizontal Scaling
- Add nodes for increased throughput
- Use consistent hashing for load distribution
- Implement sticky sessions for WebSocket connections

## Next Steps

- [Monitoring Guide](monitoring.md) - Set up comprehensive monitoring
- [Troubleshooting Guide](troubleshooting.md) - Common issues and solutions
- [Security Guide](security.md) - Security best practices