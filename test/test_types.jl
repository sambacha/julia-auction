# Specialized tests for type system components
using Test
@testset "Extended Type System Tests" begin
    @testset "Type Hierarchy Tests" begin
        # Test abstract type hierarchy
        @test AbstractBidder <: Any
        @test AbstractAuction <: Any
        
        # Test concrete type implementations
        @test TruthfulBidder <: AbstractBidder
        @test ShadedBidder <: AbstractBidder
        @test RandomBidder <: AbstractBidder
        @test FirstPriceAuction <: AbstractAuction
        @test SecondPriceAuction <: AbstractAuction
    end
    
    @testset "Type Interface Tests" begin
        # Test that all bidder types implement required interface
        bidder_types = [TruthfulBidder, ShadedBidder, RandomBidder]
        
        for BidderType in bidder_types
            # Test constructor
            if BidderType == ShadedBidder
                bidder = BidderType(1, 100.0, 0.1)
            elseif BidderType == RandomBidder
                bidder = BidderType(1, 100.0, 0.2)
            else
                bidder = BidderType(1, 100.0)
            end
            
            @test hasmethod(generate_bid, (BidderType, AbstractAuction))
            @test bidder.id isa Int
            @test bidder.valuation isa Float64
        end
        
        # Test that all auction types implement required interface
        auction_types = [FirstPriceAuction, SecondPriceAuction]
        
        for AuctionType in auction_types
            auction = AuctionType(reserve_price=10.0)
            @test hasmethod(run_auction, (AuctionType, Vector{Bid}))
            @test auction.reserve_price isa Float64
        end
    end
    
    @testset "Type Stability Tests" begin
        # Test that functions maintain type stability
        bidder = TruthfulBidder(1, 100.0)
        auction = FirstPriceAuction(reserve_price=20.0)
        
        # Test bid generation type stability
        @inferred generate_bid(bidder, auction)
        
        # Test auction result type stability
        bids = [Bid(1, 50.0), Bid(2, 60.0)]
        @inferred run_auction(auction, bids)
    end
    
    @testset "Memory Efficiency Tests" begin
        # Test that types don't allocate excessive memory
        @test sizeof(Bid(1, 50.0)) <= 16  # Should be efficient
        @test sizeof(TruthfulBidder(1, 100.0)) <= 24  # Should be efficient
        
        # Test that large collections are handled efficiently
        large_bid_vector = [Bid(i, float(i)) for i in 1:1000]
        @test length(large_bid_vector) == 1000
        
        # Memory allocation should be reasonable
        alloc_before = @allocated begin
            auction = FirstPriceAuction(reserve_price=10.0)
            result = run_auction(auction, large_bid_vector)
        end
        
        @test alloc_before < 100_000  # Should allocate less than 100KB
    end
end