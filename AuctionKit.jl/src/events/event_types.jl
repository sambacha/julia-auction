# Event types for the event sourcing system
# Following A/HC/LC naming pattern

abstract type AuctionEvent end

# ============================================
# Core Event Types
# ============================================

struct BidSubmittedEvent <: AuctionEvent
    id::UUID
    auction_id::UUID
    bidder_id::UUID
    amount::Float64
    quantity::Int
    timestamp::DateTime
    metadata::Dict{Symbol, Any}
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

struct BidRejectedEvent <: AuctionEvent
    id::UUID
    auction_id::UUID
    bidder_id::UUID
    reason::String
    timestamp::DateTime
end

struct AuctionCancelledEvent <: AuctionEvent
    id::UUID
    auction_id::UUID
    reason::String
    timestamp::DateTime
end

# ============================================
# Workflow Events
# ============================================

struct WorkflowStartedEvent <: AuctionEvent
    id::UUID
    workflow_id::UUID
    workflow_type::Symbol
    timestamp::DateTime
    metadata::Dict{Symbol, Any}
end

struct WorkflowCompletedEvent <: AuctionEvent
    id::UUID
    workflow_id::UUID
    successful_auctions::Vector{UUID}
    failed_auctions::Vector{UUID}
    timestamp::DateTime
end

struct ChainLinkExecutedEvent <: AuctionEvent
    id::UUID
    workflow_id::UUID
    source_auction::UUID
    target_auction::UUID
    propagated_data::Dict{Symbol, Any}
    timestamp::DateTime
end

# ============================================
# Immutable Event Structure
# ============================================

struct ImmutableEvent
    id::UUID
    auction_id::UUID
    event_type::Symbol
    payload::String  # JSON serialized event data
    hash::String
    previous_hash::String
    timestamp::DateTime
    
    function ImmutableEvent(auction_id::UUID, event::AuctionEvent, previous_hash::String)
        id = uuid4()
        event_type = Symbol(typeof(event))
        payload = JSON3.write(event)
        timestamp = now()
        
        # Create hash chain
        content = string(id, auction_id, event_type, payload, previous_hash, timestamp)
        hash = bytes2hex(sha256(content))
        
        new(id, auction_id, event_type, payload, hash, previous_hash, timestamp)
    end
end