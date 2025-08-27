# Troubleshooting Guide

## Common Issues and Solutions

This guide helps diagnose and resolve common issues with the Julia Auction System.

## System Startup Issues

### Julia Version Incompatibility

**Problem**: Error message about Julia version when starting.

**Solution**:
```bash
# Check Julia version
julia --version

# Should be 1.9.0 or higher
# If not, upgrade Julia
```

### Package Installation Failures

**Problem**: Errors during `Pkg.instantiate()`.

**Solution**:
```bash
# Clear package cache
rm -rf ~/.julia/packages
rm -rf ~/.julia/compiled

# Reinstall
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

### Configuration File Not Found

**Problem**: System fails to start with config error.

**Solution**:
```bash
# Ensure config files exist
ls config/
# Should show: default.toml, production.toml

# Copy default if missing
cp config/default.toml config/local.toml
```

## Runtime Errors

### High Memory Usage

**Problem**: System consuming excessive memory.

**Diagnosis**:
```julia
# Check memory usage
using InteractiveUtils
varinfo()

# Monitor GC
GC.gc()
@time GC.gc(true)
```

**Solution**:
```bash
# Increase heap size hint
export JULIA_HEAP_SIZE_HINT=8G

# Enable GC logging
export JULIA_GC_ALLOC_PRINT=1
```

### Circuit Breaker Open

**Problem**: Services returning 503 errors.

**Diagnosis**:
```bash
# Check circuit breaker status
curl http://localhost:8080/admin/circuit-breaker/status
```

**Solution**:
```bash
# Reset circuit breaker
curl -X POST http://localhost:8080/admin/circuit-breaker/reset \
  -H "Content-Type: application/json" \
  -d '{"component": "cfmm_bridge"}'
```

### Consensus Failures

**Problem**: Settlements failing due to consensus issues.

**Diagnosis**:
```bash
# Check participant health
curl http://localhost:8080/admin/participants/health

# Check logs for consensus errors
grep "consensus_failed" /var/log/auction/app.log
```

**Solution**:
```julia
# Adjust consensus threshold
ENV["AUCTION_COORDINATOR_CONSENSUS_THRESHOLD"] = "0.6"

# Restart affected participants
```

## Performance Issues

### High Latency

**Problem**: p99 latency exceeding targets.

**Diagnosis**:
```bash
# Check metrics
curl http://localhost:8080/metrics | grep latency

# Profile slow operations
julia --project=. --track-allocation=user src/profile.jl
```

**Solution**:
```julia
# Enable performance optimizations
julia -O3 --inline=yes --check-bounds=no \
      --math-mode=fast --project=. src/main.jl

# Increase thread count
export JULIA_NUM_THREADS=auto
```

### Low Throughput

**Problem**: System not meeting throughput requirements.

**Solution**:
```toml
# config/production.toml
[auction]
max_batch_size = 1000  # Increase batch size

[settlement]
enable_parallel_execution = true
worker_threads = 8
```

## Auction-Specific Issues

### Bids Not Being Accepted

**Problem**: Valid bids being rejected.

**Common Causes**:
1. Bid below reserve price
2. Auction already ended
3. Invalid bid format
4. Rate limiting

**Diagnosis**:
```julia
# Check auction status
response = HTTP.get("http://localhost:8080/v1/auctions/$auction_id")
status = JSON.parse(String(response.body))
println("Status: $(status["status"])")
println("Reserve: $(status["reserve_price"])")
```

### Incorrect Clearing Price

**Problem**: Clearing price seems wrong.

**Diagnosis**:
```julia
# Verify bid data
bids = get_auction_bids(auction_id)
sort!(bids, by=b->b.price, rev=true)

# Calculate theoretical clearing price
supply = get_supply_schedule(auction_id)
theoretical_price = calculate_clearing_price(bids, supply)
```

### Settlement Delays

**Problem**: Settlements taking too long.

**Solution**:
```toml
# config/production.toml
[settlement]
timeout_seconds = 10  # Reduce timeout
max_retries = 2  # Reduce retries
enable_fast_path = true
```

## Network and Connectivity

### Connection Refused

**Problem**: Cannot connect to API.

**Diagnosis**:
```bash
# Check if service is running
ps aux | grep julia

