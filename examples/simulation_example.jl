"""
Example usage of the simulation engine and benchmarking utilities.

This file demonstrates how to use the simulation.jl module for running
auction simulations and performance benchmarks.
"""

# Note: This example assumes the existence of actual auction and bidder types
# which would be implemented by other agents in the system.

include("../src/simulation.jl")

# Example 1: Basic Simulation Configuration
println("=== Basic Simulation Example ===")

# Create a basic configuration
config = AuctionConfig(
    num_rounds=1000,
    min_value=10.0,
    max_value=100.0,
    reserve_price=5.0,
    seed=42
)

println("Configuration created:")
println("  Rounds: $(config.num_rounds)")
println("  Value range: $(config.min_value) - $(config.max_value)")
println("  Reserve price: $(config.reserve_price)")
println("  Seed: $(config.seed)")

# Example 2: Running a Simulation
println("\n=== Running Simulation Example ===")

# Create mock bidders for demonstration
struct ExampleBidder
    strategy_factor::Float64
    name::String
end

# Override the make_bid function for our example
function make_bid(bidder::ExampleBidder, valuation, auction)
    return valuation * bidder.strategy_factor
end

# Create bidders with different strategies
bidders = [
    ExampleBidder(0.9, "Conservative"),
    ExampleBidder(0.95, "Moderate"),
    ExampleBidder(0.85, "Aggressive")
]

# Create a mock auction type
struct ExampleAuction
    auction_type::String
end

# Run simulation with quick config for demonstration
quick_config = quick_test_config()
result = run_simulation(ExampleAuction("FirstPrice"), bidders, quick_config)

println("Simulation completed!")
println("  Auction type: $(result.auction_type)")
println("  Total rounds: $(length(result.revenues))")
println("  Average revenue: $(round(mean(result.revenues), digits=2))")
println("  Average efficiency: $(round(mean(result.efficiencies), digits=2))")
println("  Execution time: $(round(result.total_time, digits=3)) seconds")

# Example 3: Analyzing Results
println("\n=== Analysis Example ===")

# Generate summary statistics
summary = generate_summary_statistics(result)

println("Summary Statistics:")
println("  Revenue mean: $(round(summary["revenue_mean"], digits=2))")
println("  Revenue std: $(round(summary["revenue_std"], digits=2))")
println("  Efficiency mean: $(round(summary["efficiency_mean"], digits=2))")
println("  Rounds per second: $(round(summary["rounds_per_second"], digits=1))")

# Analyze bidder performance
bidder_analysis = analyze_bidder_performance(result)
println("\nBidder Performance:")
for (bidder_id, win_rate) in bidder_analysis["win_rates"]
    println("  Bidder $bidder_id: $(round(win_rate * 100, digits=1))% win rate")
end
println("  Market concentration (HHI): $(round(bidder_analysis["market_concentration"], digits=3))")

# Example 4: Benchmarking Multiple Configurations
println("\n=== Benchmarking Example ===")

# Create different auction types
auction_types = [
    ExampleAuction("FirstPrice"),
    ExampleAuction("SecondPrice")
]

# Create bidder configuration function
function create_test_bidders()
    return [
        ExampleBidder(0.9, "Conservative"),
        ExampleBidder(0.95, "Moderate")
    ]
end

# Test different population sizes
sizes = [5, 10, 20]

println("Running benchmark with $(length(auction_types)) auction types and $(length(sizes)) population sizes...")

# Note: This would normally run the full benchmark, but we'll use a smaller scale for demonstration
# benchmark_result = benchmark_auction(auction_types, [create_test_bidders], sizes)

# Example 5: Configuration Presets
println("\n=== Configuration Presets ===")

# Show different preset configurations
configs = [
    ("Default", default_config()),
    ("Quick Test", quick_test_config()),
    ("Stress Test", stress_test_config())
]

for (name, config) in configs
    println("$(name) Configuration:")
    println("  Rounds: $(config.num_rounds)")
    println("  Items: $(config.num_items)")
    println("  Value range: $(config.min_value) - $(config.max_value)")
    println("  Parallel: $(config.parallel)")
    println()
end

# Example 6: Custom Configuration with Validation
println("=== Custom Configuration Example ===")

try
    # This will work
    valid_config = AuctionConfig(
        num_rounds=500,
        min_value=20.0,
        max_value=200.0,
        reserve_price=15.0,
        seed=123
    )
    println("Valid configuration created successfully!")
    
    # This will fail validation
    invalid_config = AuctionConfig(
        num_rounds=0,  # Invalid: must be positive
        min_value=100.0,
        max_value=50.0  # Invalid: max must be greater than min
    )
catch e
    println("Configuration validation caught error: $(e)")
end

# Example 7: Efficiency Analysis
println("\n=== Efficiency Analysis Example ===")

# Create a scenario with different efficiency levels
function simulate_efficiency_scenario()
    # Mock different auction results with varying efficiency
    config = AuctionConfig(num_rounds=100)
    
    # Create results with known efficiency patterns
    revenues = rand(50:100, 100)
    efficiencies = [0.9, 0.8, 1.0, 0.7, 0.95]  # Mix of efficiency levels
    winning_bids = revenues
    bidder_wins = Dict(1 => 40, 2 => 35, 3 => 25)
    
    result = SimulationResult(
        "EfficiencyTest",
        config,
        revenues,
        repeat(efficiencies, 20),  # Repeat to get 100 values
        winning_bids,
        bidder_wins,
        2.0,
        1000,
        500
    )
    
    return result
end

efficiency_result = simulate_efficiency_scenario()
overall_efficiency = calculate_efficiency(efficiency_result)
println("Overall efficiency: $(round(overall_efficiency, digits=3))")

# Show efficiency distribution
println("Efficiency distribution:")
for eff in unique(efficiency_result.efficiencies)
    count = sum(efficiency_result.efficiencies .== eff)
    println("  $(eff): $(count) rounds")
end

println("\n=== Example Complete ===")
println("This example demonstrates the core functionality of the simulation module.")
println("In a real implementation, you would:")
println("1. Create actual auction types (FirstPriceAuction, SecondPriceAuction)")
println("2. Implement bidder strategies (SimpleBidder, StrategicBidder, etc.)")
println("3. Run large-scale simulations with thousands of rounds")
println("4. Compare different auction mechanisms")
println("5. Analyze market dynamics and bidder behavior")