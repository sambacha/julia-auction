#!/usr/bin/env julia
"""
Demonstration of all auction types in AuctionKit.jl

This example shows how to use each auction type with the unified interface.
"""

using AuctionKit
using UUIDs
using Dates
using Random

Random.seed!(42)  # For reproducibility

# Helper function to create sample bidders
function create_sample_bidders(n::Int; valuation_range=(10.0, 100.0))
    bidders = Bidder{Float64}[]
    for i in 1:n
        valuation = rand() * (valuation_range[2] - valuation_range[1]) + valuation_range[1]
        budget = valuation * 1.2  # Budget slightly above valuation
        push!(bidders, Bidder("Bidder_$i", budget, valuation))
    end
    return bidders
end

# Helper function to create bids from bidders
function create_bids_from_bidders(bidders::Vector{Bidder{Float64}}, strategy::Symbol=:truthful)
    bids = Bid{Float64}[]
    for bidder in bidders
        if strategy == :truthful
            amount = bidder.valuation
        elseif strategy == :shaded
            amount = bidder.valuation * 0.85  # 15% shading
        elseif strategy == :random
            amount = bidder.valuation * (0.7 + 0.3 * rand())
        else
            amount = bidder.valuation
        end
        
        push!(bids, Bid(bidder.id, amount, 1))
    end
    return bids
end

# Create sample bidders and bids
println("="^60)
println("Creating sample bidders and bids...")
println("="^60)

bidders = create_sample_bidders(10)
bids = create_bids_from_bidders(bidders, :random)

println("Created $(length(bidders)) bidders with valuations ranging from $(minimum(b.valuation for b in bidders)) to $(maximum(b.valuation for b in bidders))")
println()

# Define auction configurations
auction_configs = Dict{Symbol, UnifiedAuctionConfig{Float64}}(
    :first_price => UnifiedAuctionConfig(
        auction_type = :first_price,
        reserve_price = 20.0
    ),
    :second_price => UnifiedAuctionConfig(
        auction_type = :second_price,
        reserve_price = 20.0
    ),
    :dutch => UnifiedAuctionConfig(
        auction_type = :dutch,
        reserve_price = 15.0,
        metadata = Dict(:decrement => 5.0)
    ),
    :english => UnifiedAuctionConfig(
        auction_type = :english,
        reserve_price = 20.0,
        metadata = Dict(:increment => 5.0)
    ),
    :japanese => UnifiedAuctionConfig(
        auction_type = :japanese,
        reserve_price = 20.0,
        metadata = Dict(:increment => 3.0, :min_active_bidders => 2)
    ),
    :candle => UnifiedAuctionConfig(
        auction_type = :candle,
        reserve_price = 20.0,
        metadata = Dict(:min_duration => 1.0, :max_duration => 10.0)
    ),
    :penny => UnifiedAuctionConfig(
        auction_type = :penny,
        reserve_price = 1.0,
        metadata = Dict(:bid_increment => 0.01, :bid_cost => 0.50)
    ),
    :all_pay => UnifiedAuctionConfig(
        auction_type = :all_pay,
        reserve_price = 10.0,
        metadata = Dict(:prize_structure => :winner_takes_all, :refund_rate => 0.0)
    )
)

# For double auction, create buy and sell orders
function create_double_auction_bids(n_buyers::Int, n_sellers::Int)
    bids = Bid{Float64}[]
    
    # Create buy orders (higher prices)
    for i in 1:n_buyers
        price = 50.0 + rand() * 50.0
        bid = Bid(uuid4(), price, rand(1:5))
        # Mark as buy order in metadata
        bid.metadata[:is_buy] = true
        push!(bids, bid)
    end
    
    # Create sell orders (lower prices)
    for i in 1:n_sellers
        price = 20.0 + rand() * 40.0
        bid = Bid(uuid4(), price, rand(1:5))
        # Mark as sell order in metadata
        bid.metadata[:is_buy] = false
        push!(bids, bid)
    end
    
    return bids
end

