# Quick Start Tutorial

## Overview

Start using the Julia Auction System in minutes. This tutorial shows you how to create your first auction, submit bids, and understand the results.

## Prerequisites

Complete the [Installation Guide](../installation.md) first and start the system.

## Step 1: Start the System

### Development Mode
```bash
cd julia-auction
julia --project=. src/main.jl
```

### Using Docker
```bash
docker run -p 8080:8080 julia-auction:latest
```

## Step 2: Create Your First Auction

### Using the Julia REPL

```julia
using AugmentedUniformPriceAuction
using HTTP
using JSON

# Create an auction configuration
auction_params = Dict(
    "type" => "uniform_price",
    "reserve_price" => 10.0,
    "supply_schedule" => Dict(
        "base_quantity" => 1000.0,
        "price_floor" => 10.0,
        "price_ceiling" => 100.0,
        "elasticity_type" => "exponential"
    ),
    "duration_ms" => 60000
)

# Submit via API
response = HTTP.post(
    "http://localhost:8080/v1/auctions",
    ["Content-Type" => "application/json"],
    JSON.json(auction_params)
)

auction = JSON.parse(String(response.body))
println("Created auction: $(auction["auction_id"])")
```

### Using cURL

```bash
curl -X POST http://localhost:8080/v1/auctions \
  -H "Content-Type: application/json" \
  -d '{
    "type": "uniform_price",
    "reserve_price": 10.0,
    "supply_schedule": {
      "base_quantity": 1000.0,
      "price_floor": 10.0,
      "price_ceiling": 100.0,
      "elasticity_type": "exponential"
    },
    "duration_ms": 60000
  }'
```

## Step 3: Submit Bids

### Submit a Single Bid

```julia
# Submit a bid
bid_params = Dict(
    "quantity" => 100.0,
    "price" => 50.0
)

response = HTTP.post(
    "http://localhost:8080/v1/auctions/$(auction["auction_id"])/bids",
    ["Content-Type" => "application/json"],
    JSON.json(bid_params)
)

bid = JSON.parse(String(response.body))
println("Submitted bid: $(bid["bid_id"])")
```

### Submit Multiple Bids

```julia
# Submit multiple bids
bids = [
    Dict("quantity" => 100.0, "price" => 55.0),
    Dict("quantity" => 150.0, "price" => 52.0),
    Dict("quantity" => 120.0, "price" => 50.0),
    Dict("quantity" => 80.0, "price" => 48.0)
]

for bid in bids
    HTTP.post(
        "http://localhost:8080/v1/auctions/$(auction["auction_id"])/bids",
        ["Content-Type" => "application/json"],
        JSON.json(bid)
    )
end
```

## Step 4: Monitor Auction Progress

### Get Auction Status

```julia
response = HTTP.get("http://localhost:8080/v1/auctions/$(auction["auction_id"])")
status = JSON.parse(String(response.body))

println("Auction Status: $(status["status"])")
println("Current Price: $(status["current_price"])")
println("Total Bids: $(status["total_bids"])")
```

### Real-time Updates via WebSocket

```julia
using HTTP.WebSockets

WebSockets.open("ws://localhost:8080/v1/ws") do ws
    # Subscribe to auction updates
    write(ws, JSON.json(Dict(
        "type" => "subscribe",
        "channel" => "auction",
        "auction_id" => auction["auction_id"]
    )))
    
    # Listen for updates
    for msg in ws
        update = JSON.parse(String(msg))
        println("Update: $(update)")
    end
end
```

## Step 5: View Results

### View Settlement Results

```julia
# Wait for auction to complete
sleep(60)

# Get settlement details
response = HTTP.get("http://localhost:8080/v1/settlements/$(auction["auction_id"])")
settlement = JSON.parse(String(response.body))

println("Clearing Price: $(settlement["clearing_price"])")
println("Total Allocated: $(settlement["total_allocated"])")
println("Total Revenue: $(settlement["total_revenue"])")
println("Price Improvement: $(settlement["phantom_improvement_bps"]) bps")
```

### View Individual Bid Results

```julia
response = HTTP.get("http://localhost:8080/v1/bids/$(bid["bid_id"])")
bid_result = JSON.parse(String(response.body))

if bid_result["status"] == "allocated"
    println("Bid won! Allocated: $(bid_result["allocated_quantity"]) at $(bid_result["clearing_price"])")
else
    println("Bid not allocated")
end
```

## Complete Example Script

