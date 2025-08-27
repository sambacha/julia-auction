# Code Examples

## Basic Examples

### Simple Uniform Price Auction

```julia
using AugmentedUniformPriceAuction

// Create a basic auction configuration
config = AuctionConfig(
    reserve_price = 20.0,
    supply_quantity = 1000.0
)

# Submit bids
bids = [
    Bid("alice", 100.0, 30.0),
    Bid("bob", 200.0, 25.0),
    Bid("charlie", 150.0, 22.0),
    Bid("diana", 250.0, 21.0)
]

# Run auction
result = run_auction(bids, config)

println("Clearing price: $(result.clearing_price)")
println("Total allocated: $(result.total_allocated)")
println("Winners:")
for allocation in result.allocations
    println("  $(allocation.bidder): $(allocation.quantity) units")
end
```

### Dutch Auction

```julia
using DutchAuction

# Configure descending price auction
auction = DutchAuction(
    starting_price = 100.0,
    reserve_price = 20.0,
    quantity = 500.0,
    price_decrement = 5.0,
    time_interval_ms = 1000
)

# Start auction
start_auction(auction)

# Submit bid when price is acceptable
current_price = get_current_price(auction)
if current_price <= 45.0
    bid = submit_bid(auction, quantity = 100.0)
    println("Bid accepted at price: $(bid.execution_price)")
end
```

### Vickrey (Second-Price) Auction

```julia
using VickreyAuction

# Single item Vickrey auction
auction = VickreyAuction(
    reserve_price = 50.0,
    sealed_bid_period_ms = 60000
)

# Submit sealed bids
submit_sealed_bid(auction, "alice", 100.0)
submit_sealed_bid(auction, "bob", 85.0)
submit_sealed_bid(auction, "charlie", 90.0)

# Reveal winner (pays second highest price)
result = reveal_winner(auction)
println("Winner: $(result.winner)")
println("Winning bid: $(result.winning_bid)")
println("Payment price: $(result.payment_price)")  # Second highest bid
```

## Advanced Examples

### Elastic Supply with Augmented Tie-Breaking

```julia
using AugmentedUniformPriceAuction

# Create elastic supply schedule
supply = create_elastic_schedule(
    base_quantity = 1000.0,
    price_floor = 10.0,
    price_ceiling = 100.0,
    elasticity_type = EXPONENTIAL,
    elasticity_factor = 1.5
)

# Configure augmented tie-breaking
tie_breaking = AugmentedTieBreaking(
    pro_rata_weight = 0.7,
    time_priority_weight = 0.3
)

# Create auction with advanced features
config = AuctionConfig(
    supply_schedule = supply,
    tie_breaking = tie_breaking,
    reserve_price = 15.0,
    allow_marginal_bids = true
)

# Submit bids with timestamps
bids = [
    TimestampedBid("alice", 100.0, 50.0, timestamp = now() - Second(30)),
    TimestampedBid("bob", 100.0, 50.0, timestamp = now() - Second(20)),
    TimestampedBid("charlie", 100.0, 50.0, timestamp = now() - Second(10)),
    MarginalBid("diana", 200.0, 48.0, min_quantity = 100.0)
]

# Run auction
result = run_augmented_auction(bids, config)

# Analyze tie-breaking
for allocation in result.tied_allocations
    println("$(allocation.bidder): $(allocation.quantity) units")
    println("  Pro-rata share: $(allocation.pro_rata_share)")
    println("  Time priority: $(allocation.time_priority_score)")
end
```

### Phantom Auction with VCG Mechanism

```julia
using PhantomAuction

# Configure phantom auction
phantom_config = PhantomAuctionConfig(
    mechanism = :vickrey,
    bid_generator = create_bid_generator(
        distribution = :log_normal,
        mean_price = 45.0,
        std_dev = 10.0,
        bid_probability = 0.4
    ),
    max_phantom_bidders = 20,
    reserve_price = 30.0
)

# Real bids
real_bids = [
    Bid("alice", 100.0, 52.0),
    Bid("bob", 150.0, 48.0),
    Bid("charlie", 200.0, 45.0)
]

# Run phantom auction
result = run_phantom_auction(real_bids, phantom_config)

println("Original clearing price: $(result.original_price)")
println("Discovered price: $(result.discovered_price)")
println("Price improvement: $(result.improvement_bps) bps")

# Show VCG payments
for payment in result.vcg_payments
    println("$(payment.bidder) pays: $(payment.amount)")
end
```

### Multi-Party Settlement with Two-Phase Commit

