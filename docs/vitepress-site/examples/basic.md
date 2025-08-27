# Basic Auction Examples

## Getting Started

This guide provides basic examples of using the Julia Auction System.

## Simple Uniform Price Auction

### Basic Setup

```julia
using AuctionSystem

# Create a simple auction configuration
config = AuctionConfig(
    supply = 1000.0,  # 1000 units available
    reserve_price = 10.0,  # Minimum price of $10
    auction_type = UNIFORM_PRICE
)

# Create some bids
bids = [
    Bid("bidder1", 15.0, 200.0),  # Bidder 1: $15 for 200 units
    Bid("bidder2", 14.0, 300.0),  # Bidder 2: $14 for 300 units  
    Bid("bidder3", 13.0, 400.0),  # Bidder 3: $13 for 400 units
    Bid("bidder4", 12.0, 500.0),  # Bidder 4: $12 for 500 units
    Bid("bidder5", 11.0, 100.0),  # Bidder 5: $11 for 100 units
]

# Run the auction
result = run_auction(bids, config)

# Display results
println("Clearing price: \$\$(result.clearing_price)")
println("Total allocated: \$(result.total_allocated) units")
println("\nAllocations:")
for alloc in result.allocations
    println("  \$(alloc.bidder_id): \$(alloc.quantity) units at \$\$(result.clearing_price)")
end
```

### Expected Output

```
Clearing price: $12.0
Total allocated: 1000.0 units

Allocations:
  bidder1: 200.0 units at $12.0
  bidder2: 300.0 units at $12.0
  bidder3: 400.0 units at $12.0
  bidder4: 100.0 units at $12.0
```

## Augmented Auction with Elastic Supply

### Configuration

```julia
using AuctionSystem

# Create elastic supply schedule
supply_schedule = ElasticSupplySchedule(
    base_quantity = 1000.0,
    price_floor = 10.0,
    price_ceiling = 20.0,
    elasticity = 0.5,
    elasticity_type = LINEAR
)

# Configure augmented auction
config = AuctionConfig(
    supply_schedule = supply_schedule,
    tie_breaking = AugmentedTieBreaking(0.7, 0.3),
    reserve_price = 10.0
)

# Generate more realistic bids
bids = generate_sample_bids(
    num_bidders = 10,
    price_range = (8.0, 25.0),
    quantity_range = (50.0, 300.0)
)

# Run augmented auction
result = run_auction(bids, config)

# Analyze results
println("Results with Elastic Supply:")
println("  Clearing price: \$\$(result.clearing_price)")
println("  Supply at clearing: \$(result.final_supply)")
println("  Revenue: \$\$(result.total_revenue)")
```

## Batch Auction Processing

### Multiple Simultaneous Auctions

```julia
# Define multiple auction configurations
auctions = [
    ("GOLD_AUCTION", 
     AuctionConfig(supply = 100.0, reserve_price = 1500.0)),
    ("SILVER_AUCTION", 
     AuctionConfig(supply = 1000.0, reserve_price = 25.0)),
    ("COPPER_AUCTION", 
     AuctionConfig(supply = 5000.0, reserve_price = 3.0))
]

# Collect bids for each auction
all_bids = Dict(
    "GOLD_AUCTION" => [
        Bid("bank1", 1600.0, 30.0),
        Bid("bank2", 1580.0, 40.0),
        Bid("bank3", 1550.0, 50.0)
    ],
    "SILVER_AUCTION" => [
        Bid("trader1", 27.0, 300.0),
        Bid("trader2", 26.5, 400.0),
        Bid("trader3", 26.0, 500.0)
    ],
    "COPPER_AUCTION" => [
        Bid("industrial1", 3.5, 2000.0),
        Bid("industrial2", 3.4, 2500.0),
        Bid("industrial3", 3.3, 1500.0)
    ]
)

# Process all auctions
results = Dict{String, AuctionResult}()
for (name, config) in auctions
    bids = all_bids[name]
    results[name] = run_auction(bids, config)
    println("\$name cleared at \$\$(results[name].clearing_price)")
end
```

## Working with Bid Objects

### Creating and Validating Bids

```julia
# Create a bid with full parameters
bid = Bid(
    bidder_id = "trader_123",
    price = 50.0,
    quantity = 100.0,
    timestamp = now(),
    metadata = Dict(
        "account_type" => "institutional",
        "order_type" => "AON",  # All or None
        "max_fees" => 2.50
    )
)

# Validate bid
function validate_bid(bid::Bid, config::AuctionConfig)
    errors = String[]
    
    if bid.price < config.reserve_price
        push!(errors, "Bid below reserve price")
    end
    
    if bid.quantity <= 0
        push!(errors, "Invalid quantity")
    end
    
    if bid.price <= 0
        push!(errors, "Invalid price")
    end
    
    return length(errors) == 0, errors
end

is_valid, errors = validate_bid(bid, config)
if !is_valid
    println("Bid validation failed: ", join(errors, ", "))
end
```

## Monitoring Auction Metrics

### Real-time Metrics Collection

```julia
# Track auction metrics
struct AuctionMetrics
    bid_count::Int
    total_demand::Float64
    average_price::Float64
    price_variance::Float64
    participation_rate::Float64
end

function calculate_metrics(bids::Vector{Bid})
    prices = [b.price for b in bids]
    quantities = [b.quantity for b in bids]
    
    return AuctionMetrics(
        bid_count = length(bids),
        total_demand = sum(quantities),
        average_price = mean(prices),
        price_variance = var(prices),
        participation_rate = length(unique(b.bidder_id for b in bids)) / 100
    )
end

# Monitor auction in real-time
metrics = calculate_metrics(bids)
println("Current auction metrics:")
println("  Bids received: \$(metrics.bid_count)")
println("  Total demand: \$(metrics.total_demand)")
println("  Avg bid price: \$\$(round(metrics.average_price, digits=2))")
```

