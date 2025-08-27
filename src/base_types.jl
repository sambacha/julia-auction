"""
Base types for auction system
"""

# Abstract types
abstract type AbstractAuction end
abstract type AbstractBidder end
abstract type AbstractBiddingStrategy end

# Bid structure
struct Bid
    bidder_id::Int
    amount::Float64
    quantity::Int
    timestamp::DateTime
    
    Bid(bidder_id, amount, quantity=1) = new(bidder_id, amount, quantity, now())
end

# Auction result structure
struct AuctionResult
    auction_type::Symbol
    winner::Int
    winning_bid::Float64
    payment::Float64
    revenue::Float64
    allocations::Dict{Int, Int}
    payments::Dict{Int, Float64}
    all_bids::Vector{Bid}
    timestamp::DateTime
    
    # Constructor for simple single-winner auctions
    AuctionResult(auction_type, winner, winning_bid, payment, all_bids) = new(
        auction_type,
        winner,
        winning_bid,
        payment,
        payment,  # revenue = payment for single item
        Dict(winner => 1),
        Dict(winner => payment),
        all_bids,
        now()
    )
    
    # Constructor for multi-unit auctions
    AuctionResult(auction_type, allocations, payments, all_bids) = new(
        auction_type,
        0,  # No single winner
        0.0,
        0.0,
        sum(values(payments)),  # Total revenue
        allocations,
        payments,
        all_bids,
        now()
    )
end

export AbstractAuction, AbstractBidder, AbstractBiddingStrategy, Bid, AuctionResult