```julia
using Settlement
using Coordinator

# Initialize coordinator
coordinator = Coordinator(
    consensus_threshold = 0.8,
    participants = [
        Participant("node1", "192.168.1.10:8080"),
        Participant("node2", "192.168.1.11:8080"),
        Participant("node3", "192.168.1.12:8080")
    ]
)

# Create settlement
settlement = Settlement(
    auction_id = "550e8400-e29b-41d4-a716-446655440000",
    clearing_price = 48.5,
    allocations = [
        Allocation("alice", 100.0, 48.5),
        Allocation("bob", 150.0, 48.5),
        Allocation("charlie", 120.0, 48.5)
    ],
    total_value = 17945.0
)

# Execute two-phase commit
function execute_settlement(coordinator, settlement)
    # Phase 1: Prepare
    prepare_votes = collect_votes(coordinator, :prepare, settlement)
    
    if !has_consensus(prepare_votes, coordinator.consensus_threshold)
        rollback(coordinator, settlement)
        return SettlementResult(:failed, "No consensus in prepare phase")
    end
    
    # Phase 2: Commit
    commit_votes = collect_votes(coordinator, :commit, settlement)
    
    if !has_consensus(commit_votes, coordinator.consensus_threshold)
        rollback(coordinator, settlement)
        return SettlementResult(:failed, "No consensus in commit phase")
    end
    
    # Finalize
    finalize_settlement(coordinator, settlement)
    return SettlementResult(:success, "Settlement completed")
end

result = execute_settlement(coordinator, settlement)
println("Settlement status: $(result.status)")
```

### CFMM Integration with Routing

```julia
using CFMMIntegration

# Initialize CFMM router
router = CFMMRouter(
    pools = [
        UniswapV3Pool("USDC", "ETH", fee_tier = 3000),
        UniswapV3Pool("ETH", "DAI", fee_tier = 3000),
        CurvePool(["USDC", "DAI", "USDT"], A = 100),
        BalancerPool(["ETH", "WBTC"], weights = [0.8, 0.2])
    ]
)

# Settlement requiring CFMM execution
settlement = CFMMSettlement(
    input_token = "USDC",
    output_token = "DAI",
    input_amount = 10000.0,
    min_output = 9900.0,
    deadline = now() + Minute(5)
)

# Find optimal route
route = find_optimal_route(router, settlement)

println("Optimal path: $(route.path)")
println("Expected output: $(route.expected_output)")
println("Price impact: $(route.price_impact)")
println("Gas estimate: $(route.gas_estimate)")

# Execute trade
execution = execute_route(router, route)

if execution.success
    println("Trade executed!")
    println("Actual output: $(execution.output_amount)")
    println("Slippage: $(execution.slippage)")
else
    println("Trade failed: $(execution.error)")
end
```

## Real-World Integration Examples

### REST API Integration

```julia
using HTTP
using JSON

function create_auction_api(config::Dict)
    response = HTTP.post(
        "https://api.auction.example.com/v1/auctions",
        ["Content-Type" => "application/json",
         "Authorization" => "Bearer $(ENV["API_KEY"])"],
        JSON.json(config)
    )
    
    return JSON.parse(String(response.body))
end

function submit_bid_api(auction_id::String, quantity::Float64, price::Float64)
    bid_data = Dict(
        "quantity" => quantity,
        "price" => price,
        "metadata" => Dict("source" => "julia-client")
    )
    
    response = HTTP.post(
        "https://api.auction.example.com/v1/auctions/$auction_id/bids",
        ["Content-Type" => "application/json",
         "Authorization" => "Bearer $(ENV["API_KEY"])"],
        JSON.json(bid_data)
    )
    
    return JSON.parse(String(response.body))
end

# Example usage
auction = create_auction_api(Dict(
    "type" => "uniform_price",
    "reserve_price" => 20.0,
    "duration_ms" => 60000
))

bid = submit_bid_api(auction["auction_id"], 100.0, 45.0)
println("Bid submitted: $(bid["bid_id"])")
```

### WebSocket Real-time Streaming

```julia
using HTTP.WebSockets
using JSON

function stream_auction(auction_id::String)
    WebSockets.open("wss://api.auction.example.com/v1/ws") do ws
        # Authenticate
        auth_msg = JSON.json(Dict(
            "type" => "auth",
            "token" => "Bearer $(ENV["API_KEY"])"
        ))
        send(ws, auth_msg)
        
        # Subscribe to auction
        subscribe_msg = JSON.json(Dict(
            "type" => "subscribe",
            "channel" => "auction",
            "auction_id" => auction_id
        ))
        send(ws, subscribe_msg)
        
        # Handle messages
        for msg in ws
            data = JSON.parse(String(msg))
            
            if data["type"] == "auction_update"
                payload = data["payload"]
                println("Price: $(payload["current_price"])")
                println("Bids: $(payload["total_bids"])")
                println("Time left: $(payload["time_remaining_ms"])ms")
            elseif data["type"] == "auction_complete"
                payload = data["payload"]
                println("Auction complete!")
                println("Clearing price: $(payload["clearing_price"])")
                println("Total allocated: $(payload["total_allocated"])")
                break
            end
        end
    end
end

# Stream real-time updates
stream_auction("550e8400-e29b-41d4-a716-446655440000")
```

### Database Event Storage

