# Post-CFMM Settlement API

## Document Information
**Module:** Settlement System
**Purpose:** CFMM integration and price improvement
**Status:** Under Development

## Executive Summary

The Post-CFMM Settlement module integrates auction mechanisms with Constant Function Market Makers. The system discovers prices through auctions then routes execution through optimal CFMM paths. Sub-100ms phantom auctions capture MEV as user surplus.

## Core Components

### SettlementSystem
The main orchestration component manages auction execution and CFMM routing:

```julia
struct SettlementSystem
    config::SettlementConfig
    executor::SettlementExecutor
    monitor::SettlementMonitor
    circuit_breaker::CircuitBreaker
end
```

### SettlementConfig
Configuration parameters control system behavior:

```julia
struct SettlementConfig
    max_auction_duration_ms::Int64    # Auction time limit
    min_improvement_bps::Float64      # Minimum price improvement
    max_slippage_bps::Float64         # Maximum allowed slippage
    enable_phantom::Bool               # Enable phantom auctions
    cfmm_endpoints::Vector{String}    # CFMM API endpoints
end
```

## Primary Functions

### initialize_settlement_system
Creates and configures a new settlement system instance.

```julia
initialize_settlement_system(config::SettlementConfig) -> SettlementSystem
```

**Parameters:**
- `config`: System configuration settings

**Returns:**
- Initialized settlement system ready for processing

**Example:**
```julia
system = initialize_settlement_system(
    SettlementConfig(
        max_auction_duration_ms = 100,
        min_improvement_bps = 10,
        enable_phantom = true
    )
)
```

### process_settlement
Executes a settlement request through auction and CFMM routing.

```julia
process_settlement(
    system::SettlementSystem, 
    request::SettlementRequest
) -> SettlementResult
```

**Parameters:**
- `system`: Active settlement system
- `request`: Settlement parameters and constraints

**Returns:**
- Settlement result with execution details and metrics

**Process Flow:**
1. Validate request parameters
2. Run price discovery auction
3. Calculate optimal CFMM route
4. Execute through selected path
5. Verify price improvement

### execute_phantom_auction
Runs synthetic auctions for price discovery without execution.

```julia
execute_phantom_auction(
    system::SettlementSystem,
    conditions::MarketConditions
) -> PhantomResult
```

**Parameters:**
- `system`: Settlement system instance
- `conditions`: Current market state

**Returns:**
- Discovered price and confidence metrics

**Algorithm:**
1. Generate synthetic bids from market data
2. Run auction simulation
3. Compare with CFMM prices
4. Calculate improvement potential

## CFMM Integration

### route_to_cfmm
Finds optimal execution path through liquidity pools.

```julia
route_to_cfmm(
    order::Order,
    pools::Vector{CFMMPool}
) -> RoutingResult
```

**Routing Algorithm:**
1. Build liquidity graph from available pools
2. Calculate effective depths accounting for fees
3. Apply Bellman-Ford for optimal path
4. Estimate price impact along route
5. Return execution instructions

### calculate_price_impact
Estimates trade impact on pool prices.

```julia
calculate_price_impact(
    pool::CFMMPool,
    amount::Float64
) -> Float64
```

**Constant Product Formula:**
For AMM with reserves (x, y) and constant k:
- Output: Δy = y - (k / (x + Δx))
- Impact: 1 - ((y - Δy) / y)
- Effective price includes fee tier

## Monitoring Functions

### monitor_settlement_health
Tracks system health metrics in real-time.

```julia
monitor_settlement_health(system::SettlementSystem) -> HealthStatus
```

**Monitored Metrics:**
- `latency_p50`: Median processing time
- `latency_p99`: 99th percentile latency
- `success_rate`: Successful settlement percentage
- `breaker_status`: Circuit breaker state

### get_settlement_metrics
Retrieves performance statistics for analysis.

```julia
get_settlement_metrics(
    system::SettlementSystem,
    range::TimeRange
) -> SettlementMetrics
```

**Returned Statistics:**
- Total volume processed
- Average price improvement
- Slippage distribution
- Failure categories

## Circuit Breaker

### circuit_breaker_status
Returns current breaker state for system protection.

```julia
circuit_breaker_status(breaker::CircuitBreaker) -> BreakerStatus
```

**States:**
- `CLOSED`: Normal operation
- `OPEN`: Rejecting requests due to failures
- `HALF_OPEN`: Testing recovery with limited traffic

### trip_circuit_breaker
Manually triggers circuit breaker for intervention.

```julia
trip_circuit_breaker(breaker::CircuitBreaker, reason::String)
```

