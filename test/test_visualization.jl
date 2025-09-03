"""
Simple test of visualization functionality
"""

using AuctionSimulator
using AuctionSimulator.AuctionVisualizer
using Random
using Plots

# Set up for non-interactive plotting
ENV["GKSwstype"] = "100"  # Use headless GKS for CI/testing

Random.seed!(42)

println("Testing Auction Visualizations...")

# Create simple bidders
bidders = [
    Bidder(1, 100.0, TruthfulBidder(100.0)),
    Bidder(2, 90.0, TruthfulBidder(90.0)),
    Bidder(3, 110.0, ShadedBidder(110.0, 0.2)),
]

# Run a few auction rounds
results = []
for i = 1:10
    auction = FirstPriceAuction()
    result = conduct_auction(auction, bidders)
    push!(results, result)
end

# Collect visualization data
viz_data = collect_auction_data(results, bidders)

println("Auction data collected:")
println("  - Rounds: $(length(viz_data.rounds))")
println("  - Average Revenue: $(round(viz_data.metadata["avg_revenue"], digits=2))")
println("  - Average Efficiency: $(round(viz_data.metadata["avg_efficiency"], digits=3))")

# Test each visualization function
println("\nTesting visualization functions...")

# Test bid progression
p1 = plot_bid_progression(viz_data)
println("✓ Bid progression plot created")

# Test revenue efficiency
p2 = plot_revenue_efficiency(viz_data)
println("✓ Revenue/efficiency plot created")

# Test winner distribution
p3 = plot_winner_distribution(viz_data)
println("✓ Winner distribution plot created")

# Test competition analysis
p4 = plot_competition_analysis(viz_data)
println("✓ Competition analysis plot created")

# Test dashboard creation
dashboard = create_auction_dashboard(viz_data)
println("✓ Dashboard created")

# Save a sample plot
mkpath("test_output")
savefig(dashboard, "test_output/test_dashboard.png")
println("✓ Dashboard saved to test_output/test_dashboard.png")

println("\n✅ All visualization tests passed!")
println("\nVisualization module is ready for use.")
println("You can generate graphs for different auction stages:")
println("  - Pre-auction: Bidder valuations and expectations")
println("  - During auction: Real-time bid progression")
println("  - Post-auction: Winner analysis, efficiency, revenue")
println("\nUse the examples in examples/ directory for more detailed demonstrations.")