```julia
using LibPQ
using JSON
using UUIDs

# Connect to PostgreSQL
conn = LibPQ.Connection("host=localhost dbname=julia_auction user=auction")

# Store auction events
function store_auction_event(conn, event_type::String, auction_id::String, data::Dict)
    event_id = string(uuid4())
    timestamp = now()
    
    query = """
        INSERT INTO events (event_id, event_type, auction_id, timestamp, data)
        VALUES (\$1, \$2, \$3, \$4, \$5)
    """
    
    execute(conn, query, [
        event_id,
        event_type,
        auction_id,
        timestamp,
        JSON.json(data)
    ])
end

# Query auction history
function get_auction_history(conn, auction_id::String)
    query = """
        SELECT event_type, timestamp, data
        FROM events
        WHERE auction_id = \$1
        ORDER BY timestamp ASC
    """
    
    result = execute(conn, query, [auction_id])
    
    events = []
    for row in result
        push!(events, Dict(
            "event_type" => row[1],
            "timestamp" => row[2],
            "data" => JSON.parse(row[3])
        ))
    end
    
    return events
end

# Example usage
store_auction_event(conn, "auction_created", "auction-123", Dict(
    "reserve_price" => 20.0,
    "supply" => 1000.0
))

store_auction_event(conn, "bid_submitted", "auction-123", Dict(
    "bidder" => "alice",
    "quantity" => 100.0,
    "price" => 45.0
))

history = get_auction_history(conn, "auction-123")
for event in history
    println("$(event["timestamp"]): $(event["event_type"])")
end
```

### Performance Monitoring

```julia
using Dates
using Statistics

mutable struct PerformanceMonitor
    latencies::Vector{Float64}
    start_times::Dict{String, DateTime}
end

monitor = PerformanceMonitor(Float64[], Dict{String, DateTime}())

function start_operation(monitor::PerformanceMonitor, operation_id::String)
    monitor.start_times[operation_id] = now()
end

function end_operation(monitor::PerformanceMonitor, operation_id::String)
    if haskey(monitor.start_times, operation_id)
        start_time = monitor.start_times[operation_id]
        latency = (now() - start_time).value / 1000.0  # Convert to ms
        push!(monitor.latencies, latency)
        delete!(monitor.start_times, operation_id)
        return latency
    end
    return nothing
end

function get_metrics(monitor::PerformanceMonitor)
    if isempty(monitor.latencies)
        return Dict("error" => "No data")
    end
    
    sorted = sort(monitor.latencies)
    n = length(sorted)
    
    return Dict(
        "count" => n,
        "mean" => mean(sorted),
        "median" => median(sorted),
        "p95" => sorted[ceil(Int, 0.95 * n)],
        "p99" => sorted[ceil(Int, 0.99 * n)],
        "max" => maximum(sorted),
        "min" => minimum(sorted)
    )
end

# Example usage
for i in 1:100
    op_id = "auction_$i"
    
    start_operation(monitor, op_id)
    
    # Simulate auction execution
    result = run_auction(generate_random_bids(), config)
    
    latency = end_operation(monitor, op_id)
    println("Auction $i completed in $(latency)ms")
end

metrics = get_metrics(monitor)
println("Performance metrics:")
println("  Mean latency: $(metrics["mean"])ms")
println("  p99 latency: $(metrics["p99"])ms")
```

## Testing Examples

### Unit Testing

```julia
using Test

@testset "Auction Tests" begin
    @testset "Basic Auction" begin
        config = AuctionConfig(reserve_price = 20.0, supply_quantity = 100.0)
        bids = [
            Bid("alice", 50.0, 30.0),
            Bid("bob", 60.0, 25.0)
        ]
        
        result = run_auction(bids, config)
        
        @test result.clearing_price == 25.0
        @test result.total_allocated == 100.0
        @test length(result.allocations) == 2
    end
    
    @testset "Elastic Supply" begin
        supply = create_elastic_schedule(
            base_quantity = 1000.0,
            price_floor = 10.0,
            price_ceiling = 100.0
        )
        
        @test get_quantity_at_price(supply, 10.0) == 1000.0
        @test get_quantity_at_price(supply, 100.0) > 1000.0
        @test get_quantity_at_price(supply, 55.0) > get_quantity_at_price(supply, 50.0)
    end
end
```

### Property-Based Testing

```julia
using Test
using Random

function property_test_auction(n_tests::Int = 100)
    for _ in 1:n_tests
        # Generate random configuration
        config = AuctionConfig(
            reserve_price = rand(10.0:50.0),
            supply_quantity = rand(100.0:1000.0)
        )
        
        # Generate random bids
        n_bids = rand(5:20)
        bids = [
            Bid("bidder_$i", rand(10.0:200.0), rand(config.reserve_price:100.0))
            for i in 1:n_bids
        ]
        
        result = run_auction(bids, config)
        
        # Property 1: Clearing price >= reserve price
        @test result.clearing_price >= config.reserve_price
        
        # Property 2: Total allocated <= supply
        @test result.total_allocated <= config.supply_quantity
        
        # Property 3: Winners bid >= clearing price
        for allocation in result.allocations
            original_bid = findfirst(b -> b.bidder == allocation.bidder, bids)
            @test bids[original_bid].price >= result.clearing_price
        end
    end
end

property_test_auction(1000)
```

## Next Steps

- [API Reference](api_reference.md) - Complete API documentation
- [SDK Documentation](sdk.md) - Language-specific SDKs
- [WebSocket Guide](websocket.md) - Real-time communication