# Message types for actor communication
# Following A/HC/LC naming pattern

# Import MetadataValue and MetadataDict from abstract.jl
using ..Actors: MetadataValue, MetadataDict

# Define response types for channels
const ResponseValue = Union{Bool, Int64, Float64, String, AuctionResult, Vector{Bid}, MetadataDict, Nothing}
const ResponseChannel = Channel{ResponseValue}

"""
    BidMessage

Message for bid submission to an auction actor.
"""
struct BidMessage <: ActorMessage
    bidder_id::UUID
    auction_id::UUID
    amount::Float64
    quantity::Int
    metadata::MetadataDict
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
    parameters::MetadataDict
    response_channel::ResponseChannel
end

"""
    UpdateConfigMessage

Message to update auction configuration.
"""
struct UpdateConfigMessage <: ActorMessage
    updates::MetadataDict
    timestamp::DateTime
end

"""
    StateSnapshotMessage

Message to request a state snapshot.
"""
struct StateSnapshotMessage <: ActorMessage
    include_bids::Bool
    include_metadata::Bool
    response_channel::ResponseChannel
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