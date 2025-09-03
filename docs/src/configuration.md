# Configuration Guide

## Overview

The Julia Auction System uses a hierarchical configuration system that combines TOML files and environment variable overrides.

## Configuration Hierarchy

1. **Default Configuration** (`config/default.toml`) - Base settings
2. **Environment Configuration** (`config/{environment}.toml`) - Environment-specific overrides
3. **Environment Variables** - Runtime overrides
4. **Dynamic Updates** - Runtime configuration changes

## Configuration Files

### Default Configuration Structure

```toml
# config/default.toml

[auction]
max_batch_size = 100
timeout_ms = 100
allow_partial_fills = true

[phantom_auction]
bid_probability = 0.3
duration_ms = 100
min_improvement_bps = 10
max_improvement_bps = 50
reveal_delay_ms = 20
min_participants = 2
max_phantom_bidders = 10
enable_vickrey = true
enable_uniform = true
enable_discriminatory = false

[coordinator]
consensus_threshold = 0.67
timeout_seconds = 30.0
retry_count = 3
heartbeat_interval_seconds = 5.0
heartbeat_timeout_multiplier = 3.0
enable_two_phase_commit = true
max_participants = 100

[settlement]
max_batch_size = 50
base_gas_cost = 100000
gas_limit = 10000000
slippage_tolerance = 0.02
max_slippage_tolerance = 0.05
validation_time_estimate_ms = 20.0
execution_time_estimate_ms = 5.0
enable_atomic_execution = true

[circuit_breaker]
failure_threshold = 3
recovery_threshold = 5
timeout_ms = 30000
recovery_timeout_seconds = 15.0
slow_call_threshold_ms = 100
error_percentage_threshold = 50.0
sliding_window_size = 10
min_calls_before_activation = 5

[monitoring]
enable_metrics = true
metrics_interval_seconds = 10
enable_tracing = true
trace_sample_rate = 0.1
slow_operation_threshold_ms = 100
alert_threshold_percentage = 5.0

[logging]
level = "info"
format = "json"
enable_correlation_ids = true
enable_structured_logging = true
max_file_size_mb = 100
max_files = 10
```

### Production Configuration

```toml
# config/production.toml

[auction]
max_batch_size = 1000
timeout_ms = 50  # Aggressive timeout for production

[phantom_auction]
bid_probability = 0.4
max_phantom_bidders = 20

[coordinator]
consensus_threshold = 0.8  # Higher threshold for production
timeout_seconds = 15.0  # Shorter timeout

[settlement]
max_batch_size = 100
slippage_tolerance = 0.01  # Tighter tolerance

[circuit_breaker]
failure_threshold = 2  # More sensitive
recovery_timeout_seconds = 30.0  # Longer recovery

[monitoring]
metrics_interval_seconds = 5
trace_sample_rate = 0.01  # Lower sampling in production

[logging]
level = "warn"  # Less verbose in production
```

## Environment Variables

### Naming Convention
Environment variables follow the pattern: `AUCTION_{SECTION}_{KEY}`

### Examples

```bash
# Override phantom auction bid probability
export AUCTION_PHANTOM_AUCTION_BID_PROBABILITY=0.5

# Override coordinator consensus threshold
export AUCTION_COORDINATOR_CONSENSUS_THRESHOLD=0.9

# Override settlement batch size
export AUCTION_SETTLEMENT_MAX_BATCH_SIZE=200

# Override circuit breaker timeout
export AUCTION_CIRCUIT_BREAKER_TIMEOUT_MS=60000

# Override logging level
export AUCTION_LOGGING_LEVEL=debug
```

### Special Cases

For nested configurations:
```bash
# Nested config: auction.mechanisms.uniform.elasticity_factor
export AUCTION_MECHANISMS_UNIFORM_ELASTICITY_FACTOR=1.5

# Array values (comma-separated)
export AUCTION_SETTLEMENT_ALLOWED_TOKENS=ETH,USDC,DAI
```

## Using Configuration in Code

### Loading Configuration

```julia
using ConfigManager

# Load configuration based on environment
config = load_config()

# Load specific environment
config = load_config(environment=:production)

# Load with custom path
config = load_config(config_dir="/custom/config")
```

### Accessing Values

```julia
# Type-safe access
bid_probability = get_config(config, "phantom_auction.bid_probability", Float64)
consensus_threshold = get_config(config, "coordinator.consensus_threshold", Float64)

# With defaults
timeout = get_config(config, "auction.timeout_ms", Int64, default=100)

# Nested access
elasticity = get_config(config, "auction.mechanisms.uniform.elasticity_factor", Float64)
```

### Dynamic Updates

```julia
# Update configuration at runtime
update_config!(config, "auction.max_batch_size", 500)

# Reload from files
reload_config!(config)

# Watch for file changes
watch_config!(config) do updated_config
    @info "Configuration updated" changes=updated_config.changes
end
```

