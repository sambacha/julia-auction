# Augmented Uniform Price Auction API

## Overview

This reference documents the augmented uniform price auction module.

!!! note "Module Structure"
    The module contains four components:
    1. **Supply Schedules** - Configure elastic supply
    2. **Tie-Breaking** - Allocate tied bids strategically
    3. **Auction Execution** - Run auctions
    4. **Analysis Tools** - Calculate metrics

## Types

### Core Types

- `ElasticSupplySchedule` - Elastic supply configuration
- `SupplyPoint` - Supply point with price and quantity
- `Bid` - Bid structure with bidder info
- `BidAllocation` - Allocation result
- `AuctionConfig` - Auction configuration
- `AuctionResult` - Complete auction results

### Enumerations

- `ElasticityType` - EXPONENTIAL, LINEAR, or LOGARITHMIC

### Tie-Breaking Strategies

- `TieBreakingStrategy` - Abstract type for tie-breaking
- `StandardTieBreaking` - Traditional highest-bids-first
- `AugmentedTieBreaking` - Advanced mechanism with quantity weighting

## Functions

### Supply Schedule Management

- `create_elastic_schedule` - Creates elastic supply schedule with parameters
- `calculate_supply_at_price` - Calculates supply quantity at given price

#### Example: Creating Custom Supply Curves

```jldoctest supply
julia> using AugmentedUniformPriceAuction

julia> # Exponential supply curve
       exp_supply = create_elastic_schedule(
           base_quantity = 1000.0,
           price_floor = 20.0,
           price_ceiling = 80.0,
           elasticity_type = EXPONENTIAL,
           elasticity_factor = 1.5
       );

julia> # Calculate supply at different prices
       supply_at_30 = calculate_supply_at_price(exp_supply, 30.0);

julia> supply_at_50 = calculate_supply_at_price(exp_supply, 50.0);

julia> supply_at_50 > supply_at_30
true

julia> # Linear supply for comparison
       lin_supply = create_elastic_schedule(
           base_quantity = 1000.0,
           price_floor = 20.0,
           price_ceiling = 80.0,
           elasticity_type = LINEAR
       );

julia> calculate_supply_at_price(lin_supply, 50.0) < supply_at_50
true
```

### Auction Execution

- `run_auction` - Executes complete auction with bids and configuration
- `find_clearing_price` - Finds market-clearing price
- `validate_bids` - Validates bids against auction rules

!!! tip "Performance Optimization"
    For auctions with more than 10,000 bids:
    - Pre-sort bids by price
    - Use binary search for clearing price
    - Enable partial fills

### Analysis Functions

- `analyze_bid_shading` - Estimates strategic bid shading percentage
- `calculate_efficiency` - Calculates auction efficiency score
- `analyze_market_concentration` - Computes Herfindahl index
- `calculate_price_discovery_efficiency` - Measures price discovery quality

## Detailed Function Documentation

### `run_auction`

```@doc
run_auction(bids::Vector{Bid}, config::AuctionConfig) -> AuctionResult

Executes an augmented uniform price auction.

# Arguments
- `bids::Vector{Bid}`: Collection of bids to process
- `config::AuctionConfig`: Auction configuration parameters

# Returns
- `AuctionResult`: Auction results with allocations and metrics

# Algorithm
1. Validate all bids against auction rules
2. Find clearing price using binary search
3. Allocate to bids above clearing price
4. Apply tie-breaking for bids at clearing price
5. Calculate performance metrics

# Example
```jldoctest auction
julia> using AugmentedUniformPriceAuction

julia> bids = [
           Bid("alice", 100.0, 55.0),
           Bid("bob", 150.0, 52.0),
           Bid("charlie", 120.0, 52.0),  # Tie with bob
           Bid("dave", 80.0, 48.0)
       ];

julia> config = AuctionConfig(
           supply_schedule = create_elastic_schedule(
               base_quantity = 300.0,
               price_floor = 40.0
           ),
           tie_breaking = AugmentedTieBreaking(0.7, 0.3),
           reserve_price = 45.0
       );

julia> result = run_auction(bids, config);

julia> result.clearing_price >= 45.0  # Above reserve
true

julia> length(result.allocations) > 0
true

julia> result.num_tie_breaks  # Bob and Charlie tied
2
```

# Performance
- Time complexity: O(n log n) for n bids
- Space complexity: O(n)
- Typical execution: <1ms for 1000 bids
```

### `create_elastic_schedule`