## Error Handling

### Graceful Error Management

```julia
# Wrap auction execution with error handling
function safe_run_auction(bids, config)
    try
        # Validate inputs
        if isempty(bids)
            return ErrorResult("No bids received")
        end
        
        if config.supply <= 0
            return ErrorResult("Invalid supply configuration")
        end
        
        # Run auction
        result = run_auction(bids, config)
        
        # Validate result
        if result.clearing_price < config.reserve_price
            return ErrorResult("Auction failed to meet reserve")
        end
        
        return result
        
    catch e
        # Log error
        @error "Auction failed" exception=e
        return ErrorResult(string(e))
    end
end

# Use safe wrapper
result = safe_run_auction(bids, config)
if isa(result, ErrorResult)
    println("Auction error: \$(result.message)")
else
    println("Auction successful at \$\$(result.clearing_price)")
end
```

## Integration Examples

### REST API Integration

```julia
using HTTP
using JSON

# Submit bid via API
function submit_bid_api(bid::Bid, auction_id::String)
    url = "http://localhost:8080/api/auctions/\$(auction_id)/bids"
    
    payload = JSON.json(Dict(
        "bidder_id" => bid.bidder_id,
        "price" => bid.price,
        "quantity" => bid.quantity
    ))
    
    response = HTTP.post(
        url,
        ["Content-Type" => "application/json"],
        payload
    )
    
    return JSON.parse(String(response.body))
end

# Get auction results
function get_auction_results(auction_id::String)
    url = "http://localhost:8080/api/auctions/\$(auction_id)/results"
    response = HTTP.get(url)
    return JSON.parse(String(response.body))
end
```

### WebSocket Real-time Updates

```julia
using WebSockets

# Connect to auction updates
WebSockets.open("ws://localhost:8080/ws/auctions") do ws
    # Subscribe to auction
    write(ws, JSON.json(Dict("action" => "subscribe", "auction_id" => "GOLD_001")))
    
    # Listen for updates
    while !eof(ws)
        data = String(read(ws))
        update = JSON.parse(data)
        
        if update["type"] == "bid_received"
            println("New bid: \$(update["price"]) for \$(update["quantity"])")
        elseif update["type"] == "auction_cleared"
            println("Auction cleared at \$(update["clearing_price"])")
            break
        end
    end
end
```

## Performance Testing

### Simple Benchmark

```julia
using BenchmarkTools

# Benchmark auction performance
function benchmark_auction(num_bids::Int)
    # Generate random bids
    bids = [Bid("bidder_\$i", 
                10.0 + 5.0 * rand(), 
                100.0 * rand()) 
            for i in 1:num_bids]
    
    config = AuctionConfig(
        supply = num_bids * 30.0,
        reserve_price = 10.0
    )
    
    # Measure execution time
    @benchmark run_auction(\$bids, \$config)
end

# Test with different sizes
for n in [100, 1000, 10000]
    println("Performance with \$n bids:")
    display(benchmark_auction(n))
    println()
end
```

## Next Steps

After mastering these basic examples:

1. **Advanced Features** - See [Advanced Examples](advanced.md)
2. **Performance Tuning** - See [Performance Guide](performance.md)
3. **API Integration** - See [API Reference](../api/augmented.md)
4. **Theory Deep Dive** - See [Auction Theory](../theory/overview.md)

## Common Patterns

### Pattern 1: Reserve Price Enforcement

```julia
function enforce_reserve(bids, reserve_price)
    valid_bids = filter(b -> b.price >= reserve_price, bids)
    if isempty(valid_bids)
        throw(AuctionError("No bids meet reserve price"))
    end
    return valid_bids
end
```

### Pattern 2: Bid Aggregation

```julia
function aggregate_bids_by_bidder(bids)
    aggregated = Dict{String, Bid}()
    for bid in bids
        if haskey(aggregated, bid.bidder_id)
            # Combine bids from same bidder
            existing = aggregated[bid.bidder_id]
            aggregated[bid.bidder_id] = Bid(
                bid.bidder_id,
                max(existing.price, bid.price),  # Use highest price
                existing.quantity + bid.quantity  # Sum quantities
            )
        else
            aggregated[bid.bidder_id] = bid
        end
    end
    return values(aggregated)
end
```

### Pattern 3: Progressive Auction

```julia
function progressive_auction(total_supply, batches)
    remaining = total_supply
    results = []
    
    for (i, batch_percent) in enumerate(batches)
        batch_supply = total_supply * batch_percent
        config = AuctionConfig(
            supply = min(batch_supply, remaining),
            reserve_price = 10.0 * (1 + i * 0.1)  # Increasing reserve
        )
        
        result = run_auction(current_bids, config)
        push!(results, result)
        
        remaining -= result.total_allocated
        if remaining <= 0
            break
        end
    end
    
    return results
end
```

## Troubleshooting

Common issues and solutions:

1. **No clearing price found**
   - Check if total demand exceeds supply
   - Verify reserve price isn't too high

2. **Unexpected allocations**
   - Review tie-breaking rules
   - Check bid timestamps

3. **Performance issues**
   - Consider batch processing
   - Implement bid caching
   - Use parallel processing for large auctions

For more help, see [Troubleshooting Guide](../troubleshooting.md)