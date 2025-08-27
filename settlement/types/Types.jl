"""
    Types

Core type definitions for the Settlement system. Provides abstract types,
concrete implementations, and type unions used throughout the system.

# Design Principles
- Immutable by default for thread safety
- Zero-allocation constructors where possible
- Parametric types for performance
- Clear type hierarchies
"""
module Types

using Dates
using UUIDs

# Abstract types
abstract type AbstractSettlement end
abstract type AbstractTransaction end
abstract type AbstractRoute end
abstract type AbstractProtocol end
abstract type AbstractMEVProtection end

# Core settlement types
struct AssetPair{T<:Real}
    base::Symbol
    quote::Symbol
    amount_base::T
    amount_quote::T
end

struct PriceQuote{T<:Real}
    pair::AssetPair{T}
    price::T
    liquidity::T
    timestamp::DateTime
    source::Symbol
end

struct RouteSegment{T<:Real}
    protocol::Symbol
    pool_address::String
    input_asset::Symbol
    output_asset::Symbol
    input_amount::T
    output_amount::T
    fee_rate::T
    gas_estimate::T
end

struct Route{T<:Real}
    segments::Vector{RouteSegment{T}}
    total_output::T
    total_gas::T
    price_impact::T
    is_optimal::Bool
end

struct ExecutionPath{T<:Real}
    routes::Vector{Route{T}}
    total_value::T
    execution_time_estimate::T
    parallelizable::Bool
end

# Transaction types
mutable struct AtomicTransaction{T<:Real} <: AbstractTransaction
    id::UUID
    auction_id::UUID
    created_at::DateTime
    status::Symbol  # :pending, :prepared, :committed, :rolled_back
    input_assets::Vector{AssetPair{T}}
    output_assets::Vector{AssetPair{T}}
    routes::Vector{Route{T}}
    gas_limit::T
    deadline::DateTime
    metadata::Dict{String, Any}
    lock_version::Int
end

struct TransactionReceipt{T<:Real}
    transaction_id::UUID
    block_number::Int
    block_timestamp::DateTime
    gas_used::T
    success::Bool
    revert_reason::Union{String, Nothing}
    output_amounts::Vector{T}
end

# Settlement results
struct SettlementMetrics{T<:Real}
    latency_ms::T
    gas_used::T
    price_improvement::T
    slippage::T
    routing_efficiency::T
    mev_extracted::T
end

struct SettlementResult{T<:Real} <: AbstractSettlement
    transaction::AtomicTransaction{T}
    receipt::TransactionReceipt{T}
    metrics::SettlementMetrics{T}
    execution_paths::Vector{ExecutionPath{T}}
    timestamp::DateTime
    success::Bool
    error::Union{String, Nothing}
end

# MEV Protection types
struct SandwichDetection{T<:Real}
    detected::Bool
    confidence::T
    front_transaction::Union{String, Nothing}
    back_transaction::Union{String, Nothing}
    estimated_loss::T
end

struct CommitRevealParams{T<:Real}
    commit_hash::Vector{UInt8}
    reveal_block::Int
    nonce::Vector{UInt8}
    timeout_blocks::Int
    bond_amount::T
end

struct MEVProtectionResult{T<:Real}
    protection_type::Symbol  # :none, :commit_reveal, :flashbots, :cow
    sandwich_detection::SandwichDetection{T}
    commit_reveal::Union{CommitRevealParams{T}, Nothing}
    protection_cost::T
    estimated_savings::T
end

# Cache types
struct CacheEntry{T}
    key::String
    value::T
    timestamp::DateTime
    ttl_seconds::Int
    access_count::Int
end

struct CacheStats
    hits::Int
    misses::Int
    evictions::Int
    memory_bytes::Int
    avg_latency_ns::Float64
end

# Circuit breaker types
mutable struct CircuitBreakerState
    is_open::Bool
    failure_count::Int
    success_count::Int
    last_failure_time::DateTime
    last_success_time::DateTime
    half_open_attempts::Int
end

struct CircuitBreakerConfig
    failure_threshold::Int
    success_threshold::Int
    timeout_seconds::Int
    half_open_max_attempts::Int
end

# Protocol adapter types
struct ProtocolCapabilities
    supports_multi_path::Bool
    supports_flash_loans::Bool
    supports_partial_fill::Bool
    max_slippage::Float64
    min_liquidity::Float64
    fee_tiers::Vector{Float64}
end

abstract type AbstractProtocolAdapter end

struct ProtocolMetadata
    name::String
    version::String
    chain_id::Int
    capabilities::ProtocolCapabilities
    health_endpoint::Union{String, Nothing}
end

# Error types
struct SettlementError <: Exception
    code::Symbol
    message::String
    details::Dict{String, Any}
    timestamp::DateTime
end

# Type unions for convenience
const Price = Union{Float32, Float64, Rational}
const Amount = Union{Int, Float32, Float64}
const GasAmount = Union{Int, UInt}

# Export all types
export AbstractSettlement, AbstractTransaction, AbstractRoute
export AbstractProtocol, AbstractMEVProtection, AbstractProtocolAdapter
export AssetPair, PriceQuote, RouteSegment, Route, ExecutionPath
export AtomicTransaction, TransactionReceipt
export SettlementMetrics, SettlementResult
export SandwichDetection, CommitRevealParams, MEVProtectionResult
export CacheEntry, CacheStats
export CircuitBreakerState, CircuitBreakerConfig
export ProtocolCapabilities, ProtocolMetadata
export SettlementError
export Price, Amount, GasAmount

end # module Types