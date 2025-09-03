# Post-CFMM Settlement API

## Overview

The Post-CFMM Settlement module provides integration between auction mechanisms and Constant Function Market Makers (CFMMs) for improved price discovery and execution.

## Core Components

### Settlement System

```julia
struct SettlementSystem
    config::SettlementConfig
    executor::SettlementExecutor
    monitor::SettlementMonitor
    circuit_breaker::CircuitBreaker
end
```

### Configuration

```julia
struct SettlementConfig
    max_auction_duration_ms::Int64
    min_improvement_bps::Float64
    max_slippage_bps::Float64
    enable_phantom::Bool
    cfmm_endpoints::Vector{String}
    retry_config::RetryConfig
end
```

## Main Functions

### `initialize_settlement_system`

```julia
initialize_settlement_system(config::SettlementConfig) -> SettlementSystem

Initialize the settlement system with specified configuration.

# Arguments
- `config::SettlementConfig`: System configuration

# Returns
- `SettlementSystem`: Initialized settlement system

# Example
system = initialize_settlement_system(SettlementConfig(
    max_auction_duration_ms = 100,
    min_improvement_bps = 10,
    max_slippage_bps = 50,
    enable_phantom = true
))
```

### `process_settlement`

```julia
process_settlement(system::SettlementSystem, request::SettlementRequest) -> SettlementResult

Process a settlement request through auction and CFMM routing.

# Arguments
- `system::SettlementSystem`: Settlement system instance
- `request::SettlementRequest`: Settlement parameters

# Returns
- `SettlementResult`: Settlement outcome with execution details

# Example
result = process_settlement(system, SettlementRequest(
    asset_pair = "ETH/USDC",
    amount = 100.0,
    side = BUY,
    max_slippage = 0.01
))
```

### `execute_phantom_auction`

```julia
execute_phantom_auction(
    system::SettlementSystem, 
    market_conditions::MarketConditions
) -> PhantomResult

Run a phantom auction for price discovery without execution.

# Arguments
- `system::SettlementSystem`: Settlement system
- `market_conditions::MarketConditions`: Current market state

# Returns
- `PhantomResult`: Synthetic auction results

# Algorithm
1. Generate synthetic bids based on market conditions
2. Run auction simulation
3. Compare with CFMM prices
4. Return price improvement metrics
```

## CFMM Integration

### `route_to_cfmm`

```julia
route_to_cfmm(
    order::Order,
    cfmm_pools::Vector{CFMMPool}
) -> RoutingResult

Find optimal routing through CFMM pools.

# Arguments
- `order::Order`: Order to execute
- `cfmm_pools::Vector{CFMMPool}`: Available liquidity pools

# Returns
- `RoutingResult`: Optimal path and expected execution

# Routing Algorithm
1. Build liquidity graph
2. Calculate pool depths
3. Find optimal path (Bellman-Ford)
4. Account for price impact
5. Return execution path
```

### `calculate_price_impact`

```julia
calculate_price_impact(
    pool::CFMMPool,
    trade_amount::Float64
) -> Float64

Calculate expected price impact for a trade.

# Formula
For constant product AMM (x * y = k):
- Price impact = 1 - (y - ”y) / y
- Where ”y = trade output amount
```

## Monitoring Functions

### `monitor_settlement_health`

```julia
monitor_settlement_health(system::SettlementSystem) -> HealthStatus

Monitor system health metrics.

# Returns
HealthStatus with:
- `latency_p50`: Median latency
- `latency_p99`: 99th percentile latency
- `success_rate`: Settlement success percentage
- `circuit_breaker_status`: Open/Closed/HalfOpen
```

### `get_settlement_metrics`

```julia
get_settlement_metrics(
    system::SettlementSystem,
    time_range::TimeRange
) -> SettlementMetrics

Retrieve settlement performance metrics.

# Returns
- Total volume processed
- Average price improvement
- Slippage statistics
- Failed settlement count
```

## Circuit Breaker

### `circuit_breaker_status`

```julia
circuit_breaker_status(breaker::CircuitBreaker) -> BreakerStatus

Check circuit breaker state.

# States
- `CLOSED`: Normal operation
- `OPEN`: Failing, rejecting requests
- `HALF_OPEN`: Testing recovery
```

