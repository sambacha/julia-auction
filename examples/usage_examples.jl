"""
Usage Examples for AuctionSimulator.jl

This file demonstrates how to use the auction simulation library with various
auction types and bidding strategies.
"""

using AuctionSimulator
using Random
using Statistics

# Set random seed for reproducibility
Random.seed!(42)

println("=== AuctionSimulator.jl Usage Examples ===\n")

# Example 1: Basic First-Price Auction
println("1. Basic First-Price Auction")
println("=" ^ 30)

# Create bidders with different strategies
bidders = [
    Bidder(1, 100.0, TruthfulBidder(100.0)),
    Bidder(2, 80.0, ShadedBidder(80.0, 0.1)),
    Bidder(3, 120.0, TruthfulBidder(120.0)),
    Bidder(4, 90.0, ShadedBidder(90.0, 0.2))
]

# Create first-price auction
auction = FirstPriceAuction(10.0)  # Reserve price of 10.0

# Run the auction
result = conduct_auction(auction, bidders)

println("Winner: Bidder $(result.winner_id)")
println("Winning Price: $(result.winning_price)")
println("Total Bids: $(length(result.all_bids))")
println("Efficiency: $(result.statistics["efficiency"])")
println()

# Example 2: Second-Price Auction
println("2. Second-Price Auction")
println("=" ^ 30)

# Create second-price auction
auction2 = SecondPriceAuction(15.0)  # Reserve price of 15.0

# Run the auction
result2 = conduct_auction(auction2, bidders)

println("Winner: Bidder $(result2.winner_id)")
println("Winning Price: $(result2.winning_price)")
println("Total Bids: $(length(result2.all_bids))")
println("Efficiency: $(result2.statistics["efficiency"])")
println()

# Example 3: Auction with Strategic Bidders
println("3. Strategic Bidders")
println("=" ^ 30)

strategic_bidders = [
    Bidder(1, 100.0, StrategicBidder(100.0, 5)),
    Bidder(2, 80.0, StrategicBidder(80.0, 5)),
    Bidder(3, 120.0, StrategicBidder(120.0, 5)),
    Bidder(4, 90.0, StrategicBidder(90.0, 5)),
    Bidder(5, 110.0, StrategicBidder(110.0, 5))
]

# Test both auction types
first_price_strategic = conduct_auction(FirstPriceAuction(0.0), strategic_bidders)
second_price_strategic = conduct_auction(SecondPriceAuction(0.0), strategic_bidders)

println("First-Price with Strategic Bidders:")
println("  Winner: Bidder $(first_price_strategic.winner_id)")
println("  Price: $(first_price_strategic.winning_price)")
println("  Efficiency: $(first_price_strategic.statistics["efficiency"])")

println("Second-Price with Strategic Bidders:")
println("  Winner: Bidder $(second_price_strategic.winner_id)")
println("  Price: $(second_price_strategic.winning_price)")
println("  Efficiency: $(second_price_strategic.statistics["efficiency"])")
println()

# Example 4: Auction with Random Bidders
println("4. Random Bidders")
println("=" ^ 30)

random_bidders = [
    Bidder(1, 100.0, RandomBidder(TruthfulBidder(100.0), 5.0)),
    Bidder(2, 80.0, RandomBidder(ShadedBidder(80.0, 0.1), 3.0)),
    Bidder(3, 120.0, RandomBidder(TruthfulBidder(120.0), 8.0))
]

random_result = conduct_auction(FirstPriceAuction(0.0), random_bidders)

println("Winner: Bidder $(random_result.winner_id)")
println("Winning Price: $(random_result.winning_price)")
println("Efficiency: $(random_result.statistics["efficiency"])")
println()

# Example 5: Simulation with Multiple Rounds
println("5. Multiple Round Simulation")
println("=" ^ 30)

# Create a simple simulation configuration
config = AuctionConfig(
    num_rounds = 100,
    min_value = 10.0,
    max_value = 100.0,
    reserve_price = 5.0,
    seed = 123
)

# Run simulation for first-price auction
first_price_sim = run_simulation(FirstPriceAuction(), bidders, config)

println("First-Price Simulation Results:")
println("  Average Revenue: $(mean(first_price_sim.revenues))")
println("  Average Efficiency: $(mean(first_price_sim.efficiencies))")
println("  Total Rounds: $(length(first_price_sim.revenues))")
println("  Total Time: $(first_price_sim.total_time) seconds")
println()

# Run simulation for second-price auction
second_price_sim = run_simulation(SecondPriceAuction(), bidders, config)

println("Second-Price Simulation Results:")
println("  Average Revenue: $(mean(second_price_sim.revenues))")
println("  Average Efficiency: $(mean(second_price_sim.efficiencies))")
println("  Total Rounds: $(length(second_price_sim.revenues))")
println("  Total Time: $(second_price_sim.total_time) seconds")
println()

# Example 6: Simple Performance Comparison
println("6. Simple Performance Comparison")
println("=" ^ 30)

# Create benchmark configuration
auction_types = [
    (FirstPriceAuction(), "First-Price"),
    (SecondPriceAuction(), "Second-Price")
]

bidder_sizes = [5, 10, 20]

println("Comparing auction performance:")
for (auction, name) in auction_types
    println("$(name) Auction:")
    for size in bidder_sizes
        # Create bidders for this size
        test_bidders = [
            Bidder(i, 50.0 + 50.0*rand(), TruthfulBidder(50.0 + 50.0*rand()))
            for i in 1:size
        ]
        
        # Measure execution time
        start_time = time()
        result = conduct_auction(auction, test_bidders)
        end_time = time()
        
        println("  $(size) bidders: $(round((end_time - start_time) * 1000, digits=3)) ms")
    end
    println()
end

println("=== Examples Complete ===")