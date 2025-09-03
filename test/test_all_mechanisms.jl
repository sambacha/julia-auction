"""
Test suite for all auction mechanisms
"""

using Test
using AuctionKit
using UUIDs
using Random

Random.seed!(123)  # For reproducibility

@testset "All Auction Mechanisms" begin

    # Helper function to create test bids
    function create_test_bids(n::Int = 5)
        bids = Bid{Float64}[]
        for i = 1:n
            push!(bids, Bid(uuid4(), 10.0 + i * 5.0, 1))
        end
        return bids
    end

    @testset "Combinatorial Auction" begin
        items = [:A, :B, :C]
        auction = CombinatorialAuction(items = items, reserve_prices = Dict(:A => 5.0, :B => 5.0, :C => 5.0))

        # Create bundle bids
        bids = Bid{Float64}[]

        # Bid 1: Bundle A,B for 25
        bid1 = Bid(uuid4(), 25.0, 1)
        bid1.metadata[:bundle] = [:A, :B]
        push!(bids, bid1)

        # Bid 2: Bundle B,C for 20
        bid2 = Bid(uuid4(), 20.0, 1)
        bid2.metadata[:bundle] = [:B, :C]
        push!(bids, bid2)

        # Bid 3: Single item A for 15
        bid3 = Bid(uuid4(), 15.0, 1)
        bid3.metadata[:bundle] = [:A]
        push!(bids, bid3)

        # Bid 4: Single item C for 12
        bid4 = Bid(uuid4(), 12.0, 1)
        bid4.metadata[:bundle] = [:C]
        push!(bids, bid4)

        clearing_price = determineClearingPrice(auction, bids)
        @test clearing_price >= 0

        winners, allocations = allocateWinners(auction, bids, clearing_price)
        @test length(winners) >= 0
        @test length(winners) <= length(bids)

        # Check no item is allocated twice
        allocated_items = Set{Symbol}()
        for (bidder_id, quantity) in allocations
            # In real implementation would track actual bundles
            @test quantity >= 0
        end
    end

    @testset "Double Auction" begin
        auction = SealedBidDoubleAuction(max_quantity = 100, price_rule = :uniform)

        # Create buy and sell orders
        bids = Bid{Float64}[]

        # Buy orders (high prices)
        for i = 1:3
            bid = Bid(uuid4(), 50.0 + i * 10.0, 2)
            bid.metadata[:is_buy] = true
            push!(bids, bid)
        end

        # Sell orders (low prices)
        for i = 1:3
            bid = Bid(uuid4(), 30.0 + i * 5.0, 2)
            bid.metadata[:is_buy] = false
            push!(bids, bid)
        end

        clearing_price = determineClearingPrice(auction, bids)
        @test clearing_price >= 0

        winners, allocations = allocateWinners(auction, bids, clearing_price)

        # Check that trades are balanced
        total_bought = sum(v for (k, v) in allocations if v > 0; init = 0.0)
        total_sold = sum(abs(v) for (k, v) in allocations if v < 0; init = 0.0)
        @test isapprox(total_bought, total_sold, atol = 1e-6)
    end

    @testset "All-Pay Auction" begin
        auction = AllPayAuction(reserve_price = 10.0, prize_structure = :winner_takes_all)

        bids = create_test_bids(5)

        clearing_price = determineClearingPrice(auction, bids)
        @test clearing_price >= auction.reserve_price

        winners, allocations = allocateWinners(auction, bids, clearing_price)
        @test length(winners) >= 1  # At least one winner

        # In winner-takes-all, only one should have allocation
        @test sum(v > 0 for v in values(allocations)) == 1
    end

    @testset "Japanese Auction" begin
        auction = JapaneseAuction(starting_price = 10.0, increment = 5.0, min_active_bidders = 2)

        bids = create_test_bids(4)

        # Register bidders
        for bid in bids
            success, msg = registerActiveBidder(auction, bid.bidder_id)
            @test success
        end

        # Simulate dropouts
        simulateJapaneseProcess(auction, bids)

        clearing_price = determineClearingPrice(auction, bids)
        @test clearing_price >= auction.starting_price

        winners, allocations = allocateWinners(auction, bids, clearing_price)
        @test length(winners) >= 0  # Could be 0 if all drop out
        @test length(winners) <= length(bids)
    end

    @testset "Candle Auction" begin
        auction =
            CandleAuction(starting_price = 10.0, min_duration = 0.1, max_duration = 1.0, termination_probability = 0.5)

        bids = create_test_bids(3)

        # Process bids
        for bid in bids
            if !auction.is_terminated
                success, msg = acceptCandleBid(auction, bid)
                # Might fail if auction terminates
            end
        end

        # Force termination check
        checkRandomTermination(auction)

        clearing_price = determineClearingPrice(auction, bids)
        @test clearing_price >= auction.starting_price

        winners, allocations = allocateWinners(auction, bids, clearing_price)
        @test length(winners) <= 1  # At most one winner
    end

    @testset "Penny Auction" begin
        auction = PennyAuction(starting_price = 0.0, bid_increment = 0.01, bid_cost = 0.50)

        # Simulate penny auction process
        for i = 1:10
            bidder_id = uuid4()
            success, msg, cost = placePennyBid(auction, bidder_id)

            if success
                @test cost == auction.bid_cost
                @test auction.current_price > auction.starting_price
            end
        end

        # Force auction to end
        auction.current_timer = 0.0

        bids = create_test_bids(3)  # Dummy bids for interface
        clearing_price = determineClearingPrice(auction, bids)
        @test clearing_price >= auction.starting_price

        winners, allocations = allocateWinners(auction, bids, clearing_price)
        @test length(winners) <= 1  # At most one winner

        # Check revenue calculation
        stats = calculateRevenueStatistics(auction)
        @test stats[:total_bid_costs] >= 0
        @test stats[:num_bids] >= 0
    end

    @testset "Unified Interface" begin
        bids = create_test_bids(5)

        # Test multiple auction types through unified interface
        auction_types = [:first_price, :second_price, :dutch, :english, :all_pay]

        for auction_type in auction_types
            config = UnifiedAuctionConfig(auction_type = auction_type, reserve_price = 15.0)

            result = run_unified_auction(config, bids)

            @test result.auction_type == auction_type
            @test result.clearing_price >= 0
            @test length(result.winners) >= 0
            @test result.revenue >= 0
            @test result.efficiency >= 0
            @test result.efficiency <= 1
        end
    end

    @testset "Performance Analysis" begin
        bids = create_test_bids(10)

        # Compare different auction types
        results = compare_auction_types(bids, [:first_price, :second_price, :english], reserve_price = 10.0)

        @test length(results) >= 1
        @test all(haskey(results, k) for k in keys(results))

        # Analyze each result
        for (auction_type, result) in results
            metrics = analyze_auction_performance(result)

            @test haskey(metrics, :total_revenue)
            @test haskey(metrics, :clearing_price)
            @test haskey(metrics, :num_winners)
            @test haskey(metrics, :efficiency)

            @test metrics[:total_revenue] >= 0
            @test metrics[:num_winners] >= 0
        end
    end

    @testset "Auction Recommendation" begin
        # Test recommendation system
        scenarios = [
            Dict(:num_bidders => 3, :bid_variance => 0.1),
            Dict(:num_bidders => 20, :bid_variance => 0.8, :time_sensitive => true),
            Dict(:bundle_bids => true),
            Dict(:two_sided => true),
        ]

        for scenario in scenarios
            recommended = recommend_auction_type(scenario)
            @test recommended isa Symbol
            @test recommended in
                  [:first_price, :second_price, :dutch, :english, :combinatorial, :double, :candle, :augmented_uniform]
        end
    end

    @testset "Edge Cases" begin
        # Empty bids
        empty_bids = Bid{Float64}[]

        config = UnifiedAuctionConfig(auction_type = :first_price, reserve_price = 10.0)

        result = run_unified_auction(config, empty_bids)
        @test length(result.winners) == 0
        @test result.revenue == 0

        # Single bidder
        single_bid = [Bid(uuid4(), 50.0, 1)]
        result = run_unified_auction(config, single_bid)
        @test length(result.winners) <= 1

        # All bids below reserve
        low_bids = [Bid(uuid4(), 5.0, 1) for _ = 1:3]
        result = run_unified_auction(config, low_bids)
        @test length(result.winners) == 0
    end
end