### `trip_circuit_breaker`

```julia
trip_circuit_breaker(breaker::CircuitBreaker, reason::String)

Manually trip the circuit breaker.

# Use Cases
- Excessive failures detected
- Manual intervention required
- Downstream service unavailable
```

## Types Reference

### Request Types

```julia
struct SettlementRequest
    request_id::String
    asset_pair::String
    amount::Float64
    side::OrderSide
    max_slippage::Float64
    deadline::DateTime
    metadata::Dict{String, Any}
end

struct Order
    order_id::String
    trader::String
    asset_in::String
    asset_out::String
    amount_in::Float64
    min_amount_out::Float64
    deadline::DateTime
end
```

### Result Types

```julia
struct SettlementResult
    request_id::String
    status::SettlementStatus
    execution_price::Float64
    executed_amount::Float64
    price_improvement::Float64
    execution_venue::String
    gas_used::Int64
    settlement_time::DateTime
end

struct PhantomResult
    auction_id::String
    discovered_price::Float64
    market_price::Float64
    price_improvement_bps::Float64
    confidence_score::Float64
    bid_participation::Int
end
```

### Pool Types

```julia
struct CFMMPool
    pool_address::String
    protocol::String  # "UniswapV2", "UniswapV3", etc.
    token_a::String
    token_b::String
    reserve_a::Float64
    reserve_b::Float64
    fee_tier::Float64
    liquidity::Float64
end
```

## Error Handling

### Settlement Errors

```julia
abstract type SettlementError <: Exception end

struct InsufficientLiquidityError <: SettlementError
    requested_amount::Float64
    available_amount::Float64
end

struct SlippageExceededError <: SettlementError
    max_slippage::Float64
    actual_slippage::Float64
end

struct SettlementTimeoutError <: SettlementError
    timeout_ms::Int64
    elapsed_ms::Int64
end
```

## Configuration Examples

### Basic Configuration

```toml
[settlement]
max_auction_duration_ms = 100
min_improvement_bps = 10
max_slippage_bps = 50
enable_phantom = true

[settlement.retry]
max_attempts = 3
base_delay_ms = 100
max_delay_ms = 5000
```

### Production Configuration

```toml
[settlement]
max_auction_duration_ms = 50
min_improvement_bps = 5
max_slippage_bps = 30
enable_phantom = true

[settlement.cfmm]
endpoints = [
    "https://api.uniswap.v3.example.com",
    "https://api.sushiswap.example.com"
]
timeout_ms = 2000

[settlement.circuit_breaker]
failure_threshold = 5
recovery_timeout_ms = 30000
half_open_requests = 3
```

## Usage Examples

### Basic Settlement

```julia
using PostCFMMSettlement

# Initialize system
config = SettlementConfig(
    max_auction_duration_ms = 100,
    min_improvement_bps = 10
)
system = initialize_settlement_system(config)

# Process settlement
request = SettlementRequest(
    asset_pair = "ETH/USDC",
    amount = 10.0,
    side = BUY,
    max_slippage = 0.01
)

result = process_settlement(system, request)
println("Executed at: \$(result.execution_price)")
println("Price improvement: \$(result.price_improvement) bps")
```

### With Monitoring

```julia
# Monitor health
health = monitor_settlement_health(system)
if health.circuit_breaker_status == OPEN
    @warn "Circuit breaker is open!"
end

# Get metrics
metrics = get_settlement_metrics(
    system,
    TimeRange(now() - Hour(1), now())
)
println("Success rate: \$(metrics.success_rate)%")
```

## Performance Considerations

### Latency Optimization
- Connection pooling for CFMM queries
- Parallel route calculation
- Caching of pool states
- Pre-computed routing tables

### Throughput
- Batch settlement processing
- Async CFMM interactions
- Queue-based request handling
- Horizontal scaling support

## See Also

- [Augmented Auctions API](augmented.md)
- [Phantom Auctions API](phantom.md)
- [Architecture Overview](../architecture.md)
- [Performance Guide](../performance.md)