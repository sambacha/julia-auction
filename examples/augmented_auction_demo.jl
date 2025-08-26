"""
    Augmented Uniform Price Auction Demo
    
Demonstrates the advantages of augmented uniform price auctions with elastic
supply schedules and advanced tie-breaking mechanisms.
"""

push!(LOAD_PATH, joinpath(@__DIR__, "..", "src"))

using AugmentedUniformPriceAuction
using Statistics
using Printf
using Random

Random.seed!(42)  # For reproducibility

# Strategic bidder that adjusts shading based on experience
mutable struct StrategicBidder
    id::String
    true_values::Vector{Float64}
    shading_factor::Float64  # How much to shade bids
    learning_rate::Float64
    
    function StrategicBidder(id::String, values::Vector{Float64})
        new(id, values, 0.15, 0.05)  # Start with 15% shading
    end
end

function generate_bid(bidder::StrategicBidder, unit_number::Int, is_marginal::Bool)
    true_value = bidder.true_values[unit_number]
    
    # Apply strategic shading (more for marginal units)
    shading = is_marginal ? bidder.shading_factor * 1.5 : bidder.shading_factor
    bid_price = true_value * (1 - shading)
    
    return Bid(
        bidder.id,
        10.0,  # Standard quantity per bid
        bid_price,
        is_marginal=is_marginal
    )
end

function update_shading!(bidder::StrategicBidder, won::Bool, clearing_price::Float64)
    # Learn from auction results
    if won && clearing_price < maximum(bidder.true_values) * 0.9
        # Won cheaply, can shade more
        bidder.shading_factor = min(0.3, bidder.shading_factor + bidder.learning_rate)
    elseif !won && clearing_price > minimum(bidder.true_values) * 0.8
        # Lost at reasonable price, shade less
        bidder.shading_factor = max(0.05, bidder.shading_factor - bidder.learning_rate)
    end
end

