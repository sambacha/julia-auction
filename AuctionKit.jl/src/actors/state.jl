# Auction state definition
# Following A/HC/LC naming pattern

"""
    AuctionState{T}

Maintains the state of an auction actor.
"""
mutable struct AuctionState{T} <: ActorState{T}
    auction_id::UUID
    auction_type::Symbol
    status::Symbol  # :pending, :active, :finalizing, :completed, :cancelled
    current_bids::Vector{Bid{T}}
    participants::Dict{UUID, Bidder{T}}
    start_time::DateTime
    end_time::DateTime
    mutex::ReentrantLock
    
    # Auction parameters
    reserve_price::T
    increment::T  # For English/Dutch auctions
    clearing_rule::Symbol  # :first_price, :second_price, :vcg
    tie_breaking::Symbol  # :random, :first_come, :proportional
    max_quantity::Int
    
    # Results (populated after finalization)
    result::Union{Nothing, AuctionResult{T}}
end