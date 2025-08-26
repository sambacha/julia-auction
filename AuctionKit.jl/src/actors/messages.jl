# Message types for actor communication
# Following A/HC/LC naming pattern

"""
    BidMessage

Message for bid submission to an auction actor.
"""
struct BidMessage <: ActorMessage
    bidder_id::UUID
    auction_id::UUID
    amount::Float64
    quantity::Int
    metadata::Dict{Symbol, Any}
    timestamp::DateTime
end

"""
    FinalizeMessage

Message to trigger auction finalization.
"""
struct FinalizeMessage <: ActorMessage
    force::Bool
    timestamp::DateTime
end

"""
    QueryMessage

Message to query auction state.
"""
struct QueryMessage <: ActorMessage
    query_type::Symbol
    parameters::Dict{Symbol, Any}
    response_channel::Channel{Any}
end

"""
    UpdateConfigMessage

Message to update auction configuration.
"""
struct UpdateConfigMessage <: ActorMessage
    updates::Dict{Symbol, Any}
    timestamp::DateTime
end

"""
    StateSnapshotMessage

Message to request a state snapshot.
"""
struct StateSnapshotMessage <: ActorMessage
    include_bids::Bool
    include_metadata::Bool
    response_channel::Channel{Any}
end

"""
    BidResponse

Response to a bid submission.
"""
struct BidResponse
    success::Bool
    bid_id::UUID
    message::String
    timestamp::DateTime
end