## Configuration Validation

### Built-in Validation

```julia
# config/validations.jl

struct ConfigValidation
    rules::Vector{ValidationRule}
end

# Define validation rules
validations = ConfigValidation([
    # Range validation
    RangeRule("phantom_auction.bid_probability", 0.0, 1.0),
    RangeRule("coordinator.consensus_threshold", 0.5, 1.0),
    
    # Required fields
    RequiredRule("settlement.base_gas_cost"),
    RequiredRule("circuit_breaker.failure_threshold"),
    
    # Type validation
    TypeRule("auction.max_batch_size", Int64),
    TypeRule("monitoring.trace_sample_rate", Float64),
    
    # Custom validation
    CustomRule("settlement.slippage_tolerance") do value
        value < get_config(config, "settlement.max_slippage_tolerance", Float64)
    end
])

# Validate configuration
validate_config(config, validations)
```

### Custom Validators

```julia
# Custom validator implementation
function validate_auction_config(config::Config)
    auction_config = config.data["auction"]
    
    # Validate batch size
    if auction_config["max_batch_size"] < 1
        throw(ConfigError("auction.max_batch_size must be positive"))
    end
    
    # Validate timeout
    if auction_config["timeout_ms"] < 10
        throw(ConfigError("auction.timeout_ms too low for production"))
    end
    
    # Cross-validation
    if auction_config["timeout_ms"] > config.data["coordinator"]["timeout_seconds"] * 1000
        throw(ConfigError("Auction timeout exceeds coordinator timeout"))
    end
end
```

## Configuration Best Practices

### 1. Environment-Specific Files

```bash
# Development
cp config/default.toml config/development.toml
# Edit development-specific settings

# Staging
cp config/default.toml config/staging.toml
# Edit staging-specific settings

# Production
cp config/default.toml config/production.toml
# Edit production-specific settings
```

### 2. Secrets Management

```julia
# Never store secrets in config files
# Use environment variables or secret management systems

# Bad - in config file
[database]
password = "secret123"  # Don't do this!

# Good - use environment variable
export AUCTION_DATABASE_PASSWORD=secret123

# Best - use secret management
secret = fetch_secret_from_vault("database/password")
```

### 3. Configuration Documentation

```toml
# Always document configuration options

[auction]
# Maximum number of bids to process in a single batch
# Range: 1-10000, Default: 100
# Production recommendation: 1000
max_batch_size = 100

# Timeout for auction execution in milliseconds
# Range: 10-60000, Default: 100
# Lower values improve latency but may cause timeouts
timeout_ms = 100
```

### 4. Testing Configurations

```julia
# test/config_test.jl

@testset "Configuration Tests" begin
    # Test default configuration loads
    config = load_config(environment=:test)
    @test !isnothing(config)
    
    # Test environment override
    ENV["AUCTION_PHANTOM_AUCTION_BID_PROBABILITY"] = "0.7"
    config = load_config()
    @test get_config(config, "phantom_auction.bid_probability", Float64) == 0.7
    
    # Test validation
    @test_throws ConfigError begin
        update_config!(config, "coordinator.consensus_threshold", 1.5)
    end
end
```

## Configuration Reference

### Auction Configuration

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `max_batch_size` | Int | 100 | Maximum bids per batch |
| `timeout_ms` | Int | 100 | Execution timeout |
| `allow_partial_fills` | Bool | true | Allow partial bid fills |

### Phantom Auction Configuration

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `bid_probability` | Float64 | 0.3 | Probability of phantom bid |
| `duration_ms` | Int | 100 | Auction duration |
| `min_improvement_bps` | Int | 10 | Minimum price improvement |

### Coordinator Configuration

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `consensus_threshold` | Float64 | 0.67 | Required vote percentage |
| `timeout_seconds` | Float64 | 30.0 | Vote collection timeout |
| `retry_count` | Int | 3 | Maximum retry attempts |

### Settlement Configuration

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `max_batch_size` | Int | 50 | Maximum settlements per batch |
| `base_gas_cost` | Int | 100000 | Base gas cost estimate |
| `slippage_tolerance` | Float64 | 0.02 | Maximum allowed slippage |

## Monitoring Configuration

### Metrics Configuration
```toml
[monitoring.metrics]
enable_counters = true
enable_histograms = true
enable_gauges = true
histogram_buckets = [0.001, 0.005, 0.01, 0.05, 0.1, 0.5, 1.0]
```

### Alerting Configuration
```toml
[monitoring.alerts]
enable_email = true
email_recipients = ["ops@example.com"]
enable_slack = true
slack_webhook_url = "${SLACK_WEBHOOK_URL}"
alert_cooldown_minutes = 15
```

## Next Steps

- [API Reference](api_reference.md) - API documentation
- [Deployment Guide](deployment.md) - Production deployment
- [Monitoring Guide](monitoring.md) - Monitoring setup