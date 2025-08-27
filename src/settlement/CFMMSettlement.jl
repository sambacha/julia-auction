"""
    CFMMSettlement

Production-grade CFMM (Constant Function Market Maker) settlement system for the Julia Auction System.
Provides high-performance order routing, MEV protection, and atomic settlement with sub-100ms latency.

# Features
- Multi-protocol support (Uniswap V2/V3, Balancer, Curve)
- Advanced routing optimization with multi-path splitting
- MEV protection with sandwich attack detection
- Two-phase commit for atomic settlement
- Intelligent caching with route pre-computation
- Circuit breakers and monitoring

# Example
```julia
using CFMMSettlement

# Initialize settlement system
config = SettlementConfig(
    max_latency_ms = 100,
    enable_mev_protection = true,
    routing_algorithm = :optimal,
)
orchestrator = SettlementOrchestrator(config)

# Process settlement
transaction = SettlementTransaction(
    asset_pair = ("ETH", "USDC"),
    amount = 100.0,
    max_slippage = 0.01,
)
result = process_settlement(orchestrator, transaction)
```
"""
module CFMMSettlement

# Ordered imports (alphabetical)
using Base.Threads
using DataStructures
using Dates
using HTTP
using JSON3
using LinearAlgebra
using SparseArrays
using Statistics
using UUIDs

# Custom imports
using ..AuctionKit
using ..CFMMRouter

# Type definitions
include("types/SettlementTypes.jl")
include("config/SettlementConfig.jl")

# Core modules
include("protection/MEVProtection.jl")
include("routing/RouteOptimizer.jl")
include("cache/RouteCache.jl")
include("execution/AtomicExecution.jl")
include("monitoring/SettlementMonitor.jl")

# Protocol adapters
include("adapters/UniswapV2Adapter.jl")
include("adapters/UniswapV3Adapter.jl")
include("adapters/BalancerAdapter.jl")
include("adapters/CurveAdapter.jl")

# Orchestration
include("orchestration/Orchestrator.jl")

# Public exports
export SettlementConfig,
       SettlementOrchestrator,
       SettlementTransaction,
       SettlementResult,
       MEVProtectionConfig,
       RouteOptimizationConfig,
       
       # Functions
       process_settlement,
       validate_settlement,
       estimate_gas_cost,
       calculate_price_impact,
       detect_mev_risk,
       
       # Monitoring
       get_settlement_metrics,
       get_circuit_breaker_status,
       emergency_halt,
       resume_operations

# Module initialization
function __init__()
    # Warm up JIT compilation
    if get(ENV, "CFMM_PRECOMPILE", "true") == "true"
        _precompile_hot_paths()
    end
end

function _precompile_hot_paths()
    # Precompile common operations
    config = SettlementConfig()
    orchestrator = SettlementOrchestrator(config)
    
    # Trigger compilation of critical paths
    tx = SettlementTransaction(
        id = uuid4(),
        asset_pair = ("ETH", "USDC"),
        amount = 100.0,
        max_slippage = 0.01,
        deadline = now() + Minute(5),
    )
    
    try
        validate_settlement(orchestrator, tx)
        estimate_gas_cost(orchestrator, tx)
        calculate_price_impact(tx, 1000000.0, 3000000.0)
    catch
        # Ignore errors during precompilation
    end
end

end # module CFMMSettlement