**Trigger Conditions:**
- Failure rate exceeds threshold
- Downstream service unavailable
- Manual maintenance required

## Type Definitions

### Request Types
```julia
struct SettlementRequest
    request_id::String         # Unique identifier
    asset_pair::String         # Trading pair
    amount::Float64           # Trade size
    side::OrderSide          # BUY or SELL
    max_slippage::Float64    # Slippage tolerance
    deadline::DateTime       # Execution deadline
end

struct Order
    order_id::String         # Order identifier
    trader::String          # Trader address
    asset_in::String        # Input token
    asset_out::String       # Output token
    amount_in::Float64      # Input amount
    min_amount_out::Float64 # Minimum output
end
```

### Result Types
```julia
struct SettlementResult
    request_id::String        # Request reference
    status::SettlementStatus  # SUCCESS/FAILED/PARTIAL
    execution_price::Float64  # Achieved price
    executed_amount::Float64  # Filled amount
    improvement_bps::Float64  # Price improvement
    venue::String            # Execution venue
    gas_used::Int64         # Gas consumption
end

struct PhantomResult
    auction_id::String       # Auction identifier
    discovered_price::Float64 # Auction price
    market_price::Float64    # CFMM price
    improvement::Float64     # Improvement basis points
    confidence::Float64      # Result confidence
end
```

### Pool Types
```julia
struct CFMMPool
    address::String         # Pool contract address
    protocol::String        # UniswapV3, Curve, etc.
    token_a::String        # First token
    token_b::String        # Second token
    reserve_a::Float64     # Token A reserves
    reserve_b::Float64     # Token B reserves
    fee_tier::Float64      # Trading fee percentage
end
```

## Error Handling

### Settlement Errors
The system defines specific error types for failure diagnosis:

```julia
abstract type SettlementError <: Exception end

struct InsufficientLiquidityError <: SettlementError
    requested::Float64     # Requested amount
    available::Float64     # Available liquidity
end

struct SlippageExceededError <: SettlementError
    maximum::Float64       # Maximum allowed
    actual::Float64        # Actual slippage
end

struct TimeoutError <: SettlementError
    limit_ms::Int64       # Time limit
    elapsed_ms::Int64     # Actual duration
end
```

## Configuration

### Basic Setup
Minimal configuration for development:

```toml
[settlement]
max_auction_duration_ms = 100
min_improvement_bps = 10
enable_phantom = true
```

### Production Setup
Optimized settings for production deployment:

```toml
[settlement]
max_auction_duration_ms = 50
min_improvement_bps = 5
max_slippage_bps = 30

[settlement.circuit_breaker]
failure_threshold = 5
recovery_timeout_ms = 30000

[settlement.cfmm]
endpoints = ["https://api.pool1.com", "https://api.pool2.com"]
timeout_ms = 2000
```

## Usage Examples

### Basic Settlement Flow
```julia
# Initialize system
config = SettlementConfig(
    max_auction_duration_ms = 100,
    min_improvement_bps = 10
)
system = initialize_settlement_system(config)

# Execute settlement
request = SettlementRequest(
    asset_pair = "ETH/USDC",
    amount = 10.0,
    side = BUY,
    max_slippage = 0.01
)

result = process_settlement(system, request)
println("Price: $(result.execution_price)")
println("Improvement: $(result.improvement_bps) bps")
```

### Health Monitoring
```julia
# Check system health
health = monitor_settlement_health(system)
if health.breaker_status == OPEN
    @warn "System circuit breaker triggered"
end

# Retrieve metrics
metrics = get_settlement_metrics(system, last_hour)
println("Success rate: $(metrics.success_rate)%")
println("Median latency: $(metrics.latency_p50)ms")
```

## Performance Optimization

### Latency Reduction
The system minimizes latency through:
- Connection pooling for API calls
- Parallel route calculation
- State caching mechanisms
- Pre-computed routing tables

### Throughput Scaling
High throughput achieved via:
- Batch settlement processing
- Asynchronous CFMM queries
- Queue-based load balancing
- Horizontal scaling support

## Related Documentation

- [Augmented Auctions](augmented.md): Core auction mechanisms
- [Phantom Auctions](phantom.md): Synthetic price discovery
- [Architecture Overview](../architecture.md): System design
- [Performance Guide](../guides/performance.md): Optimization techniques

## Summary

The Post-CFMM Settlement API provides efficient integration between auction mechanisms and decentralized liquidity pools. Phantom auctions discover prices while optimal routing ensures best execution. The system captures MEV as user surplus through sub-100ms auction cycles.