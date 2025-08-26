# Abstract types for the actor system
# Following A/HC/LC naming pattern: Action + High Context + Low Context

abstract type AbstractActor{T} end
abstract type ActorMessage end
abstract type ActorState{T} end

"""
    AbstractAuction{T}

Base type for all auction mechanisms.
"""
abstract type AbstractAuction{T} end


"""
    AuctionResult{T}

Stores the result of an auction.
"""
struct AuctionResult{T}
    auction_id::UUID
    clearing_price::T
    winners::Vector{UUID}
    allocations::Dict{UUID, T}
    payments::Dict{UUID, T}
    timestamp::DateTime
    metadata::Dict{Symbol, Any}
end

"""
    Bid{T}

Represents a bid in an auction.
"""
struct Bid{T}
    id::UUID
    bidder_id::UUID
    amount::T
    quantity::Int
    timestamp::DateTime
    metadata::Dict{Symbol, Any}
    
    function Bid(bidder_id::UUID, amount::T, quantity::Int=1; 
                 metadata::Dict{Symbol, Any}=Dict{Symbol, Any}()) where T
        new{T}(uuid4(), bidder_id, amount, quantity, now(), metadata)
    end
end

"""
    Bidder{T}

Represents a participant in an auction.
"""
struct Bidder{T}
    id::UUID
    name::String
    budget::T
    valuation::T
    strategy::Symbol
    metadata::Dict{Symbol, Any}
    
    function Bidder(name::String, budget::T, valuation::T; 
                   strategy::Symbol=:truthful,
                   metadata::Dict{Symbol, Any}=Dict{Symbol, Any}()) where T
        new{T}(uuid4(), name, budget, valuation, strategy, metadata)
    end
end