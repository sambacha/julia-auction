# Monitoring Guide

## Overview

The Julia Auction System provides comprehensive monitoring through metrics, logging, tracing, and health checks. This guide covers setup, configuration, and best practices for production monitoring.

## Metrics

### Metric Types

#### Counters
Track cumulative values that only increase:
```julia
auction_requests_total
auction_bids_submitted_total
auction_settlements_completed_total
auction_errors_total
```

#### Gauges
Track values that can go up or down:
```julia
auction_active_participants
auction_pending_settlements
auction_circuit_breaker_state
auction_memory_usage_bytes
```

#### Histograms
Track distributions of values:
```julia
auction_latency_seconds
auction_bid_processing_duration_seconds
auction_settlement_duration_seconds
auction_consensus_time_seconds
```

### Key Metrics to Monitor

#### Performance Metrics
```prometheus
# p99 Latency
histogram_quantile(0.99, 
  rate(auction_latency_seconds_bucket[5m])
)

# Request Rate
rate(auction_requests_total[5m])

# Error Rate
rate(auction_errors_total[5m]) / rate(auction_requests_total[5m])

# Throughput
rate(auction_bids_processed_total[5m])
```

#### Business Metrics
```prometheus
# Auction Success Rate
rate(auction_completed_total[5m]) / rate(auction_created_total[5m])

# Average Clearing Price
rate(auction_revenue_total[5m]) / rate(auction_quantity_allocated_total[5m])

# Bid Participation Rate
auction_unique_bidders_total / auction_created_total

# Price Improvement
avg(auction_phantom_improvement_basis_points)
```

#### System Health
```prometheus
# Circuit Breaker Status
auction_circuit_breaker_state{component="cfmm_bridge"}

# Consensus Health
auction_consensus_success_rate

# Memory Usage
auction_memory_usage_bytes / auction_memory_limit_bytes

# Thread Pool Utilization
auction_thread_pool_active / auction_thread_pool_size
```

## Logging

### Log Levels

```julia
# Configure log levels
using Logging

# Development
global_logger(ConsoleLogger(stdout, Logging.Debug))

# Production
global_logger(JSONLogger(stdout, Logging.Info))
```

### Structured Logging

```julia
@info "Auction completed" auction_id=auction.id \
                         clearing_price=result.clearing_price \
                         total_bids=length(bids) \
                         duration_ms=elapsed_ms \
                         correlation_id=get_correlation_id()

@error "Settlement failed" auction_id=auction.id \
                          error=e \
                          retry_count=retries \
                          correlation_id=get_correlation_id()
```

### Log Aggregation

#### Elasticsearch Configuration
```yaml
# filebeat.yml
filebeat.inputs:
- type: log
  enabled: true
  paths:
    - /var/log/auction/*.log
  json.keys_under_root: true
  json.add_error_key: true
  
output.elasticsearch:
  hosts: ["elasticsearch:9200"]
  index: "auction-logs-%{+yyyy.MM.dd}"
```

#### Logstash Pipeline
```ruby
# logstash.conf
filter {
  json {
    source => "message"
  }
  
  date {
    match => [ "timestamp", "ISO8601" ]
  }
  
  mutate {
    add_field => {
      "environment" => "${JULIA_AUCTION_ENV}"
    }
  }
  
  if [level] == "ERROR" {
    mutate {
      add_tag => [ "alert" ]
    }
  }
}
```

## Distributed Tracing

### OpenTelemetry Setup

```julia
using OpenTelemetry

# Initialize tracer
tracer = Tracer(
    "julia-auction",
    exporter = OTLPExporter("http://jaeger:4317")
)

# Trace auction execution
function execute_auction_with_tracing(auction, bids)
    span = start_span(tracer, "execute_auction",
        attributes = Dict(
            "auction.id" => auction.id,
            "auction.type" => auction.type,
            "bid.count" => length(bids)
        )
    )
    
    try
        # Trace sub-operations
        validation_span = start_span(tracer, "validate_bids", parent=span)
        validate_bids(bids)
        end_span(validation_span)
        
        discovery_span = start_span(tracer, "price_discovery", parent=span)
        result = discover_price(auction, bids)
        end_span(discovery_span)
        
        return result
    finally
        end_span(span)
    end
end
```