# Check port availability
netstat -an | grep 8080

# Test connectivity
telnet localhost 8080
```

**Solution**:
```bash
# Check firewall
sudo ufw status
sudo ufw allow 8080

# Restart service
systemctl restart julia-auction
```

### WebSocket Disconnections

**Problem**: WebSocket connections dropping.

**Solution**:
```javascript
// Implement reconnection logic
let ws;
let reconnectInterval;

function connect() {
    ws = new WebSocket('ws://localhost:8080/v1/ws');
    
    ws.onclose = () => {
        reconnectInterval = setTimeout(connect, 5000);
    };
    
    ws.onerror = (error) => {
        console.error('WebSocket error:', error);
        ws.close();
    };
}
```

## Database and Storage

### Event Log Corruption

**Problem**: Event log appears corrupted.

**Diagnosis**:
```sql
-- Check event integrity
SELECT COUNT(*), MAX(timestamp), MIN(timestamp)
FROM events
WHERE auction_id = '...';

-- Verify hash chain
SELECT event_id, previous_hash, current_hash
FROM events
ORDER BY timestamp;
```

**Solution**:
```bash
# Restore from backup
./scripts/restore_events.sh $BACKUP_DATE
```

## Monitoring and Logging

### Missing Metrics

**Problem**: Prometheus not collecting metrics.

**Solution**:
```yaml
# prometheus.yml
scrape_configs:
  - job_name: 'julia-auction'
    static_configs:
      - targets: ['localhost:8080']
    metrics_path: '/metrics'
    scrape_interval: 15s
```

### Log Aggregation Issues

**Problem**: Logs not appearing in Elasticsearch.

**Solution**:
```yaml
# filebeat.yml
filebeat.inputs:
- type: log
  enabled: true
  paths:
    - /var/log/auction/*.log
  json.keys_under_root: true
  json.add_error_key: true
```

## Recovery Procedures

### Emergency Shutdown

```bash
#!/bin/bash
# emergency_shutdown.sh

# Stop accepting new requests
curl -X POST http://localhost:8080/admin/maintenance/enable

# Wait for active auctions to complete
sleep 60

# Graceful shutdown
kill -TERM $(pgrep -f julia-auction)
```

### Data Recovery

```bash
#!/bin/bash
# recover_data.sh

# Stop service
systemctl stop julia-auction

# Restore database
pg_restore -d julia_auction backup_$DATE.sql

# Restore Redis
redis-cli --rdb backup_$DATE.rdb

# Verify integrity
julia --project=. scripts/verify_integrity.jl

# Restart service
systemctl start julia-auction
```

## Debug Mode

### Enable Debug Logging

```bash
# Set debug level
export JULIA_DEBUG=all
export AUCTION_LOGGING_LEVEL=debug

# Enable specific modules
export JULIA_DEBUG=AuctionKit,Settlement

# Start with debugging
julia --project=. --depwarn=yes src/main.jl
```

### Performance Profiling

```julia
using Profile
using ProfileView

# Profile specific operation
@profile run_auction(bids, config)

# View results
ProfileView.view()

# Generate report
Profile.print(format=:flat, sortby=:count)
```

## Getting Help

### Log Collection for Support

```bash
#!/bin/bash
# collect_diagnostics.sh

mkdir -p diagnostics
cd diagnostics

# System info
julia --version > julia_version.txt
uname -a > system_info.txt

# Configuration
cp ../config/*.toml .

# Recent logs
tail -n 10000 /var/log/auction/app.log > recent_logs.txt

# Metrics snapshot
curl http://localhost:8080/metrics > metrics.txt

# Create archive
tar -czf diagnostics_$(date +%Y%m%d_%H%M%S).tar.gz *
```

### Support Channels

- GitHub Issues: [Report bugs](https://github.com/julia-auction/julia-auction/issues)
- Documentation: [Full documentation](https://docs.julia-auction.io)
- Community: [Discord server](https://discord.gg/julia-auction)

## Prevention Best Practices

1. **Regular Backups**: Schedule automated backups
2. **Monitor Metrics**: Set up alerts for anomalies
3. **Test Updates**: Use staging environment first
4. **Capacity Planning**: Monitor resource trends
5. **Documentation**: Keep runbooks updated