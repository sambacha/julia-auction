# Phantom Auction API

## Overview

The Phantom Auction API provides comprehensive functionality for running price discovery auctions with simulated phantom bidders. This system implements VCG mechanisms for truthful bidding and captures MEV as user surplus.

## Core Modules

### PhantomAuction

Main auction execution module for production phantom auctions.

```julia
using PhantomAuction

# Create and run a phantom auction
auction_result = run_auction(
    request,
    baseline_price,
    baseline_amount,
    deadline;
    global_config = load_config()
)
```

#### Types

##### `ImprovementBid{T}`

Represents a bid for price improvement.

**Fields:**
- `bidder_id::String` - Unique bidder identifier
- `token_pair::Tuple{Int64, Int64}` - Token pair being traded
- `improved_price::T` - Improved price offer
- `volume::T` - Volume to trade
- `priority_fee::T` - Priority fee for execution
- `commitment_hash::Vector{UInt8}` - SHA-256 hash for commitment
- `nonce::Int64` - Nonce for replay protection
- `timestamp::DateTime` - Bid submission time

##### `AuctionResult{T}`

Result of a phantom auction.

**Fields:**
- `winning_bid::Union{ImprovementBid{T}, Nothing}` - Winning bid if any
- `price::T` - Final clearing price
- `amount::T` - Amount traded
- `improvement_bps::Float64` - Price improvement in basis points
- `num_participants::Int64` - Total number of participants
- `auction_duration_ms::Float64` - Auction duration in milliseconds

#### Functions

##### `run_auction(request, baseline_price, baseline_amount, deadline)`

Execute a phantom auction.

**Parameters:**
- `request` - Settlement request object
- `baseline_price::T` - Starting price for the auction
- `baseline_amount::T` - Quantity available
- `deadline::DateTime` - Auction deadline

**Returns:**
- `AuctionResult{T}` - Auction results with winning bid and metrics

**Example:**
```julia
result = run_auction(
    settlement_request,
    100.0,  # baseline price
    1000.0, # baseline amount
    now() + Millisecond(100)
)

println("Clearing price: $(result.price)")
println("Improvement: $(result.improvement_bps) bps")
```

##### `submit_bid(auction, bid)`

Submit a sealed bid to an auction.

**Parameters:**
- `auction::Auction{T}` - Active auction instance
- `bid::ImprovementBid{T}` - Bid to submit

**Returns:**
- `Bool` - Success status

##### `reveal_bid(auction, bid)`

Reveal a previously submitted bid.

**Parameters:**
- `auction::Auction{T}` - Auction in reveal phase
- `bid::ImprovementBid{T}` - Bid to reveal

**Returns:**
- `Bool` - Success status

### VCGMechanism

Implementation of Vickrey-Clarke-Groves mechanism for truthful auctions.

```julia
using VCGMechanism

# Create VCG auction
auction = VCGAuction(
    supply = 1000.0,
    reserve_price = 50.0,
    enable_multi_unit = true
)

# Add bids
push!(auction.bids, VCGBid("bidder1", 55.0, 100.0))
push!(auction.bids, VCGBid("bidder2", 52.0, 200.0))

# Run auction
result = run_vcg_auction(auction)
```

#### Types

##### `VCGBid{T}`

A bid in the VCG auction.

**Fields:**
- `bidder_id::String` - Bidder identifier
- `valuation::T` - Bid value/price
- `quantity::T` - Quantity desired
- `is_phantom::Bool` - Whether this is a phantom bid
- `metadata::Dict{Symbol, Any}` - Additional metadata

##### `VCGAllocation{T}`

Allocation result for a bidder.

**Fields:**
- `bidder_id::String` - Winner identifier
- `quantity::T` - Quantity allocated
- `payment::T` - VCG payment amount
- `utility::T` - Bidder's utility (value - payment)

##### `VCGResult{T}`

Complete VCG auction result.

**Fields:**
- `allocations::Vector{VCGAllocation{T}}` - All allocations
- `social_welfare::T` - Total social welfare
- `total_revenue::T` - Total payments collected
- `efficiency::Float64` - Efficiency ratio
- `phantom_participation_rate::Float64` - Phantom bidder percentage

#### Functions

##### `run_vcg_auction(auction)`

Execute VCG auction mechanism.

**Parameters:**
- `auction::VCGAuction{T}` - Configured auction

**Returns:**
- `VCGResult{T}` - Complete auction results

**Example:**
```julia
result = run_vcg_auction(auction)

println("Social welfare: $(result.social_welfare)")
println("Efficiency: $(result.efficiency)")

for allocation in result.allocations
    println("$(allocation.bidder_id): $(allocation.quantity) @ $(allocation.payment)")
end
```

##### `verify_truthfulness(auction, bidder_id, true_value)`

Verify that truthful bidding is optimal.

