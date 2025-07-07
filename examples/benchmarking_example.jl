"""
Advanced benchmarking example for the auction simulation system.

This example demonstrates comprehensive performance analysis and comparison
of different auction mechanisms at scale.
"""

include("../src/simulation.jl")

# Define example auction types
struct FirstPriceAuction
    name::String
    FirstPriceAuction() = new("FirstPrice")
end

struct SecondPriceAuction
    name::String
    SecondPriceAuction() = new("SecondPrice")
end

# Define example bidder types
struct ConservativeBidder
    risk_factor::Float64
    ConservativeBidder() = new(0.85)
end

struct AggressiveBidder
    risk_factor::Float64
    AggressiveBidder() = new(0.95)
end

struct RandomBidder
    risk_factor::Float64
    RandomBidder() = new(0.7 + 0.3 * rand())
end

# Implement bidding logic
function make_bid(bidder::ConservativeBidder, valuation, auction)
    return valuation * bidder.risk_factor
end

function make_bid(bidder::AggressiveBidder, valuation, auction)
    return valuation * bidder.risk_factor
end

function make_bid(bidder::RandomBidder, valuation, auction)
    return valuation * bidder.risk_factor
end

# Implement auction logic
function conduct_auction(auction::FirstPriceAuction, bids, reserve_price)
    if isempty(bids)
        return (revenue=0.0, winning_bid=0.0, winner_id=0)
    end
    
    valid_bids = filter(bid -> bid[1] >= reserve_price, bids)
    if isempty(valid_bids)
        return (revenue=0.0, winning_bid=0.0, winner_id=0)
    end
    
    winning_bid_info = valid_bids[argmax([bid[1] for bid in valid_bids])]
    winning_bid = winning_bid_info[1]
    winner_id = winning_bid_info[2]
    
    return (revenue=winning_bid, winning_bid=winning_bid, winner_id=winner_id)
end

function conduct_auction(auction::SecondPriceAuction, bids, reserve_price)
    if isempty(bids)
        return (revenue=0.0, winning_bid=0.0, winner_id=0)
    end
    
    valid_bids = filter(bid -> bid[1] >= reserve_price, bids)
    if isempty(valid_bids)
        return (revenue=0.0, winning_bid=0.0, winner_id=0)
    end
    
    sorted_bids = sort(valid_bids, by=bid -> bid[1], rev=true)
    winning_bid = sorted_bids[1][1]
    winner_id = sorted_bids[1][2]
    
    # Second price: pay second highest bid or reserve price
    second_price = length(sorted_bids) > 1 ? sorted_bids[2][1] : reserve_price
    
    return (revenue=second_price, winning_bid=winning_bid, winner_id=winner_id)
end

# Bidder creation functions
function create_conservative_population()
    return [ConservativeBidder() for _ in 1:2]
end

function create_aggressive_population()
    return [AggressiveBidder() for _ in 1:2]
end

function create_mixed_population()
    return [ConservativeBidder(), AggressiveBidder()]
end

function create_random_population()
    return [RandomBidder() for _ in 1:2]
end

# Enhanced bidder creation for different sizes
function create_bidders_for_size(base_func, size::Int)
    base_bidders = base_func()
    result = []
    
    for i in 1:size
        base_idx = ((i - 1) % length(base_bidders)) + 1
        base_bidder = base_bidders[base_idx]
        
        # Create variations
        if base_bidder isa ConservativeBidder
            push!(result, ConservativeBidder())
        elseif base_bidder isa AggressiveBidder
            push!(result, AggressiveBidder())
        else
            push!(result, RandomBidder())
        end
    end
    
    return result
end

println("=== Advanced Benchmarking Example ===")

# Example 1: Compare auction mechanisms
println("\n1. Comparing Auction Mechanisms")

auction_types = [FirstPriceAuction(), SecondPriceAuction()]
config = AuctionConfig(num_rounds=1000, seed=42)

# Test with mixed population
mixed_bidders = create_mixed_population()

results = []
for auction_type in auction_types
    println("Running $(auction_type.name) auction...")
    result = run_simulation(auction_type, mixed_bidders, config)
    push!(results, result)
    
    summary = generate_summary_statistics(result)
    println("  Average revenue: $(round(summary["revenue_mean"], digits=2))")
    println("  Average efficiency: $(round(summary["efficiency_mean"], digits=3))")
    println("  Revenue volatility: $(round(summary["bidder_performance"]["revenue_volatility"], digits=3))")
end

# Example 2: Population composition analysis
println("\n2. Population Composition Analysis")

population_configs = [
    ("Conservative", create_conservative_population),
    ("Aggressive", create_aggressive_population),
    ("Mixed", create_mixed_population),
    ("Random", create_random_population)
]

auction = FirstPriceAuction()
comparison_config = AuctionConfig(num_rounds=500, seed=42)

population_results = []
for (name, pop_func) in population_configs
    println("Testing $(name) population...")
    bidders = pop_func()
    result = run_simulation(auction, bidders, comparison_config)
    push!(population_results, (name, result))
    
    summary = generate_summary_statistics(result)
    println("  Revenue: $(round(summary["revenue_mean"], digits=2)) ± $(round(summary["revenue_std"], digits=2))")
    println("  Efficiency: $(round(summary["efficiency_mean"], digits=3))")
    println("  Market concentration: $(round(summary["bidder_performance"]["market_concentration"], digits=3))")
end

# Example 3: Scalability analysis
println("\n3. Scalability Analysis")