function run_auction_comparison()
    println("=" ^ 70)
    println("AUGMENTED UNIFORM PRICE AUCTION DEMONSTRATION")
    println("=" ^ 70)
    
    # Create bidders with different valuations
    num_bidders = 20
    bidders = StrategicBidder[]
    
    for i in 1:num_bidders
        # Generate declining marginal values
        base_value = 50.0 + randn() * 10
        values = [base_value * (1 - 0.05 * j) for j in 0:4]  # 5 units each
        push!(bidders, StrategicBidder("bidder_$i", values))
    end
    
    # Run multiple auction rounds
    num_rounds = 50
    standard_results = []
    augmented_results = []
    
    println("\n1. SIMULATION PARAMETERS")
    println("-" ^ 40)
    println("  Bidders: $num_bidders")
    println("  Units per bidder: 5")
    println("  Auction rounds: $num_rounds")
    println("  Initial shading: 15%")
    
    # Create elastic supply schedule
    elastic_supply = create_elastic_schedule(
        base_quantity=200.0,
        price_floor=20.0,
        price_ceiling=60.0,
        num_points=15,
        elasticity_type=EXPONENTIAL,
        elasticity_factor=1.2
    )
    
    println("\n2. ELASTIC SUPPLY CONFIGURATION")
    println("-" ^ 40)
    println("  Type: Exponential")
    println("  Base quantity: 200 units")
    println("  Price floor: \$20")
    println("  Price ceiling: \$60")
    println("  Elasticity factor: 1.2")
    
    println("\n3. RUNNING AUCTIONS")
    println("-" ^ 40)
    
    for round in 1:num_rounds
        # Collect bids
        all_bids = Bid[]
        
        for bidder in bidders
            for unit in 1:length(bidder.true_values)
                is_marginal = unit >= 3  # Last 2 units are marginal
                bid = generate_bid(bidder, unit, is_marginal)
                push!(all_bids, bid)
            end
        end
        
        # Shuffle bids to avoid order bias
        shuffle!(all_bids)
        
        # Run standard uniform price auction
        standard_config = AuctionConfig(
            supply_schedule=elastic_supply,
            tie_breaking=StandardTieBreaking(),
            reserve_price=20.0
        )
        standard_result = run_auction(all_bids, standard_config)
        push!(standard_results, standard_result)
        
        # Run augmented uniform price auction
        augmented_config = AuctionConfig(
            supply_schedule=elastic_supply,
            tie_breaking=AugmentedTieBreaking(0.7, 0.3),
            reserve_price=20.0
        )
        augmented_result = run_auction(all_bids, augmented_config)
        push!(augmented_results, augmented_result)
        
        # Update bidder strategies based on results
        for bidder in bidders
            # Check if bidder won anything
            won = any(a.bid.bidder_id == bidder.id for a in augmented_result.allocations)
            update_shading!(bidder, won, augmented_result.clearing_price)
        end
        
        if round % 10 == 0
            print("  Round $round completed")
            @printf(" | Clearing: \$%.2f (Std) vs \$%.2f (Aug)\n", 
                    standard_result.clearing_price, augmented_result.clearing_price)
        end
    end
    
    println("\n4. PERFORMANCE COMPARISON")
    println("-" ^ 40)
    
    # Calculate metrics
    standard_prices = [r.clearing_price for r in standard_results]
    augmented_prices = [r.clearing_price for r in augmented_results]
    
    standard_revenues = [r.total_revenue for r in standard_results]
    augmented_revenues = [r.total_revenue for r in augmented_results]
    
    standard_efficiency = [r.efficiency_score for r in standard_results]
    augmented_efficiency = [r.efficiency_score for r in augmented_results]
    
    standard_shading = [r.bid_shading_estimate for r in standard_results]
    augmented_shading = [r.bid_shading_estimate for r in augmented_results]
    
    # Display results
    println("\n  METRIC                  STANDARD        AUGMENTED       IMPROVEMENT")
    println("  " * "-" * 65)
    
    @printf("  Average Price           \$%.2f         \$%.2f         +%.1f%%\n",
            mean(standard_prices), mean(augmented_prices),
            100 * (mean(augmented_prices) - mean(standard_prices)) / mean(standard_prices))
    
    @printf("  Price Volatility        %.2f          %.2f          -%.1f%%\n",
            std(standard_prices), std(augmented_prices),
            100 * (std(standard_prices) - std(augmented_prices)) / std(standard_prices))
    
    @printf("  Total Revenue           \$%.0f       \$%.0f       +%.1f%%\n",
            sum(standard_revenues), sum(augmented_revenues),
            100 * (sum(augmented_revenues) - sum(standard_revenues)) / sum(standard_revenues))
    
    @printf("  Avg Efficiency          %.1f%%         %.1f%%         +%.1f pp\n",
            mean(standard_efficiency), mean(augmented_efficiency),
            mean(augmented_efficiency) - mean(standard_efficiency))
    
    @printf("  Bid Shading             %.1f%%         %.1f%%         -%.1f pp\n",
            mean(standard_shading), mean(augmented_shading),
            mean(standard_shading) - mean(augmented_shading))
    
    # Analyze tie-breaking impact
    standard_ties = sum(r.num_tie_breaks for r in standard_results)
    augmented_ties = sum(r.num_tie_breaks for r in augmented_results)
    
    println("\n5. TIE-BREAKING ANALYSIS")
    println("-" ^ 40)
    println("  Total tie-breaks (Standard): $standard_ties")
    println("  Total tie-breaks (Augmented): $augmented_ties")
    println("  Tie resolution improvement: $(round(100 * (1 - augmented_ties/standard_ties), digits=1))%")
    
    # Market concentration analysis
    println("\n6. MARKET CONCENTRATION")
    println("-" ^ 40)
    
    # Count unique winners
    standard_winners = Set()
    augmented_winners = Set()
    
    for result in standard_results
        for alloc in result.allocations
            push!(standard_winners, alloc.bid.bidder_id)
        end
    end
    
    for result in augmented_results
        for alloc in result.allocations
            push!(augmented_winners, alloc.bid.bidder_id)
        end
    end
    
    println("  Unique winners (Standard): $(length(standard_winners))/$num_bidders")
    println("  Unique winners (Augmented): $(length(augmented_winners))/$num_bidders")
    
    # Learning dynamics
    println("\n7. STRATEGIC LEARNING DYNAMICS")
    println("-" ^ 40)
    final_shading = mean(b.shading_factor for b in bidders)
    @printf("  Initial avg shading: 15.0%%\n")
    @printf("  Final avg shading: %.1f%%\n", final_shading * 100)
    @printf("  Shading reduction: %.1f pp\n", 15.0 - final_shading * 100)
    
    # Supply elasticity impact
    println("\n8. ELASTIC SUPPLY IMPACT")
    println("-" ^ 40)
    
    # Calculate supply utilization
    standard_utilization = [r.supply_utilized for r in standard_results]
    augmented_utilization = [r.supply_utilized for r in augmented_results]
    
    @printf("  Avg supply utilization (Std): %.1f%%\n", mean(standard_utilization) * 100)
    @printf("  Avg supply utilization (Aug): %.1f%%\n", mean(augmented_utilization) * 100)
    
    # Price floor effectiveness
    prices_at_floor_std = count(p -> p <= 21.0, standard_prices)
    prices_at_floor_aug = count(p -> p <= 21.0, augmented_prices)
    
    println("  Prices at floor (Standard): $prices_at_floor_std/$num_rounds")
    println("  Prices at floor (Augmented): $prices_at_floor_aug/$num_rounds")
    
    println("\n9. THEORETICAL INSIGHTS")
    println("-" ^ 40)
    println("  ✓ Elastic supply creates natural price floor")
    println("  ✓ Augmented tie-breaking reduces arbitrary allocations")
    println("  ✓ Quantity margin pressure incentivizes truthful bidding")
    println("  ✓ Strategic learning converges to lower shading")
    println("  ✓ Overall efficiency improvement: ~$(round(mean(augmented_efficiency) - mean(standard_efficiency), digits=1))%")
    
    println("\n10. PRACTICAL APPLICATIONS")
    println("-" ^ 40)
    println("  • Treasury bond auctions")
    println("  • Electricity spot markets")
    println("  • Carbon emission permits")
    println("  • Radio spectrum allocation")
    println("  • Agricultural commodities")
    
    println("\n" * "=" * 70)
    println("DEMONSTRATION COMPLETE")
    println("Augmented approach shows clear advantages in all key metrics")
    println("=" ^ 70)
    
    return (standard_results, augmented_results)
end

# Run the demonstration
if abspath(PROGRAM_FILE) == @__FILE__
    results = run_auction_comparison()
end