**Parameters:**
- `auction::VCGAuction{T}` - Auction instance
- `bidder_id::String` - Bidder to verify
- `true_value::T` - True valuation

**Returns:**
- `Bool` - Whether truthful bidding is optimal

##### `individual_rationality_check(result)`

Verify all participants have non-negative utility.

**Parameters:**
- `result::VCGResult{T}` - Auction result

**Returns:**
- `Bool` - Whether individual rationality holds

### PhantomAuctionSimulator

Advanced simulation framework for testing and analysis.

```julia
using PhantomAuctionSimulator

# Configure simulation
config = SimulationConfig(
    num_real_bidders = 5,
    num_phantom_bidders = 15,
    auction_duration_ms = 100,
    num_simulations = 1000,
    enable_vcg = true
)

# Set market conditions
market = MarketConditions(
    volatility = 0.3,
    liquidity = 0.7,
    trend = 0.1
)

# Create simulator
simulator = PhantomSimulator(config, market)

# Run Monte Carlo simulation
results = run_monte_carlo(simulator, 100.0, 1000.0)
analysis = analyze_results(results)
```

#### Types

##### `SimulationConfig`

Configuration for simulations.

**Fields:**
- `num_real_bidders::Int` - Number of real participants
- `num_phantom_bidders::Int` - Number of phantom bidders
- `auction_duration_ms::Int` - Auction duration
- `num_simulations::Int` - Monte Carlo iterations
- `seed::Union{Int, Nothing}` - Random seed
- `enable_vcg::Bool` - Use VCG mechanism
- `enable_learning::Bool` - Enable adaptive strategies

##### `MarketConditions`

Market environment parameters.

**Fields:**
- `volatility::Float64` - Market volatility (0-1)
- `liquidity::Float64` - Liquidity score (0-1)
- `trend::Float64` - Market trend (-1 to 1)
- `spread::Float64` - Bid-ask spread in bps
- `volume::Float64` - Recent volume
- `correlation_matrix::Matrix{Float64}` - Bidder correlations

##### `SimulationResult`

Result of a single simulation.

**Fields:**
- `winning_bid::Union{SimulatedBid, Nothing}` - Winner
- `clearing_price::Float64` - Final price
- `total_surplus::Float64` - Economic surplus
- `metrics::SimulationMetrics` - Performance metrics
- `all_bids::Vector{SimulatedBid}` - All submitted bids
- `vcg_result::Union{VCGResult, Nothing}` - VCG results
- `convergence_path::Vector{Float64}` - Price path
- `execution_trace::Dict{String, Any}` - Debug information

#### Functions

##### `run_simulation(simulator, baseline_price, baseline_quantity)`

Run single auction simulation.

**Parameters:**
- `simulator::PhantomSimulator` - Configured simulator
- `baseline_price::Float64` - Starting price
- `baseline_quantity::Float64` - Available quantity

**Returns:**
- `SimulationResult` - Complete simulation results

##### `run_monte_carlo(simulator, baseline_price, baseline_quantity)`

Run Monte Carlo simulation.

**Parameters:**
- `simulator::PhantomSimulator` - Configured simulator
- `baseline_price::Float64` - Starting price
- `baseline_quantity::Float64` - Available quantity

**Returns:**
- `Vector{SimulationResult}` - All simulation results

##### `analyze_results(results)`

Analyze simulation results statistically.

**Parameters:**
- `results::Vector{SimulationResult}` - Simulation results

**Returns:**
- `Dict` - Statistical analysis including means, medians, quantiles

**Example Output:**
```julia
{
    "avg_price_improvement" => {
        "mean" => 25.3,
        "median" => 24.8,
        "std" => 5.2,
        "p95" => 35.1
    },
    "mev_capture_rate" => {
        "mean" => 0.823,
        "median" => 0.835,
        "std" => 0.091
    }
}
```

## Bidding Strategies

### Available Strategies

#### `AggressiveStrategy`
- High-frequency bidding (every 10ms)
- Small improvements (10-15 bps)
- Low priority fees
- Best for liquid markets

#### `ConservativeStrategy`
- Low-frequency bidding (every 30ms)
- Large improvements (30-50 bps)
- Higher priority fees
- Best for volatile markets

#### `AdaptiveStrategy`
- Machine learning-based
- Q-learning optimization
- Adjusts to market conditions
- Self-improving over time

#### `RandomWalkStrategy`
- Stochastic process-based
- Geometric Brownian motion
- Jump diffusion model
- Models realistic price discovery

#### `CompetitiveEquilibriumStrategy`
- Game theory optimal
- Nash equilibrium seeking
- Risk-adjusted bidding
- Strategic timing

### Strategy Interface

All strategies implement:

```julia
function generate_bid(
    strategy::BidderStrategy,
    baseline_price::Float64,
    baseline_quantity::Float64,
    market::MarketConditions,
    rng::Random.AbstractRNG
)
```

