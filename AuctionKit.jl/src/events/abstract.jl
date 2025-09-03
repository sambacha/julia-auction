# Abstract types for events
# Following A/HC/LC naming pattern

"""
    AuctionEvent

Abstract type for all auction events.
"""
abstract type AuctionEvent end

"""
    ImmutableEvent

Wrapper for immutable event storage with metadata.
"""
struct ImmutableEvent
    id::UUID
    auction_id::UUID
    timestamp::DateTime
    event_hash::Vector{UInt8}
    previous_hash::Vector{UInt8}
    wrapped_event::AuctionEvent
    
    function ImmutableEvent(
        auction_id::UUID,
        event::AuctionEvent,
        previous_hash::Vector{UInt8} = UInt8[]
    )
        id = uuid4()
        timestamp = now()
        
        # Create hash of event content
        event_data = string(auction_id, timestamp, event)
        event_hash = sha256(event_data * string(previous_hash))
        
        new(id, auction_id, timestamp, event_hash, previous_hash, event)
    end
end

# Event types

struct BidSubmittedEvent <: AuctionEvent
    id::UUID
    auction_id::UUID
    bidder_id::UUID
    amount::Float64
    quantity::Int
    timestamp::DateTime
    metadata::Dict{Symbol, Any}
end

struct BidRejectedEvent <: AuctionEvent
    id::UUID
    auction_id::UUID
    bidder_id::UUID
    reason::String
    timestamp::DateTime
end

struct AuctionStartedEvent <: AuctionEvent
    id::UUID
    auction_id::UUID
    auction_type::Symbol
    start_time::DateTime
    end_time::DateTime
    parameters::Dict{Symbol, Any}
end

struct AuctionFinalizedEvent <: AuctionEvent
    id::UUID
    auction_id::UUID
    clearing_price::Float64
    winners::Vector{UUID}
    allocations::Dict{UUID, Float64}
    payments::Dict{UUID, Float64}
    timestamp::DateTime
end

struct AuctionCancelledEvent <: AuctionEvent
    id::UUID
    auction_id::UUID
    reason::String
    timestamp::DateTime
end