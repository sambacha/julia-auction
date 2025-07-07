# Edge case and boundary condition tests
using Test
using Random

@testset "Edge Cases and Boundary Conditions" begin
    @testset "Extreme Value Tests" begin
        @testset "Very Small Values" begin
            # Test with extremely small valuations
            tiny_bidder = TruthfulBidder(1, 1e-10)
            @test tiny_bidder.valuation == 1e-10
            
            # Test auction with tiny values
            tiny_auction = FirstPriceAuction(reserve_price=1e-12)
            tiny_bids = [Bid(1, 1e-11)]
            result = run_auction(tiny_auction, tiny_bids)
            
            @test result.winner_id == 1
            @test result.price_paid ≈ 1e-11
            @test isfinite(result.seller_revenue)
        end
        
        @testset "Very Large Values" begin
            # Test with extremely large valuations
            huge_bidder = TruthfulBidder(1, 1e10)
            @test huge_bidder.valuation == 1e10
            
            # Test auction with large values
            huge_auction = SecondPriceAuction(reserve_price=1e8)
            huge_bids = [Bid(1, 1e9), Bid(2, 5e8)]
            result = run_auction(huge_auction, huge_bids)
            
            @test result.winner_id == 1
            @test result.price_paid ≈ 5e8
            @test isfinite(result.seller_revenue)
        end
        
        @testset "Zero Values" begin
            # Test with zero valuations and bids
            zero_bidder = TruthfulBidder(1, 0.0)
            zero_bid = generate_bid(zero_bidder, FirstPriceAuction())
            @test zero_bid == 0.0
            
            # Test auction with zero bids
            zero_auction = FirstPriceAuction(reserve_price=0.0)
            zero_bids = [Bid(1, 0.0), Bid(2, 0.0)]
            result = run_auction(zero_auction, zero_bids)
            
            @test result.winner_id > 0  # Someone should win
            @test result.price_paid == 0.0
            @test result.seller_revenue == 0.0
        end
    end
    
    @testset "Degenerate Cases" begin
        @testset "Empty Auctions" begin
            # Test auction with no bids
            empty_auction = FirstPriceAuction(reserve_price=10.0)
            empty_result = run_auction(empty_auction, Bid[])
            
            @test empty_result.winner_id == 0
            @test empty_result.winning_bid == 0.0
            @test empty_result.price_paid == 0.0
            @test empty_result.seller_revenue == 0.0
        end
        
        @testset "Single Bidder Auctions" begin
            # Test first price auction with single bidder
            single_fp_auction = FirstPriceAuction(reserve_price=20.0)
            single_bid = [Bid(1, 50.0)]
            result = run_auction(single_fp_auction, single_bid)
            
            @test result.winner_id == 1
            @test result.winning_bid == 50.0
            @test result.price_paid == 50.0
            
            # Test second price auction with single bidder
            single_sp_auction = SecondPriceAuction(reserve_price=20.0)
            result_sp = run_auction(single_sp_auction, single_bid)
            
            @test result_sp.winner_id == 1
            @test result_sp.winning_bid == 50.0
            @test result_sp.price_paid == 20.0  # Should pay reserve price
        end
        
        @testset "All Bids Below Reserve" begin
            # Test when all bids are below reserve price
            high_reserve_auction = FirstPriceAuction(reserve_price=100.0)
            low_bids = [Bid(1, 30.0), Bid(2, 40.0), Bid(3, 50.0)]
            result = run_auction(high_reserve_auction, low_bids)
            
            @test result.winner_id == 0  # No winner
            @test result.winning_bid == 0.0
            @test result.price_paid == 0.0
            @test result.seller_revenue == 0.0
        end
    end
    
    @testset "Tie Breaking Tests" begin
        @testset "Perfect Ties" begin
            # Test with multiple identical bids
            tie_auction = FirstPriceAuction(reserve_price=10.0)
            tie_bids = [Bid(1, 50.0), Bid(2, 50.0), Bid(3, 50.0)]
            result = run_auction(tie_auction, tie_bids)
            
            @test result.winner_id in [1, 2, 3]  # One of the tied bidders should win
            @test result.winning_bid == 50.0
            @test result.price_paid == 50.0
            
            # Test deterministic tie breaking with seed
            Random.seed!(123)
            result1 = run_auction(tie_auction, tie_bids)
            Random.seed!(123)
            result2 = run_auction(tie_auction, tie_bids)
            @test result1.winner_id == result2.winner_id  # Should be deterministic
        end
        
        @testset "Partial Ties" begin
            # Test with some tied bids and some different
            partial_tie_auction = SecondPriceAuction(reserve_price=5.0)
            partial_tie_bids = [Bid(1, 60.0), Bid(2, 60.0), Bid(3, 45.0)]
            result = run_auction(partial_tie_auction, partial_tie_bids)
            
            @test result.winner_id in [1, 2]  # One of the tied highest bidders
            @test result.winning_bid == 60.0
            @test result.price_paid == 60.0  # Other tied bid
        end
    end
    
    @testset "Numerical Precision Tests" begin
        @testset "Floating Point Precision" begin
            # Test with values that might cause precision issues
            precision_auction = FirstPriceAuction(reserve_price=0.1)
            precision_bids = [
                Bid(1, 0.1 + 1e-15),  # Barely above reserve
                Bid(2, 0.1 + 2e-15),  # Slightly higher
                Bid(3, 0.1 - 1e-15)   # Barely below reserve
            ]
            result = run_auction(precision_auction, precision_bids)
            
            @test result.winner_id == 2  # Highest valid bid
            @test result.price_paid ≈ 0.1 + 2e-15
        end
        
        @testset "Large Number Precision" begin
            # Test with large numbers that might lose precision
            large_auction = SecondPriceAuction(reserve_price=1e15)
            large_bids = [
                Bid(1, 1e15 + 1e10),
                Bid(2, 1e15 + 2e10),
                Bid(3, 1e15 + 5e9)
            ]
            result = run_auction(large_auction, large_bids)
            
            @test result.winner_id == 2
            @test result.price_paid ≈ 1e15 + 1e10
            @test isfinite(result.seller_revenue)
        end
    end
    
    @testset "Boundary Value Tests" begin
        @testset "Reserve Price Boundaries" begin
            # Test bids exactly at reserve price
            boundary_auction = FirstPriceAuction(reserve_price=25.0)
            boundary_bids = [
                Bid(1, 25.0),      # Exactly at reserve
                Bid(2, 25.0001),   # Just above reserve
                Bid(3, 24.9999)    # Just below reserve
            ]
            result = run_auction(boundary_auction, boundary_bids)
            
            @test result.winner_id == 2  # Just above reserve should win
            @test result.price_paid ≈ 25.0001
        end
        
        @testset "Valuation Boundaries" begin
            # Test bidding strategies at valuation boundaries
            boundary_bidder = ShadedBidder(1, 100.0, 0.0)  # No shading
            boundary_bid = generate_bid(boundary_bidder, FirstPriceAuction())
            @test boundary_bid == 100.0  # Should bid exactly at valuation
            
            # Test with maximum shading
            max_shade_bidder = ShadedBidder(2, 100.0, 1.0)  # 100% shading
            max_shade_bid = generate_bid(max_shade_bidder, FirstPriceAuction())
            @test max_shade_bid ≈ 0.0  # Should bid nearly zero
        end
    end
    
    @testset "Concurrent Modification Tests" begin
        @testset "Bid Vector Modifications" begin
            # Test that auction handles bid vector modifications gracefully
            mutable_auction = FirstPriceAuction(reserve_price=10.0)
            mutable_bids = [Bid(1, 50.0), Bid(2, 60.0)]
            
            # Run auction (should not modify input)
            original_length = length(mutable_bids)
            result = run_auction(mutable_auction, mutable_bids)
            
            @test length(mutable_bids) == original_length  # Should not modify input
            @test result.winner_id == 2  # Should still work correctly
        end
    end
    
    @testset "Memory Boundary Tests" begin
        @testset "Large Collections" begin
            # Test with very large numbers of bidders
            large_n = 10000
            large_bidders = [TruthfulBidder(i, rand(10.0:100.0)) for i in 1:large_n]
            large_bids = [Bid(b.id, generate_bid(b, FirstPriceAuction())) for b in large_bidders]
            large_auction = FirstPriceAuction(reserve_price=5.0)
            
            # Should complete without memory issues
            @test_nowarn run_auction(large_auction, large_bids)
            
            result = run_auction(large_auction, large_bids)
            @test result.winner_id > 0
            @test result.seller_revenue > 0
        end
    end
end