Returns named tuple or `nothing`:
```julia
(
    price = improved_price,
    quantity = bid_quantity,
    timestamp = arrival_time_ms,
    priority_fee = fee_amount
)
```

## Configuration

### Default Configuration

```toml
[phantom_auction]
bid_probability = 0.3
duration_ms = 100
min_improvement_bps = 10
max_improvement_bps = 50
reveal_delay_ms = 20
min_participants = 2
max_phantom_bidders = 20
enable_vickrey = true
enable_uniform = true
enable_discriminatory = false
```

### Environment Variables

Override configuration via environment variables:

```bash
export AUCTION_PHANTOM_AUCTION_BID_PROBABILITY=0.4
export AUCTION_PHANTOM_AUCTION_MAX_PHANTOM_BIDDERS=30
export AUCTION_PHANTOM_AUCTION_DURATION_MS=80
```

## Usage Examples

### Basic Phantom Auction

```julia
using PhantomAuction

# Simple auction execution
result = run_auction(
    request,
    100.0,   # baseline price
    1000.0,  # quantity
    now() + Millisecond(100)
)

if result.winning_bid !== nothing
    println("Winner: $(result.winning_bid.bidder_id)")
    println("Price: $(result.price)")
    println("Improvement: $(result.improvement_bps) bps")
end
```

### VCG Auction with Analysis

```julia
using VCGMechanism

# Create auction
auction = VCGAuction(1000.0, 50.0, enable_multi_unit=true)

# Add real and phantom bids
for i in 1:5
    push!(auction.bids, VCGBid(
        "real_$i",
        50.0 + rand() * 10,
        rand(50:200),
        is_phantom=false
    ))
end

for i in 1:15
    push!(auction.bids, VCGBid(
        "phantom_$i",
        50.0 + rand() * 15,
        rand(30:150),
        is_phantom=true
    ))
end

# Run and analyze
result = run_vcg_auction(auction)

println("Efficiency: $(result.efficiency)")
println("Revenue: $(result.total_revenue)")
println("Phantom rate: $(result.phantom_participation_rate)")

# Verify properties
@assert individual_rationality_check(result)
@assert result.efficiency > 0.9
```

### Monte Carlo Simulation

```julia
using PhantomAuctionSimulator

# Setup
config = SimulationConfig(
    num_simulations = 1000,
    enable_learning = true
)

market = MarketConditions(
    volatility = 0.3,
    liquidity = 0.7
)

simulator = PhantomSimulator(config, market)

# Run simulations
results = run_monte_carlo(simulator, 100.0, 1000.0)

# Analyze
analysis = analyze_results(results)

# Print summary
for (metric, stats) in analysis
    if isa(stats, Dict)
        println("$metric:")
        println("  Mean: $(stats["mean"])")
        println("  Std: $(stats["std"])")
    end
end
```

### Custom Strategy Implementation

```julia
# Define custom strategy
struct MyCustomStrategy <: BidderStrategy
    aggressiveness::Float64
end

function generate_bid(s::MyCustomStrategy, price, qty, market, rng)
    improvement = 20.0 * s.aggressiveness
    return (
        price = price * (1 + improvement/10000),
        quantity = qty,
        timestamp = rand(rng) * 100,
        priority_fee = price * 0.001
    )
end

# Use in simulation
push!(simulator.strategies, MyCustomStrategy(0.8))
```

## Performance Considerations

### Latency Targets

- Auction execution: <100ms
- Bid collection: 50-70ms
- VCG computation: <10ms
- Result finalization: <20ms

### Optimization Tips

1. **Pre-allocate bid arrays** for known participant counts
2. **Use type-stable functions** with concrete types
3. **Enable multi-threading** for Monte Carlo simulations
4. **Cache VCG computations** when possible
5. **Profile with `@time` and `@benchmark`**

### Scalability

The system scales to:
- 200+ bidders per auction
- 10,000+ auctions per second
- 1M+ Monte Carlo simulations

## Error Handling

Common errors and solutions:

### `InsufficientParticipants`
Not enough participants for valid auction.
- Increase `min_participants` threshold
- Adjust phantom bidder generation

### `InvalidBidParameters`
Bid violates constraints.
- Check improvement bounds
- Verify volume limits
- Validate priority fees

### `AuctionTimeout`
Auction exceeded time limit.
- Increase `duration_ms`
- Optimize bid generation
- Check system load

## Testing

Run comprehensive tests:

```bash
julia test/simulations/phantom_auction_scenarios.jl
```

Key test scenarios:
- Market condition variations
- Strategy performance
- VCG mechanism properties
- MEV protection effectiveness
- Convergence and stability
- Performance benchmarks

## Next Steps

- [Theory Documentation](../theory/phantom_auctions.md) - Mathematical foundation
- [Configuration Guide](../configuration.md) - Detailed configuration
- [Examples](../examples.md) - More usage examples