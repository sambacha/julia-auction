# Quick Start Guide

## Running Your First Auction

This guide will help you run your first auction in under 5 minutes.

### Step 1: Install the Package

```julia
using Pkg
Pkg.add("AuctionSystem")
```

### Step 2: Create Basic Bids

```julia
using AuctionSystem

# Create sample bids
bids = [
    Bid(price=100.0, quantity=10.0, bidder_id="alice"),
    Bid(price=95.0, quantity=15.0, bidder_id="bob"),
    Bid(price=90.0, quantity=20.0, bidder_id="charlie"),
    Bid(price=85.0, quantity=25.0, bidder_id="david")
]
```

### Step 3: Configure the Auction

```julia
# Configure elastic supply
supply_config = ElasticSupplyConfig(
    base_quantity = 50.0,
    elasticity = 0.5,
    price_floor = 80.0,
    price_ceiling = 110.0
)

# Configure auction parameters
auction_config = AuctionConfig(
    supply_schedule = supply_config,
    mechanism = AugmentedUniformPrice(),
    tie_breaking = ProportionalTieBreaking()
)
```

### Step 4: Run the Auction

```julia
# Execute the auction
result = run_auction(bids, auction_config)

# Display results
println("Clearing Price: \$$(result.clearing_price)")
println("Total Quantity: $(result.total_quantity)")
println("Winners:")
for winner in result.winners
    println("  - $(winner.bidder_id): $(winner.allocated_quantity) units")
end
```

## Example Output

```
Clearing Price: $92.50
Total Quantity: 47.5
Winners:
  - alice: 10.0 units
  - bob: 15.0 units
  - charlie: 20.0 units
  - david: 2.5 units
```

## Advanced Usage

### With CFMM Settlement

```julia
# Enable CFMM integration
cfmm_config = CFMMConfig(
    enabled = true,
    pools = ["UniswapV3", "SushiSwap"],
    max_slippage = 0.01,
    mev_protection = true
)

auction_config = AuctionConfig(
    supply_schedule = supply_config,
    mechanism = AugmentedUniformPrice(),
    settlement = cfmm_config
)

result = run_auction(bids, auction_config)

# Check settlement details
println("Settlement Route: $(result.settlement.route)")
println("Gas Cost: $(result.settlement.gas_cost)")
println("MEV Captured: \$$(result.settlement.mev_captured)")
```

### With MEV Protection

```julia
# Configure MEV protection
mev_config = MEVProtectionConfig(
    commit_reveal = true,
    private_mempool = true,
    time_delay_ms = 100,
    sandwich_protection = true
)

auction_config = AuctionConfig(
    supply_schedule = supply_config,
    mechanism = AugmentedUniformPrice(),
    mev_protection = mev_config
)

# Submit bids with protection
protected_result = run_protected_auction(bids, auction_config)
```

## Testing Your Setup

Run the test suite to verify everything is working:

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
```

## Common Patterns

### Batch Processing

```julia
# Process multiple auctions in parallel
auctions = [auction1, auction2, auction3]
results = run_batch_auctions(auctions, auction_config)
```

### Real-time Monitoring

```julia
# Enable metrics collection
monitor = AuctionMonitor(
    port = 8080,
    metrics = [:price, :volume, :mev, :latency]
)

# Run auction with monitoring
result = run_auction(bids, auction_config, monitor=monitor)

# Access metrics at http://localhost:8080/metrics
```

## Next Steps

- [Core Concepts](/concepts) - Understand the theory
- [API Reference](/api/augmented) - Full API documentation  
- [Examples](/examples/basic) - More code examples
- [Production Status](/guides/production_status) - Production readiness