sizes = [5, 10, 20, 50]
auction = FirstPriceAuction()
scale_config = AuctionConfig(num_rounds=100, seed=42)

scalability_results = []
for size in sizes
    println("Testing with $(size) bidders...")
    bidders = create_bidders_for_size(create_mixed_population, size)
    
    # Time the simulation
    start_time = time()
    result = run_simulation(auction, bidders, scale_config)
    end_time = time()
    
    push!(scalability_results, (size, result, end_time - start_time))
    
    summary = generate_summary_statistics(result)
    println("  Execution time: $(round(end_time - start_time, digits=3)) seconds")
    println("  Rounds per second: $(round(summary["rounds_per_second"], digits=1))")
    println("  Average revenue: $(round(summary["revenue_mean"], digits=2))")
end

# Example 4: Configuration sensitivity analysis
println("\n4. Configuration Sensitivity Analysis")

base_config = AuctionConfig(num_rounds=200, seed=42)
configs = [
    ("Low Reserve", AuctionConfig(num_rounds=200, reserve_price=5.0, seed=42)),
    ("Medium Reserve", AuctionConfig(num_rounds=200, reserve_price=25.0, seed=42)),
    ("High Reserve", AuctionConfig(num_rounds=200, reserve_price=50.0, seed=42)),
    ("Wide Range", AuctionConfig(num_rounds=200, min_value=1.0, max_value=200.0, seed=42)),
    ("Narrow Range", AuctionConfig(num_rounds=200, min_value=40.0, max_value=60.0, seed=42))
]

auction = FirstPriceAuction()
test_bidders = create_mixed_population()

for (name, config) in configs
    println("Testing $(name) configuration...")
    result = run_simulation(auction, test_bidders, config)
    summary = generate_summary_statistics(result)
    
    println("  Revenue: $(round(summary["revenue_mean"], digits=2))")
    println("  Efficiency: $(round(summary["efficiency_mean"], digits=3))")
    println("  Successful auctions: $(round(sum(result.revenues .> 0) / length(result.revenues) * 100, digits=1))%")
end

# Example 5: Statistical analysis
println("\n5. Statistical Analysis")

# Run multiple simulations with different seeds for statistical significance
n_simulations = 10
auction = FirstPriceAuction()
bidders = create_mixed_population()
base_config = AuctionConfig(num_rounds=100)

revenues = []
efficiencies = []

for i in 1:n_simulations
    config = AuctionConfig(num_rounds=100, seed=i)
    result = run_simulation(auction, bidders, config)
    push!(revenues, mean(result.revenues))
    push!(efficiencies, mean(result.efficiencies))
end

println("Statistical Summary ($(n_simulations) simulations):")
println("  Revenue mean: $(round(mean(revenues), digits=2)) ± $(round(std(revenues), digits=2))")
println("  Revenue range: $(round(minimum(revenues), digits=2)) - $(round(maximum(revenues), digits=2))")
println("  Efficiency mean: $(round(mean(efficiencies), digits=3)) ± $(round(std(efficiencies), digits=3))")
println("  Efficiency range: $(round(minimum(efficiencies), digits=3)) - $(round(maximum(efficiencies), digits=3))")

# Example 6: Performance profiling
println("\n6. Performance Profiling")

# Profile memory usage for different configurations
memory_configs = [
    ("Small", AuctionConfig(num_rounds=100)),
    ("Medium", AuctionConfig(num_rounds=1000)),
    ("Large", AuctionConfig(num_rounds=5000))
]

auction = FirstPriceAuction()
test_bidders = create_mixed_population()

for (name, config) in memory_configs
    # Force garbage collection before test
    GC.gc()
    
    result = run_simulation(auction, test_bidders, config)
    summary = generate_summary_statistics(result)
    
    println("$(name) simulation:")
    println("  Rounds: $(config.num_rounds)")
    println("  Time: $(round(result.total_time, digits=3))s")
    println("  Memory: $(round(summary["memory_usage_mb"], digits=2))MB")
    println("  Allocations per round: $(round(summary["allocations_per_round"], digits=1))")
end

# Example 7: Comparative efficiency metrics
println("\n7. Comparative Efficiency Metrics")

# Compare efficiency across different scenarios
scenarios = [
    ("2 Bidders", create_bidders_for_size(create_mixed_population, 2)),
    ("5 Bidders", create_bidders_for_size(create_mixed_population, 5)),
    ("10 Bidders", create_bidders_for_size(create_mixed_population, 10))
]

auction_types = [FirstPriceAuction(), SecondPriceAuction()]
config = AuctionConfig(num_rounds=500, seed=42)

for (scenario_name, bidders) in scenarios
    println("Scenario: $(scenario_name)")
    
    for auction_type in auction_types
        result = run_simulation(auction_type, bidders, config)
        summary = generate_summary_statistics(result)
        
        println("  $(auction_type.name):")
        println("    Efficiency: $(round(summary["efficiency_mean"], digits=3))")
        println("    Revenue: $(round(summary["revenue_mean"], digits=2))")
        println("    Market concentration: $(round(summary["bidder_performance"]["market_concentration"], digits=3))")
    end
end

println("\n=== Benchmarking Complete ===")
println("This example demonstrates comprehensive benchmarking capabilities:")
println("• Auction mechanism comparison")
println("• Population composition analysis")
println("• Scalability testing")
println("• Configuration sensitivity")
println("• Statistical analysis")
println("• Performance profiling")
println("• Efficiency metrics comparison")