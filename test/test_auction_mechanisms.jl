#!/usr/bin/env julia

# Comprehensive test suite for auction mechanisms
using Pkg
Pkg.activate(".")

using Test
using Dates
using Random
using Statistics
using UUIDs

# Include auction modules
include("src/auctions.jl")
include("src/AuctionSimulator.jl")
include("src/AugmentedUniformPriceAuction.jl")

println("=" * 60)
println("AUCTION MECHANISM TEST SUITE")
println("=" * 60)

# Test data structures for statistics
@testset "Statistics Types" begin
    println("\n📊 Testing Statistics Types...")

    # Test NumericStat
    ns = NumericStat(42.0)
    @test ns.value == 42.0

    ns_int = NumericStat(42)
    @test ns_int.value == 42

    # Test StringStat
    ss = StringStat("test")
    @test ss.value == "test"

    # Test BoolStat
    bs = BoolStat(true)
    @test bs.value == true

    # Test VectorStat
    vs = VectorStat([1.0, 2.0, 3.0])
    @test vs.value == [1.0, 2.0, 3.0]

    # Test DateTimeStat
    dt = now()
    ds = DateTimeStat(dt)
    @test ds.value == dt

    # Test NullStat
    ns = NullStat()
    @test isa(ns, StatisticsValue)

    println("✅ Statistics types working correctly")
end

# Helper function to create test bidders
function create_test_bidders(n::Int, base_value::Float64 = 100.0)
    bidders = []
    for i = 1:n
        value = base_value + randn() * 20  # Add some randomness
        push!(bidders, Bidder(i, max(0.0, value), TruthfulStrategy()))
    end
    return bidders
end

@testset "First-Price Auction" begin
    println("\n🥇 Testing First-Price Auction...")

    # Create auction with reserve price
    auction = FirstPriceAuction(50.0)  # reserve price = 50

    # Create bidders
    bidders = [
        Bidder(1, 100.0, TruthfulStrategy()),
        Bidder(2, 80.0, TruthfulStrategy()),
        Bidder(3, 60.0, TruthfulStrategy()),
        Bidder(4, 40.0, TruthfulStrategy()),  # Below reserve
    ]

    # Run auction
    result = run_auction(auction, bidders)

    @test result.winner == 1
    @test result.winning_bid == 100.0
    @test result.payment == 100.0  # First price
    @test result.revenue == 100.0
    @test length(result.all_bids) == 4

    # Test with shading strategy
    bidders_shade = [
        Bidder(1, 100.0, ShadeStrategy(0.1)),  # Bids 90
        Bidder(2, 80.0, ShadeStrategy(0.2)),    # Bids 64
    ]

    result_shade = run_auction(auction, bidders_shade)
    @test result_shade.winner == 1
    @test result_shade.winning_bid == 90.0
    @test result_shade.payment == 90.0

    println("✅ First-price auction working correctly")
end

@testset "Second-Price (Vickrey) Auction" begin
    println("\n🥈 Testing Second-Price Auction...")

    auction = SecondPriceAuction(50.0)

    bidders =
        [Bidder(1, 100.0, TruthfulStrategy()), Bidder(2, 80.0, TruthfulStrategy()), Bidder(3, 60.0, TruthfulStrategy())]

    result = run_auction(auction, bidders)

    @test result.winner == 1
    @test result.winning_bid == 100.0
    @test result.payment == 80.0  # Second price
    @test result.revenue == 80.0

    # Test incentive compatibility
    bidders_mixed = [
        Bidder(1, 100.0, TruthfulStrategy()),
        Bidder(2, 80.0, ShadeStrategy(0.2)),  # Shouldn't matter
    ]

    result_mixed = run_auction(auction, bidders_mixed)
    @test result_mixed.winner == 1
    @test result_mixed.payment <= 80.0  # Payment should be second bid

    println("✅ Second-price auction working correctly")
end

@testset "Dutch Auction" begin
    println("\n🇳🇱 Testing Dutch Auction...")

    # Dutch auction starts high and decreases
    auction = DutchAuction(100.0, 30.0, 5.0)  # start=100, reserve=30, decrement=5

    bidders =
        [Bidder(1, 75.0, TruthfulStrategy()), Bidder(2, 65.0, TruthfulStrategy()), Bidder(3, 55.0, TruthfulStrategy())]

    result = run_auction(auction, bidders)

    # First bidder willing to pay current price wins
    @test result.winner == 1
    @test result.payment == 75.0  # Pays their bid
    @test result.revenue == 75.0

    println("✅ Dutch auction working correctly")
end

@testset "English Auction" begin
    println("\n🏴󐁧󐁢󐁥󐁮󐁧󐁿 Testing English Auction...")

    # English auction starts low and increases
    auction = EnglishAuction(10.0, 5.0)  # reserve=10, increment=5

    bidders =
        [Bidder(1, 50.0, TruthfulStrategy()), Bidder(2, 45.0, TruthfulStrategy()), Bidder(3, 30.0, TruthfulStrategy())]

    result = run_auction(auction, bidders)

    @test result.winner == 1
    # Should pay just above second highest
    @test result.payment >= 45.0
    @test result.payment <= 50.0

    println("✅ English auction working correctly")
end

