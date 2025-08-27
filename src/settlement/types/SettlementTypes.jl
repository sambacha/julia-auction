"""
    SettlementTypes

Type definitions for the CFMM Settlement system.
"""
module SettlementTypes

using Dates
using UUIDs

# Export all types
export Price, Amount, AssetPair, ProtocolType,
       SettlementTransaction, ExecutionPath, SettlementReceipt,
       SettlementResult, SettlementMetrics, RouteSegment,
       LiquidityPool, PoolReserves, MEVRisk, ProtectionStrategy,
       CircuitBreakerState, SettlementStatus

# Type aliases for clarity and flexibility
const Price = Real
const Amount = Real
const AssetPair = Tuple{String, String}

# Protocol enumeration
@enum ProtocolType begin
    UNISWAP_V2
    UNISWAP_V3
    BALANCER
    CURVE
    UNKNOWN
end

"""
    SettlementTransaction{T<:Real}

Represents a transaction to be settled through CFMM pools.
"""
struct SettlementTransaction{T<:Real}
    id::UUID
    asset_pair::AssetPair
    amount::T
    is_buy::Bool
    max_slippage::T
    deadline::DateTime
    sender::String
    receiver::String
    metadata::Dict{Symbol, Any}
    
    function SettlementTransaction{T}(;
        id::UUID = uuid4(),
        asset_pair::AssetPair,
        amount::T,
        is_buy::Bool = true,
        max_slippage::T = T(0.01),
        deadline::DateTime = now() + Minute(5),
        sender::String = "",
        receiver::String = "",
        metadata::Dict{Symbol, Any} = Dict{Symbol, Any}(),
    ) where {T<:Real}
        amount > 0 || throw(ArgumentError("Amount must be positive"))
        0 ≤ max_slippage ≤ 1 || throw(
            ArgumentError("Max slippage must be between 0 and 1")
        )
        deadline > now() || throw(ArgumentError("Deadline must be in the future"))
        
        new(id, asset_pair, amount, is_buy, max_slippage,
            deadline, sender, receiver, metadata)
    end
end

# Convenience constructor
SettlementTransaction(; kwargs...) = SettlementTransaction{Float64}(; kwargs...)

"""
    RouteSegment{T<:Real}

Represents a segment of the execution path through a specific pool.
"""
struct RouteSegment{T<:Real}
    pool_address::String
    protocol::ProtocolType
    amount_in::T
    amount_out::T
    price_impact::T
    gas_estimate::Int
    fee_tier::T
end

"""
    ExecutionPath{T<:Real}

Complete execution path through multiple pools.
"""
struct ExecutionPath{T<:Real}
    segments::Vector{RouteSegment{T}}
    total_amount_in::T
    total_amount_out::T
    total_price_impact::T
    total_gas::Int
    is_optimal::Bool
end

"""
    SettlementReceipt{T<:Real}

Receipt of a completed settlement.
"""
struct SettlementReceipt{T<:Real}
    transaction_hash::String
    block_number::Int
    gas_used::Int
    effective_price::T
    amount_received::T
    protocol_fees::T
    mev_protection_cost::T
    timestamp::DateTime
end

"""
    SettlementMetrics

Performance metrics for a settlement.
"""
struct SettlementMetrics
    routing_latency_ms::Float64
    execution_latency_ms::Float64
    total_latency_ms::Float64
    pools_queried::Int
    routes_evaluated::Int
    cache_hit::Bool
    mev_protection_used::Bool
end

"""
    SettlementResult{T<:Real}

Complete result of a settlement operation.
"""
struct SettlementResult{T<:Real}
    transaction::SettlementTransaction{T}
    receipt::Union{SettlementReceipt{T}, Nothing}
    metrics::SettlementMetrics
    execution_paths::Vector{ExecutionPath{T}}
    timestamp::DateTime
    success::Bool
    error::Union{String, Nothing}
end

"""
    LiquidityPool{T<:Real}

Represents a CFMM liquidity pool.
"""
mutable struct LiquidityPool{T<:Real}
    address::String
    protocol::ProtocolType
    asset_pair::AssetPair
    reserves::PoolReserves{T}
    fee_tier::T
    liquidity::T
    last_update::DateTime
    metadata::Dict{Symbol, Any}
end

"""
    PoolReserves{T<:Real}

Reserves for a liquidity pool.
"""
struct PoolReserves{T<:Real}
    reserve_a::T
    reserve_b::T
    # For Uniswap V3 concentrated liquidity
    tick_lower::Union{Int, Nothing}
    tick_upper::Union{Int, Nothing}
    liquidity_active::Union{T, Nothing}
end

"""
    MEVRisk

Risk assessment for MEV attacks.
"""
struct MEVRisk
    sandwich_risk::Float64
    frontrun_risk::Float64
    backrun_risk::Float64
    total_risk::Float64
    estimated_loss::Float64
    recommended_protection::ProtectionStrategy
end

"""
    ProtectionStrategy

MEV protection strategies.
"""
@enum ProtectionStrategy begin
    NO_PROTECTION
    COMMIT_REVEAL
    FLASHBOTS_PRIVATE
    TIME_DELAY
    ROUTE_SPLITTING
end

"""
    CircuitBreakerState

Circuit breaker states for fault tolerance.
"""
@enum CircuitBreakerState begin
    CLOSED
    OPEN
    HALF_OPEN
end

"""
    SettlementStatus

Status of a settlement operation.
"""
@enum SettlementStatus begin
    PENDING
    ROUTING
    EXECUTING
    CONFIRMING
    COMPLETED
    FAILED
    ROLLED_BACK
end

end # module SettlementTypes