### Trace Analysis

Key traces to monitor:
- End-to-end auction execution
- Settlement coordination
- CFMM routing optimization
- Consensus protocol

## Dashboards

### Grafana Dashboard Configuration

```json
{
  "dashboard": {
    "title": "Julia Auction System",
    "rows": [
      {
        "title": "Overview",
        "panels": [
          {
            "title": "Request Rate",
            "targets": [{
              "expr": "rate(auction_requests_total[5m])"
            }]
          },
          {
            "title": "Error Rate",
            "targets": [{
              "expr": "rate(auction_errors_total[5m])"
            }]
          },
          {
            "title": "p99 Latency",
            "targets": [{
              "expr": "histogram_quantile(0.99, rate(auction_latency_seconds_bucket[5m]))"
            }]
          }
        ]
      },
      {
        "title": "Auctions",
        "panels": [
          {
            "title": "Active Auctions",
            "targets": [{
              "expr": "auction_active_count"
            }]
          },
          {
            "title": "Clearing Prices",
            "targets": [{
              "expr": "auction_clearing_price"
            }]
          },
          {
            "title": "Bid Volume",
            "targets": [{
              "expr": "rate(auction_bid_volume_total[5m])"
            }]
          }
        ]
      },
      {
        "title": "Settlement",
        "panels": [
          {
            "title": "Settlement Queue",
            "targets": [{
              "expr": "auction_pending_settlements"
            }]
          },
          {
            "title": "Consensus Success Rate",
            "targets": [{
              "expr": "rate(consensus_success_total[5m]) / rate(consensus_attempts_total[5m])"
            }]
          },
          {
            "title": "CFMM Route Efficiency",
            "targets": [{
              "expr": "auction_route_efficiency"
            }]
          }
        ]
      }
    ]
  }
}
```

### Key Performance Indicators (KPIs)

```yaml
kpis:
  - name: "System Availability"
    query: "avg_over_time(up{job='auction'}[24h])"
    target: ">= 0.999"
    
  - name: "p99 Latency"
    query: "histogram_quantile(0.99, rate(auction_latency_seconds_bucket[1h]))"
    target: "< 0.01"
    
  - name: "Error Rate"
    query: "rate(auction_errors_total[1h]) / rate(auction_requests_total[1h])"
    target: "< 0.001"
    
  - name: "Auction Success Rate"
    query: "rate(auction_completed_total[1h]) / rate(auction_created_total[1h])"
    target: ">= 0.95"
```

## Alerting

### Alert Rules

```yaml
groups:
  - name: auction_critical
    interval: 30s
    rules:
      - alert: HighErrorRate
        expr: |
          rate(auction_errors_total[5m]) / rate(auction_requests_total[5m]) > 0.01
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "High error rate detected"
          description: "Error rate is {{ $value | humanizePercentage }}"
          
      - alert: CircuitBreakerOpen
        expr: auction_circuit_breaker_state == 2
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Circuit breaker {{ $labels.component }} is open"
          
      - alert: ConsensusFailure
        expr: |
          rate(consensus_failed_total[5m]) > 0
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Consensus failures detected"

  - name: auction_warning
    interval: 1m
    rules:
      - alert: HighLatency
        expr: |
          histogram_quantile(0.99, rate(auction_latency_seconds_bucket[5m])) > 0.015
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "p99 latency above threshold"
          
      - alert: LowParticipation
        expr: auction_active_participants < 2
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Low participant count"
```

### Alert Routing

```yaml
# alertmanager.yml
route:
  group_by: ['alertname', 'severity']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 1h
  receiver: 'default'
  routes:
    - match:
        severity: critical
      receiver: 'pagerduty'
      continue: true
    - match:
        severity: warning
      receiver: 'slack'

receivers:
  - name: 'default'
    
  - name: 'pagerduty'
    pagerduty_configs:
      - service_key: '<service-key>'
        
  - name: 'slack'
    slack_configs:
      - api_url: '<webhook-url>'
        channel: '#auction-alerts'
```

## Health Checks

### Readiness Probe

```julia
function readiness_check() :: HealthStatus
    checks = [
        check_database_connection(),
        check_redis_connection(),
        check_cfmm_bridge(),
        check_config_loaded()
    ]
    
    if all(c.healthy for c in checks)
        return HealthStatus(
            status = "ready",
            checks = checks
        )
    else
        return HealthStatus(
            status = "not_ready",
            checks = checks,
            http_code = 503
        )
    end
end
```