```@doc
create_elastic_schedule(; kwargs...) -> ElasticSupplySchedule

Creates an elastic supply schedule with specified parameters.

# Keyword Arguments
- `base_quantity::Float64`: Starting quantity (default: 1000.0)
- `price_floor::Float64`: Minimum price (default: 10.0)
- `price_ceiling::Float64`: Maximum price (default: 100.0)
- `num_points::Int`: Number of interpolation points (default: 10)
- `elasticity_type::ElasticityType`: EXPONENTIAL, LINEAR, or LOGARITHMIC
- `elasticity_factor::Float64`: Elasticity strength (default: 1.5)

# Mathematical Models

## Exponential
```math
S(p) = S_0 \cdot e^{\alpha(p - p_f)}
```

## Linear
```math
S(p) = S_0 \cdot (1 + \beta(p - p_f))
```

## Logarithmic
```math
S(p) = S_0 \cdot (1 + \log(1 + \gamma(p - p_f)))
```

# Example
```jldoctest elastic
julia> using AugmentedUniformPriceAuction

julia> schedule = create_elastic_schedule(
           base_quantity = 500.0,
           price_floor = 25.0,
           price_ceiling = 75.0,
           elasticity_type = LOGARITHMIC
       );

julia> length(schedule.points)
10

julia> schedule.points[1].price
25.0

julia> schedule.points[end].price
75.0
```
```

### `analyze_bid_shading`

```@doc
analyze_bid_shading(bids::Vector{Bid}, clearing_price::Float64) -> Float64

Estimates the degree of bid shading in submitted bids.

# Algorithm
Compares marginal bids (marked with `is_marginal=true`) against regular bids
to estimate strategic shading percentage.

# Returns
Estimated shading percentage (0-100)

# Statistical Method
```math
\text{Shading} = \frac{\bar{p}_{regular} - \bar{p}_{marginal}}{\bar{p}_{regular}} \times 100
```

# Example
```jldoctest shading_analysis
julia> using AugmentedUniformPriceAuction

julia> # Create bids with different shading levels
       bids = [
           Bid("b1", 10.0, 50.0, is_marginal=false),  # Regular
           Bid("b2", 10.0, 45.0, is_marginal=true),   # Shaded marginal
           Bid("b3", 10.0, 49.0, is_marginal=false),  # Regular
           Bid("b4", 10.0, 44.0, is_marginal=true)    # Shaded marginal
       ];

julia> shading = analyze_bid_shading(bids, 46.0);

julia> shading > 0  # Detected shading
true

julia> round(shading, digits=1)
10.4
```
```

## Advanced Usage

### Custom Tie-Breaking Implementation

!!! example "Implementing Custom Tie-Breaking"
    ```julia
    struct ProbabilisticTieBreaking <: TieBreakingStrategy
        seed::Int
    end
    
    function resolve_ties(bids::Vector{Bid}, quantity::Float64, 
                         strategy::ProbabilisticTieBreaking)
        Random.seed!(strategy.seed)
        shuffled = shuffle(bids)
        # Allocate randomly among tied bidders
        return allocate_up_to_quantity(shuffled, quantity)
    end
    ```

### Performance Benchmarking

```julia
using BenchmarkTools
using AugmentedUniformPriceAuction

function benchmark_auction_sizes()
    sizes = [100, 1000, 10000, 100000]
    results = Dict()
    
    for n in sizes
        bids = [Bid("b$i", rand()*100, 30+rand()*40) for i in 1:n]
        config = AuctionConfig(
            supply_schedule = create_elastic_schedule(),
            tie_breaking = AugmentedTieBreaking()
        )
        
        results[n] = @benchmark run_auction($bids, $config)
    end
    
    return results
end
```

### Error Handling

!!! warning "Common Errors"
    Input validation errors:
    
    | Error | Cause | Solution |
    |:------|:------|:---------|
    | `ArgumentError("Bid quantity must be positive")` | Negative or zero quantity | Use quantities > 0 |
    | `ArgumentError("Supply schedule must be monotonically increasing")` | Invalid supply points | Check monotonicity |
    | `ArgumentError("Weights must sum to at most 1.0")` | Invalid weights | Sum weights ≤ 1.0 |

## See Also

- [Theory: Bid Shading](../theory/bid_shading.md)
- [Examples: Advanced Features](../examples/advanced.md)
- [GitHub Repository](https://github.com/julia-auction/julia-auction)

---

*Module Index: `AugmentedUniformPriceAuction`*