```julia
# quickstart.jl
using HTTP
using JSON
using Dates

function run_auction_example()
    base_url = "http://localhost:8080/v1"
    
    # Step 1: Create auction
    println("Creating auction...")
    auction_params = Dict(
        "type" => "uniform_price",
        "reserve_price" => 10.0,
        "supply_schedule" => Dict(
            "base_quantity" => 1000.0,
            "price_floor" => 10.0,
            "price_ceiling" => 100.0,
            "elasticity_type" => "exponential"
        ),
        "duration_ms" => 30000  # 30 seconds
    )
    
    response = HTTP.post(
        "$base_url/auctions",
        ["Content-Type" => "application/json"],
        JSON.json(auction_params)
    )
    auction = JSON.parse(String(response.body))
    auction_id = auction["auction_id"]
    println("✓ Created auction: $auction_id")
    
    # Step 2: Submit bids
    println("\nSubmitting bids...")
    bids = [
        Dict("quantity" => 100.0, "price" => 55.0),
        Dict("quantity" => 150.0, "price" => 52.0),
        Dict("quantity" => 120.0, "price" => 50.0),
        Dict("quantity" => 80.0, "price" => 48.0),
        Dict("quantity" => 90.0, "price" => 46.0)
    ]
    
    bid_ids = []
    for (i, bid) in enumerate(bids)
        response = HTTP.post(
            "$base_url/auctions/$auction_id/bids",
            ["Content-Type" => "application/json"],
            JSON.json(bid)
        )
        result = JSON.parse(String(response.body))
        push!(bid_ids, result["bid_id"])
        println("  ✓ Bid $i: $(bid["quantity"]) units at \$$(bid["price"])")
    end
    
    # Step 3: Monitor auction
    println("\nMonitoring auction...")
    for i in 1:3
        response = HTTP.get("$base_url/auctions/$auction_id")
        status = JSON.parse(String(response.body))
        println("  Status: $(status["status"]), Bids: $(status["total_bids"])")
        sleep(10)
    end
    
    # Step 4: Get results
    println("\nAuction completed! Getting results...")
    response = HTTP.get("$base_url/settlements/$auction_id")
    settlement = JSON.parse(String(response.body))
    
    println("\n" * "="^50)
    println("AUCTION RESULTS")
    println("="^50)
    println("Clearing Price: \$$(settlement["clearing_price"])")
    println("Total Allocated: $(settlement["total_allocated"]) units")
    println("Total Revenue: \$$(settlement["total_revenue"])")
    println("Price Improvement: $(settlement["phantom_improvement_bps"]) bps")
    
    # Check individual bids
    println("\nIndividual Bid Results:")
    for (i, bid_id) in enumerate(bid_ids)
        response = HTTP.get("$base_url/bids/$bid_id")
        result = JSON.parse(String(response.body))
        if result["status"] == "allocated"
            println("  Bid $i: WON - $(result["allocated_quantity"]) units")
        else
            println("  Bid $i: NOT ALLOCATED")
        end
    end
end

# Run the example
run_auction_example()
```

## Understanding the Results

### Key Metrics

1. **Clearing Price**: The uniform price at which all winning bids are settled
2. **Total Allocated**: Sum of quantities allocated to winning bidders
3. **Price Improvement**: Basis points improvement from phantom auction mechanism
4. **Efficiency Score**: How close the auction came to theoretical optimum

### Allocation Rules

In a uniform price auction:
- All bids above the clearing price win
- All winners pay the same clearing price (not their bid price)  
- The augmented tie-breaking mechanism resolves ties at the clearing price

## Advanced Features

### Create Custom Supply Schedules

```julia
# Linear supply schedule
linear_supply = Dict(
    "base_quantity" => 500.0,
    "price_floor" => 20.0,
    "price_ceiling" => 80.0,
    "elasticity_type" => "linear",
    "elasticity_factor" => 2.0
)

# Logarithmic supply schedule
log_supply = Dict(
    "base_quantity" => 1000.0,
    "price_floor" => 15.0,
    "price_ceiling" => 90.0,
    "elasticity_type" => "logarithmic",
    "elasticity_factor" => 1.5
)
```

### Try Different Auction Types

```julia
# Vickrey (second-price) auction
vickrey_auction = Dict(
    "type" => "vickrey",
    "reserve_price" => 20.0
)

# Dutch auction
dutch_auction = Dict(
    "type" => "dutch",
    "starting_price" => 100.0,
    "ending_price" => 10.0,
    "duration_ms" => 120000
)

# English auction
english_auction = Dict(
    "type" => "english",
    "starting_price" => 10.0,
    "increment" => 5.0,
    "duration_ms" => 180000
)
```

## Troubleshooting

### Common Issues

1. **Connection Refused**
   - Confirm the server is running
   - Check the port (default 8080)
   - Verify firewall settings

2. **Bid Rejected**
   - Confirm bid price exceeds reserve
   - Confirm auction is still active
   - Confirm bid quantity is positive

3. **No Allocation**
   - Your bid price may fall below clearing price
   - Check auction status and results

## Next Steps

- [API Reference](../api_reference.md) - Complete API documentation
- [Configuration Guide](../configuration.md) - Customize system behavior
- [Examples](../examples/basic.md) - More code examples
- [Theory Overview](../theory/overview.md) - Understand the mechanisms