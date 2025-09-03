# Basic Auction Examples

## Document Information
**Type:** Code Examples
**Level:** Beginner
**Prerequisites:** Julia 1.6+ and package installation

## Executive Summary

This guide demonstrates fundamental auction system usage through practical examples. Code samples progress from simple uniform price auctions to elastic supply configurations. Each example includes complete setup, execution, and result analysis.

## Simple Uniform Price Auction

### Basic Setup
Start with a minimal auction configuration:

```julia
using AuctionSystem

# Configure auction
config = AuctionConfig(
    supply = 1000.0,        # Units available
    reserve_price = 10.0,   # Minimum price
    auction_type = UNIFORM_PRICE
)

# Create bids
bids = [
    Bid("bidder1", 15.0, 200.0),  # $15 for 200 units
    Bid("bidder2", 14.0, 300.0),  # $14 for 300 units
    Bid("bidder3", 13.0, 400.0),  # $13 for 400 units
    Bid("bidder4", 12.0, 500.0),  # $12 for 500 units
]

# Run auction
result = run_auction(bids, config)

# Display results
println("Clearing price: $(result.clearing_price)")
println("Allocated: $(result.total_allocated) units")
```

### Expected Output
```
Clearing price: 12.0
Allocated: 1000.0 units
```

The auction clears at $12 where demand meets supply. Higher bidders receive full allocations at the uniform clearing price.

## Augmented Auction with Elastic Supply

### Configuration
Elastic supply adjusts quantity based on price:

```julia
# Create elastic supply
supply = ElasticSupplySchedule(
    base_quantity = 1000.0,
    price_floor = 10.0,
    price_ceiling = 20.0,
    elasticity = 0.5,
    elasticity_type = LINEAR
)

# Configure augmented auction
config = AuctionConfig(
    supply_schedule = supply,
    tie_breaking = AugmentedTieBreaking(0.7, 0.3),
    reserve_price = 10.0
)

# Generate sample bids
bids = generate_sample_bids(
    num_bidders = 10,
    price_range = (8.0, 25.0),
    quantity_range = (50.0, 300.0)
)

# Run and analyze
result = run_auction(bids, config)
println("Clearing price: $(result.clearing_price)")
println("Final supply: $(result.final_supply)")
println("Revenue: $(result.total_revenue)")
```

Elastic supply increases with price, finding equilibrium where supply meets demand dynamically.

## Working with Bid Objects

### Creating Valid Bids
Bids contain essential trading information:

```julia
# Create detailed bid
bid = Bid(
    bidder_id = "trader_123",
    price = 50.0,
    quantity = 100.0,
    timestamp = now(),
    metadata = Dict(
        "account_type" => "institutional",
        "order_type" => "AON"  # All or None
    )
)

# Validate bid
function validate_bid(bid::Bid, config::AuctionConfig)
    bid.price >= config.reserve_price || 
        return false, "Below reserve"
    bid.quantity > 0 || 
        return false, "Invalid quantity"
    return true, "Valid"
end

valid, message = validate_bid(bid, config)
```

## Batch Auction Processing

### Multiple Simultaneous Auctions
Process different asset auctions concurrently:

```julia
# Define multiple auctions
auctions = [
    ("GOLD", AuctionConfig(supply=100.0, reserve_price=1500.0)),
    ("SILVER", AuctionConfig(supply=1000.0, reserve_price=25.0))
]

# Collect bids
all_bids = Dict(
    "GOLD" => [
        Bid("bank1", 1600.0, 30.0),
        Bid("bank2", 1580.0, 40.0)
    ],
    "SILVER" => [
        Bid("trader1", 27.0, 300.0),
        Bid("trader2", 26.5, 400.0)
    ]
)

# Process all auctions
results = Dict()
for (name, config) in auctions
    results[name] = run_auction(all_bids[name], config)
    println("$name: $(results[name].clearing_price)")
end
```

## Monitoring Auction Metrics

### Real-time Analysis
Track key performance indicators during auctions:

```julia
struct AuctionMetrics
    bid_count::Int
    total_demand::Float64
    average_price::Float64
    price_variance::Float64
end

function calculate_metrics(bids::Vector{Bid})
    prices = [b.price for b in bids]
    quantities = [b.quantity for b in bids]
    
    AuctionMetrics(
        length(bids),
        sum(quantities),
        mean(prices),
        var(prices)
    )
end

metrics = calculate_metrics(bids)
println("Bids: $(metrics.bid_count)")
println("Demand: $(metrics.total_demand)")
println("Avg price: $(round(metrics.average_price, digits=2))")
```

## Error Handling

