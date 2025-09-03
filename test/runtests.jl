using AuctionSimulator
using Dates
using Random
using Statistics
using Test

# Import the necessary types from AuctionSimulator
using AuctionSimulator: StatisticsDict, NumericStat
# Set random seed for reproducible tests
Random.seed!(42)

@testset "AuctionSimulator.jl Tests" begin
    @testset "Core Types" begin
        @testset "Bidder Construction" begin
            # Test basic bidder construction
            strategy = TruthfulBidder(100.0)
            bidder = Bidder(1, 100.0, strategy)

            @test bidder.id == 1
            @test bidder.valuation == 100.0
            @test bidder.strategy == strategy

            # Test invalid bidder construction
            @test_throws ArgumentError Bidder(0, 100.0, strategy)  # Invalid ID
            @test_throws ArgumentError Bidder(1, -50.0, strategy)  # Negative valuation
        end

        @testset "Bid Construction" begin
            # Test basic bid construction
            bid = Bid(1, 50.0, 0.0)
            @test bid.bidder_id == 1
            @test bid.value == 50.0
            @test bid.timestamp == 0.0

            # Test convenience constructor
            bid2 = Bid(2, 75.0)
            @test bid2.bidder_id == 2
            @test bid2.value == 75.0

            # Test invalid bid construction
            @test_throws ArgumentError Bid(0, 50.0, 0.0)  # Invalid bidder ID
            @test_throws ArgumentError Bid(1, -10.0, 0.0) # Negative value
            @test_throws ArgumentError Bid(1, 50.0, -1.0) # Negative timestamp
        end

        @testset "AuctionResult Construction" begin
            auction = FirstPriceAuction()
            bids = [Bid(1, 50.0), Bid(2, 75.0)]
            # Use StatisticsDict with proper StatisticsValue types
            stats = StatisticsDict("revenue" => NumericStat(75.0), "efficiency" => NumericStat(0.9))

            result = AuctionResult(auction, 2, 75.0, bids, stats)

            @test result.winner_id == 2
            @test result.winning_price == 75.0
            @test result.all_bids == bids
            @test result.statistics == stats

            # Test no winner case
            result_no_winner = AuctionResult(auction, nothing, 0.0, Bid[], StatisticsDict())
            @test result_no_winner.winner_id === nothing
        end
    end

    @testset "Bidding Strategies" begin
        @testset "TruthfulBidder" begin
            strategy = TruthfulBidder(100.0)
            auction = FirstPriceAuction()

            bid_amount = generate_bid(strategy, auction)
            @test bid_amount == 100.0

            # Test invalid construction
            @test_throws ArgumentError TruthfulBidder(-50.0)
        end

        @testset "ShadedBidder" begin
            strategy = ShadedBidder(100.0, 0.1)
            auction = FirstPriceAuction()

            bid_amount = generate_bid(strategy, auction)
            @test bid_amount == 90.0  # 100 * (1 - 0.1)

            # Test invalid construction
            @test_throws ArgumentError ShadedBidder(-50.0, 0.1)
            @test_throws ArgumentError ShadedBidder(100.0, -0.1)
            @test_throws ArgumentError ShadedBidder(100.0, 1.5)
        end

        @testset "RandomBidder" begin
            base_strategy = TruthfulBidder(100.0)
            random_strategy = RandomBidder(base_strategy, 5.0)
            auction = FirstPriceAuction()

            # Test multiple bids to ensure randomness
            bids = [generate_bid(random_strategy, auction) for _ = 1:10]
            @test length(unique(bids)) > 1  # Should have different values
            @test all(b >= 0 for b in bids)  # All bids should be non-negative

            # Test invalid construction
            @test_throws ArgumentError RandomBidder(base_strategy, -5.0)
        end

        @testset "StrategicBidder" begin
            strategy = StrategicBidder(100.0, 5)
            first_price_auction = FirstPriceAuction()
            second_price_auction = SecondPriceAuction()

            # First-price auction should shade bid
            fp_bid = generate_bid(strategy, first_price_auction)
            @test fp_bid < 100.0
            @test fp_bid == 80.0  # 100 * (5-1)/5

            # Second-price auction should bid truthfully
            sp_bid = generate_bid(strategy, second_price_auction)
            @test sp_bid == 100.0

            # Test invalid construction
            @test_throws ArgumentError StrategicBidder(-100.0, 5)
            @test_throws ArgumentError StrategicBidder(100.0, 0)
        end
    end

    @testset "Auction Types" begin
        @testset "FirstPriceAuction" begin
            # Test basic construction
            auction = FirstPriceAuction()
            @test auction.reserve_price == 0.0
            @test auction.num_units == 1
            @test auction.tie_breaking == :random

            # Test custom construction
            auction2 = FirstPriceAuction(10.0, 2, :first_come)
            @test auction2.reserve_price == 10.0
            @test auction2.num_units == 2
            @test auction2.tie_breaking == :first_come

            # Test invalid construction
            @test_throws ArgumentError FirstPriceAuction(-5.0)  # Negative reserve
            @test_throws ArgumentError FirstPriceAuction(0.0, 0)  # Zero units
            @test_throws ArgumentError FirstPriceAuction(0.0, 1, :invalid)  # Invalid tie-breaking
        end

        @testset "SecondPriceAuction" begin
            auction = SecondPriceAuction(5.0)
            @test auction.reserve_price == 5.0
            @test auction.num_units == 1
            @test auction.tie_breaking == :random
        end
    end

    @testset "Auction Mechanics" begin
        @testset "Basic Auction Conduct" begin
            # Create test bidders
            bidders = [
                Bidder(1, 100.0, TruthfulBidder(100.0)),
                Bidder(2, 80.0, TruthfulBidder(80.0)),
                Bidder(3, 120.0, TruthfulBidder(120.0)),
            ]

            # Test first-price auction
            auction = FirstPriceAuction()
            result = conduct_auction(auction, bidders)

            @test result.winner_id !== nothing
            @test result.winner_id == 3  # Highest bidder
            @test result.winning_price == 120.0  # Pays own bid
            @test length(result.all_bids) == 3

            # Test second-price auction
            auction2 = SecondPriceAuction()
            result2 = conduct_auction(auction2, bidders)

            @test result2.winner_id !== nothing
            @test result2.winner_id == 3  # Highest bidder
            @test result2.winning_price == 100.0  # Pays second-highest bid
        end

        @testset "Reserve Price Handling" begin
            bidders = [Bidder(1, 50.0, TruthfulBidder(50.0)), Bidder(2, 30.0, TruthfulBidder(30.0))]

            # Test with reserve price higher than all bids
            auction = FirstPriceAuction(60.0)
            result = conduct_auction(auction, bidders)

            @test result.winner_id === nothing
            @test result.winning_price == 0.0
        end

        @testset "Tie Breaking" begin
            # Create bidders with same valuation
            bidders = [
                Bidder(1, 100.0, TruthfulBidder(100.0)),
                Bidder(2, 100.0, TruthfulBidder(100.0)),
                Bidder(3, 100.0, TruthfulBidder(100.0)),
            ]

            # Test random tie breaking (should work without error)
            auction = FirstPriceAuction(0.0, 1, :random)
            result = conduct_auction(auction, bidders)
            @test result.winner_id !== nothing
            @test result.winner_id in [1, 2, 3]

            # Test highest ID tie breaking
            auction2 = FirstPriceAuction(0.0, 1, :highest_id)
            result2 = conduct_auction(auction2, bidders)
            @test result2.winner_id == 3  # Highest ID
        end

        @testset "Empty Auction" begin
            # Test auction with no bidders
            auction = FirstPriceAuction()
            result = conduct_auction(auction, Bidder[])

            @test result.winner_id === nothing
            @test length(result.all_bids) == 0
        end
    end

    @testset "Utility Functions" begin
        @testset "Bid Sorting" begin
            bids = [Bid(1, 50.0, 1.0), Bid(2, 100.0, 2.0), Bid(3, 75.0, 3.0)]

            sorted_bids = sort_bids(bids)
            @test sorted_bids[1].value == 50.0
            @test sorted_bids[2].value == 75.0
            @test sorted_bids[3].value == 100.0

            # Test reverse sorting
            sorted_bids_rev = sort_bids(bids, reverse = true)
            @test sorted_bids_rev[1].value == 100.0
            @test sorted_bids_rev[2].value == 75.0
            @test sorted_bids_rev[3].value == 50.0
        end

        @testset "Highest and Second Highest Bids" begin
            bids = [Bid(1, 50.0, 1.0), Bid(2, 100.0, 2.0), Bid(3, 75.0, 3.0)]

            highest = highest_bid(bids)
            @test highest.value == 100.0
            @test highest.bidder_id == 2

            second_highest = second_highest_bid(bids)
            @test second_highest.value == 75.0
            @test second_highest.bidder_id == 3

            # Test edge cases
            @test highest_bid(Bid[]) === nothing
            @test second_highest_bid([Bid(1, 50.0)]) === nothing
        end
    end

    @testset "Simulation Engine" begin
        @testset "AuctionConfig" begin
            # Test default configuration
            config = AuctionConfig()
            @test config.num_rounds == 1000
            @test config.min_value == 1.0
            @test config.max_value == 100.0
            @test config.reserve_price == 0.0
            @test config.seed === nothing
            @test config.parallel == false

            # Test custom configuration
            custom_config = AuctionConfig(
                num_rounds = 100,
                min_value = 10.0,
                max_value = 50.0,
                reserve_price = 5.0,
                seed = 42,
                parallel = true,
            )
            @test custom_config.num_rounds == 100
            @test custom_config.min_value == 10.0
            @test custom_config.seed == 42

            # Test invalid configurations
            @test_throws AssertionError AuctionConfig(num_rounds = 0)
            @test_throws AssertionError AuctionConfig(min_value = -10.0)
            @test_throws AssertionError AuctionConfig(max_value = 10.0, min_value = 20.0)
        end

        @testset "Simulation Execution" begin
            bidders = [
                Bidder(1, 100.0, TruthfulBidder(100.0)),
                Bidder(2, 80.0, TruthfulBidder(80.0)),
                Bidder(3, 120.0, TruthfulBidder(120.0)),
            ]

            config = AuctionConfig(num_rounds = 10, seed = 42)

            # Test first-price simulation
            result = run_simulation(FirstPriceAuction(), bidders, config)
            @test result.auction_type == "FirstPriceAuction"
            @test length(result.revenues) == 10
            @test length(result.efficiencies) == 10
            @test length(result.winning_bids) == 10
            @test result.total_time >= 0.0

            # Test second-price simulation
            result2 = run_simulation(SecondPriceAuction(), bidders, config)
            @test result2.auction_type == "SecondPriceAuction"
            @test length(result2.revenues) == 10
        end
    end

    @testset "Efficiency Calculations" begin
        @testset "Perfect Efficiency" begin
            # Test case where highest valuation bidder wins
            bidders = [
                Bidder(1, 100.0, TruthfulBidder(100.0)),
                Bidder(2, 80.0, TruthfulBidder(80.0)),
                Bidder(3, 120.0, TruthfulBidder(120.0)),
            ]

            auction = FirstPriceAuction()
            result = conduct_auction(auction, bidders)

            @test result.statistics["efficiency"].value == 1.0
        end

        @testset "Imperfect Efficiency" begin
            # Test case where shaded bidding might lead to inefficiency
            bidders = [
                Bidder(1, 100.0, ShadedBidder(100.0, 0.5)),  # Bids 50
                Bidder(2, 80.0, TruthfulBidder(80.0)),        # Bids 80
                Bidder(3, 120.0, ShadedBidder(120.0, 0.4)),    # Bids 72
            ]

            auction = FirstPriceAuction()
            result = conduct_auction(auction, bidders)

            # Bidder 2 should win (highest bid of 80), but bidder 3 has highest valuation
            @test result.winner_id == 2
            @test result.statistics["efficiency"].value < 1.0
        end
    end

    @testset "Edge Cases and Error Handling" begin
        @testset "Bid Validation" begin
            valid_bids = [Bid(1, 50.0), Bid(2, 75.0)]

            auction = FirstPriceAuction()
            @test validate_bids(valid_bids, auction) == true

            # Test that invalid bids are caught during construction
            @test_throws ArgumentError Bid(0, 75.0)  # Invalid bidder ID
        end

        @testset "Malformed Auctions" begin
            # Test auction with valid bidders
            bidders = [Bidder(1, 100.0, TruthfulBidder(100.0)), Bidder(2, 80.0, TruthfulBidder(80.0))]

            auction = FirstPriceAuction()

            # This should work without error
            @test_nowarn conduct_auction(auction, bidders)
        end
    end

    @testset "Performance and Memory" begin
        @testset "Type Stability" begin
            bidders = [Bidder(1, 100.0, TruthfulBidder(100.0)), Bidder(2, 80.0, TruthfulBidder(80.0))]

            auction = FirstPriceAuction()

            # Test that conduct_auction is type-stable
            @test @inferred(conduct_auction(auction, bidders)) isa AuctionResult
        end

        @testset "Memory Efficiency" begin
            # Test that we're not allocating excessive memory
            bidders = [Bidder(i, 50.0 + rand() * 50.0, TruthfulBidder(50.0 + rand() * 50.0)) for i = 1:100]

            auction = FirstPriceAuction()

            # This should complete without excessive memory allocation
            memory_used = @allocated conduct_auction(auction, bidders)
            @test memory_used < 1_000_000  # Less than 1MB
        end
    end
end