double_bids = create_double_auction_bids(5, 5)
auction_configs[:double] = UnifiedAuctionConfig(
    auction_type = :double,
    reserve_price = 0.0,
    metadata = Dict(:price_rule => :uniform)
)

# For combinatorial auction, create bundle bids
function create_combinatorial_bids(items::Vector{Symbol}, n_bidders::Int)
    bids = Bid{Float64}[]
    
    for i in 1:n_bidders
        # Create random bundle
        bundle_size = rand(1:min(3, length(items)))
        bundle = Symbol[items[j] for j in randperm(length(items))[1:bundle_size]]
        
        # Value increases with bundle size
        base_value = 20.0 * bundle_size
        bid_value = base_value + rand() * 30.0
        
        bid = Bid(uuid4(), bid_value, 1)
        bid.metadata[:bundle] = bundle
        push!(bids, bid)
    end
    
    return bids
end

items = [:item_A, :item_B, :item_C, :item_D]
combinatorial_bids = create_combinatorial_bids(items, 8)
auction_configs[:combinatorial] = UnifiedAuctionConfig(
    auction_type = :combinatorial,
    reserve_price = 0.0,
    metadata = Dict(:items => items)
)

# Run all auction types
println("="^60)
println("Running all auction types...")
println("="^60)
println()

results = Dict{Symbol, StandardizedResult{Float64}}()

for (name, config) in auction_configs
    println("-"^40)
    println("Running $name auction...")
    println("-"^40)
    
    # Select appropriate bids for each auction type
    auction_bids = if name == :double
        double_bids
    elseif name == :combinatorial
        combinatorial_bids
    else
        bids
    end
    
    try
        result = run_unified_auction(config, auction_bids)
        results[name] = result
        
        # Display results
        println("Clearing price: \$$(round(result.clearing_price, digits=2))")
        println("Number of winners: $(length(result.winners))")
        println("Total revenue: \$$(round(result.revenue, digits=2))")
        
        if !isempty(result.allocations)
            println("Top allocation: $(round(maximum(abs.(values(result.allocations))), digits=2)) units")
        end
        
        # Auction-specific metrics
        if haskey(result.metadata, :total_surplus)
            println("Total surplus: \$$(round(result.metadata[:total_surplus], digits=2))")
        end
        if haskey(result.metadata, :price_levels)
            println("Price levels: $(result.metadata[:price_levels])")
        end
        if haskey(result.metadata, :actual_duration)
            println("Auction duration: $(round(result.metadata[:actual_duration], digits=2)) seconds")
        end
        
    catch e
        println("Error running $name auction: $e")
    end
    
    println()
end

# Compare auction performance
println("="^60)
println("Comparing auction performance...")
println("="^60)
println()

# Create comparison table
println("Auction Type    | Revenue  | Winners | Efficiency")
println("----------------|----------|---------|------------")

for (name, result) in sort(collect(results), by=x->x[1])
    metrics = analyze_auction_performance(result)
    
    revenue_str = lpad(round(result.revenue, digits=2), 8)
    winners_str = lpad(length(result.winners), 7)
    efficiency_str = lpad(round(metrics[:efficiency] * 100, digits=1), 10) * "%"
    
    println("$(rpad(string(name), 15)) | \$$revenue_str | $winners_str | $efficiency_str")
end

println()
println("="^60)
println("Auction recommendation based on characteristics...")
println("="^60)

# Test recommendation system
scenarios = [
    Dict(:num_bidders => 3, :bid_variance => 0.1, :time_sensitive => false),
    Dict(:num_bidders => 20, :bid_variance => 0.8, :time_sensitive => true),
    Dict(:num_bidders => 10, :bid_variance => 0.5, :bundle_bids => true),
    Dict(:num_bidders => 15, :bid_variance => 0.3, :two_sided => true)
]

for (i, scenario) in enumerate(scenarios)
    recommended = recommend_auction_type(scenario)
    println("\nScenario $i: $scenario")
    println("  → Recommended auction type: $recommended")
end

println()
println("="^60)
println("Demo completed successfully!")
println("="^60)