### Liveness Probe

```julia
function liveness_check() :: HealthStatus
    # Simple check that the process is responsive
    return HealthStatus(
        status = "alive",
        uptime = uptime_seconds()
    )
end
```

### Startup Probe

```julia
function startup_check() :: HealthStatus
    if system_initialized()
        return HealthStatus(status = "started")
    else
        return HealthStatus(
            status = "starting",
            http_code = 503
        )
    end
end
```

## Performance Profiling

### CPU Profiling

```julia
using Profile

# Start profiling
Profile.@profile begin
    run_auction_batch(auctions, bids)
end

# Analyze results
Profile.print(format=:flat, sortby=:count)

# Generate flame graph
using ProfileView
ProfileView.view()
```

### Memory Profiling

```julia
# Track allocations
julia --track-allocation=user script.jl

# Analyze allocation data
using Coverage
analyze_malloc(".")

# Memory snapshots
using InteractiveUtils
varinfo()
```

### Benchmark Suite

```julia
using BenchmarkTools

# Benchmark critical paths
suite = BenchmarkGroup()

suite["auction"]["execution"] = @benchmarkable run_auction($bids, $config)
suite["settlement"]["routing"] = @benchmarkable optimize_route($routes)
suite["consensus"]["voting"] = @benchmarkable collect_votes($participants)

# Run benchmarks
results = run(suite)

# Compare with baseline
baseline = load("benchmark_baseline.json")
comparison = judge(results, baseline)
```

## Custom Metrics

### Business Metrics Implementation

```julia
# Define custom metrics
mutable struct AuctionMetrics
    auctions_created::Counter
    clearing_prices::Histogram
    bid_shading::Gauge
    revenue::Counter
end

# Update metrics
function record_auction_metrics(result::AuctionResult)
    increment!(metrics.auctions_created)
    observe!(metrics.clearing_prices, result.clearing_price)
    set!(metrics.bid_shading, calculate_bid_shading(result))
    increment!(metrics.revenue, result.total_revenue)
end

# Export for Prometheus
function export_metrics()
    return """
    # HELP auction_clearing_price Auction clearing prices
    # TYPE auction_clearing_price histogram
    auction_clearing_price_bucket{le="10"} $(metrics.clearing_prices.buckets[1])
    auction_clearing_price_bucket{le="50"} $(metrics.clearing_prices.buckets[2])
    auction_clearing_price_bucket{le="100"} $(metrics.clearing_prices.buckets[3])
    auction_clearing_price_sum $(metrics.clearing_prices.sum)
    auction_clearing_price_count $(metrics.clearing_prices.count)
    """
end
```

## Monitoring Best Practices

### 1. SLI/SLO Definition

```yaml
slis:
  - name: "Request Success Rate"
    query: "1 - (rate(auction_errors_total[5m]) / rate(auction_requests_total[5m]))"
    
  - name: "Request Latency"
    query: "histogram_quantile(0.99, rate(auction_latency_seconds_bucket[5m]))"
    
slos:
  - sli: "Request Success Rate"
    objective: 99.9%
    window: 30d
    
  - sli: "Request Latency"
    objective: 10ms
    window: 30d
```

### 2. Capacity Planning

Monitor resource utilization trends:
- CPU usage patterns
- Memory growth over time
- Network bandwidth consumption
- Storage growth rate

### 3. Anomaly Detection

```julia
using Statistics

function detect_anomalies(metrics::Vector{Float64}, window::Int = 100)
    baseline = mean(metrics[1:window])
    stddev = std(metrics[1:window])
    
    anomalies = []
    for (i, value) in enumerate(metrics[window+1:end])
        if abs(value - baseline) > 3 * stddev
            push!(anomalies, (index=i+window, value=value))
        end
        # Update rolling statistics
        baseline = 0.95 * baseline + 0.05 * value
    end
    
    return anomalies
end
```

## Next Steps

- [Troubleshooting Guide](troubleshooting.md) - Common issues and solutions
- [Performance Tuning](performance.md) - Optimization techniques
- [Security Guide](security.md) - Security monitoring