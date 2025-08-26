# Message types for actor communication
# Following A/HC/LC naming pattern

# ============================================
# Actor Messages
# ============================================

struct BidMessage <: ActorMessage
    bidder_id::UUID
    amount::Float64
    quantity::Int
    timestamp::DateTime
    metadata::Dict{Symbol, Any}
end

struct FinalizeMessage <: ActorMessage
    force::Bool
    timestamp::DateTime
end

struct QueryMessage <: ActorMessage
    query_type::Symbol
    parameters::Dict{Symbol, Any}
    reply_channel::Channel{Any}
end

struct UpdateConfigMessage <: ActorMessage
    updates::Dict{Symbol, Any}
    timestamp::DateTime
end

struct StateSnapshotMessage <: ActorMessage
    reply_channel::Channel{Any}
end

# ============================================
# Controller Messages
# ============================================

abstract type ControllerMessage end

struct AuctionCompletedMessage <: ControllerMessage
    auction_id::UUID
    result::AuctionResult
    timestamp::DateTime
end

struct StartWorkflowMessage <: ControllerMessage
    workflow_id::UUID
    parameters::Dict{Symbol, Any}
end

struct ChainUpdateMessage <: ControllerMessage
    workflow_id::UUID
    auction_id::UUID
    status::Symbol
    data::Dict{Symbol, Any}
end

struct CancelWorkflowMessage <: ControllerMessage
    workflow_id::UUID
    graceful::Bool
end

# ============================================
# Response Messages
# ============================================

struct BidResponse
    accepted::Bool
    bid_id::UUID
    message::String
    timestamp::DateTime
end

struct QueryResponse{T}
    success::Bool
    data::T
    message::String
end

struct WorkflowHandle
    workflow_id::UUID
    orchestrator_ref::Any  # Reference to orchestrator
end