### Safe Execution Pattern
Handle errors gracefully in production:

```julia
function safe_run_auction(bids, config)
    try
        # Validate inputs
        isempty(bids) && 
            return ErrorResult("No bids")
        config.supply > 0 || 
            return ErrorResult("Invalid supply")
        
        # Execute auction
        result = run_auction(bids, config)
        
        # Check reserve
        result.clearing_price >= config.reserve_price ||
            return ErrorResult("Below reserve")
        
        return result
    catch e
        @error "Auction failed" exception=e
        return ErrorResult(string(e))
    end
end

result = safe_run_auction(bids, config)
isa(result, ErrorResult) ?
    println("Error: $(result.message)") :
    println("Success: $(result.clearing_price)")
```

## Common Patterns

### Reserve Price Enforcement
Filter bids meeting minimum requirements:

```julia
function enforce_reserve(bids, reserve_price)
    valid_bids = filter(b -> b.price >= reserve_price, bids)
    isempty(valid_bids) && 
        throw(AuctionError("No valid bids"))
    return valid_bids
end
```

### Bid Aggregation
Combine multiple bids from same bidder:

```julia
function aggregate_by_bidder(bids)
    aggregated = Dict{String, Bid}()
    
    for bid in bids
        if haskey(aggregated, bid.bidder_id)
            existing = aggregated[bid.bidder_id]
            aggregated[bid.bidder_id] = Bid(
                bid.bidder_id,
                max(existing.price, bid.price),
                existing.quantity + bid.quantity
            )
        else
            aggregated[bid.bidder_id] = bid
        end
    end
    
    return collect(values(aggregated))
end
```

### Progressive Auctions
Release supply in stages:

```julia
function progressive_auction(supply, stages)
    remaining = supply
    results = []
    
    for (i, fraction) in enumerate(stages)
        stage_supply = supply * fraction
        config = AuctionConfig(
            supply = min(stage_supply, remaining),
            reserve_price = 10.0 * (1 + i * 0.1)
        )
        
        result = run_auction(current_bids, config)
        push!(results, result)
        
        remaining -= result.total_allocated
        remaining <= 0 && break
    end
    
    return results
end
```

## Performance Testing

### Benchmarking
Measure auction performance at scale:

```julia
using BenchmarkTools

function benchmark_auction(n::Int)
    bids = [Bid("b$i", 10+5*rand(), 100*rand()) 
            for i in 1:n]
    
    config = AuctionConfig(
        supply = n * 30.0,
        reserve_price = 10.0
    )
    
    @benchmark run_auction($bids, $config)
end

# Test scaling
for n in [100, 1000, 10000]
    println("$n bids:")
    display(benchmark_auction(n))
end
```

## Integration Examples

### REST API Usage
Submit bids programmatically:

```julia
using HTTP, JSON

function submit_bid(bid::Bid, auction_id::String)
    url = "http://api.auction.com/bids"
    
    payload = JSON.json(Dict(
        "auction_id" => auction_id,
        "bidder_id" => bid.bidder_id,
        "price" => bid.price,
        "quantity" => bid.quantity
    ))
    
    response = HTTP.post(url,
        ["Content-Type" => "application/json"],
        payload)
    
    return JSON.parse(String(response.body))
end
```

### WebSocket Updates
Monitor auctions in real-time:

```julia
using WebSockets

WebSockets.open("ws://auction.com/live") do ws
    # Subscribe
    write(ws, JSON.json(Dict(
        "action" => "subscribe",
        "auction" => "GOLD_001"
    )))
    
    # Listen for updates
    while !eof(ws)
        update = JSON.parse(String(read(ws)))
        
        if update["type"] == "bid_received"
            println("New bid: $(update["price"])")
        elseif update["type"] == "cleared"
            println("Cleared: $(update["price"])")
            break
        end
    end
end
```

## Troubleshooting

### Common Issues

**No clearing price found:**
- Verify total demand exceeds supply
- Check reserve price configuration
- Ensure valid bid format

**Unexpected allocations:**
- Review tie-breaking rules
- Check bid timestamps
- Verify auction type

**Performance degradation:**
- Implement bid caching
- Use batch processing
- Enable parallel execution

## Next Steps

- [Advanced Examples](advanced.md): Complex configurations
- [Performance Guide](performance.md): Optimization techniques
- [API Reference](../api/augmented.md): Function documentation
- [Theory Overview](../theory/overview.md): Academic foundations

## Summary

These examples demonstrate core auction functionality from simple uniform price to augmented mechanisms. The patterns shown handle common requirements including validation, aggregation, and error management. Use these building blocks to construct production auction systems.