@testset "Multi-Unit Auction" begin
    println("\n📦 Testing Multi-Unit Auction...")

    # Auction with 3 units available
    auction = MultiUnitAuction(3, 20.0)  # 3 units, reserve=20

    bidders = [
        Bidder(1, 100.0, TruthfulStrategy()),
        Bidder(2, 80.0, TruthfulStrategy()),
        Bidder(3, 60.0, TruthfulStrategy()),
        Bidder(4, 40.0, TruthfulStrategy()),
        Bidder(5, 30.0, TruthfulStrategy()),
        Bidder(6, 10.0, TruthfulStrategy()),  # Below reserve
    ]

    result = run_auction(auction, bidders)

    # Top 3 bidders above reserve should win
    @test length(result.allocations) == 3
    @test 1 in keys(result.allocations)
    @test 2 in keys(result.allocations)
    @test 3 in keys(result.allocations)
    @test !(6 in keys(result.allocations))  # Below reserve

    # Check payments
    @test result.payments[1] > 0
    @test result.payments[2] > 0
    @test result.payments[3] > 0

    println("✅ Multi-unit auction working correctly")
end

@testset "Augmented Uniform Price Auction" begin
    println("\n🔄 Testing Augmented Uniform Price Auction...")

    # Create augmented auction with elastic supply
    params =
        AugmentedAuctionParams(base_supply = 100.0, reserve_price = 10.0, elasticity = 0.5, max_supply_multiplier = 2.0)

    auction = AugmentedUniformPriceAuction(params)

    # Create bids with different prices
    bids = [
        AugmentedBid(uuid4(), 1, 50.0, 30.0, now()),  # High price, high quantity
        AugmentedBid(uuid4(), 2, 40.0, 25.0, now()),
        AugmentedBid(uuid4(), 3, 30.0, 20.0, now()),
        AugmentedBid(uuid4(), 4, 20.0, 35.0, now()),
        AugmentedBid(uuid4(), 5, 15.0, 40.0, now()),
        AugmentedBid(uuid4(), 6, 8.0, 10.0, now()),   # Below reserve
    ]

    result = run_augmented_auction(auction, bids)

    # Check clearing price is reasonable
    @test result.clearing_price >= params.reserve_price
    @test result.clearing_price <= 50.0

    # Check allocations
    @test length(result.allocations) > 0
    @test sum(values(result.allocations)) <= result.final_supply

    # Higher bidders should get allocations
    if 1 in keys(result.allocations)
        @test result.allocations[1] > 0
    end

    # Below reserve should not get allocation
    @test !(6 in keys(result.allocations))

    # Test supply elasticity
    @test result.final_supply >= params.base_supply
    @test result.final_supply <= params.base_supply * params.max_supply_multiplier

    println("✅ Augmented uniform price auction working correctly")
    println("  - Clearing price: \$$(round(result.clearing_price, digits=2))")
    println("  - Final supply: $(round(result.final_supply, digits=2))")
    println("  - Total allocated: $(round(sum(values(result.allocations)), digits=2))")
end

@testset "Bidding Strategies" begin
    println("\n🎯 Testing Bidding Strategies...")

    # Test different strategies
    valuation = 100.0

    truthful = TruthfulStrategy()
    @test determine_bid(truthful, valuation) == valuation

    shade = ShadeStrategy(0.1)
    @test determine_bid(shade, valuation) == 90.0

    aggressive = AggressiveStrategy(1.2)
    @test determine_bid(aggressive, valuation) == 120.0

    random_strat = RandomStrategy(0.8, 1.1)
    bid = determine_bid(random_strat, valuation)
    @test bid >= 80.0
    @test bid <= 110.0

    println("✅ Bidding strategies working correctly")
end

@testset "Auction Statistics" begin
    println("\n📈 Testing Auction Statistics...")

    auction = FirstPriceAuction(10.0)
    bidders = create_test_bidders(10)

    result = run_auction(auction, bidders)
    stats = calculate_statistics(auction, result, bidders)

    # Check that statistics are calculated
    @test haskey(stats, "num_participants")
    @test haskey(stats, "num_bids")
    @test haskey(stats, "winning_bid")
    @test haskey(stats, "revenue")
    @test haskey(stats, "efficiency")

    @test stats["num_participants"] isa StatisticsValue
    @test stats["num_bids"] isa StatisticsValue

    println("✅ Auction statistics working correctly")
end

@testset "Edge Cases" begin
    println("\n⚠️  Testing Edge Cases...")

    # No bidders
    auction = FirstPriceAuction(50.0)
    result = run_auction(auction, Bidder[])
    @test result.winner == 0
    @test result.revenue == 0.0

    # All bids below reserve
    bidders = [Bidder(1, 30.0, TruthfulStrategy()), Bidder(2, 20.0, TruthfulStrategy())]
    result = run_auction(auction, bidders)
    @test result.winner == 0
    @test result.revenue == 0.0

    # Tie breaking
    auction_tie = FirstPriceAuction(10.0, tie_breaking = :random)
    bidders_tie =
        [Bidder(1, 50.0, TruthfulStrategy()), Bidder(2, 50.0, TruthfulStrategy()), Bidder(3, 50.0, TruthfulStrategy())]

    # Run multiple times to test randomness
    winners = Set{Int}()
    for _ = 1:10
        result = run_auction(auction_tie, bidders_tie)
        push!(winners, result.winner)
    end

    # Should have different winners due to random tie breaking
    @test length(winners) > 1

    println("✅ Edge cases handled correctly")
end

# Summary
println("\n" * "=" * 60)
println("✅ ALL AUCTION MECHANISM TESTS PASSED!")
println("=" * 60)

println("\nAuction types tested:")
println("  ✓ First-Price Auction")
println("  ✓ Second-Price (Vickrey) Auction")
println("  ✓ Dutch Auction")
println("  ✓ English Auction")
println("  ✓ Multi-Unit Auction")
println("  ✓ Augmented Uniform Price Auction")
println("  ✓ Various Bidding Strategies")
println("  ✓ Edge Cases and Tie Breaking")
