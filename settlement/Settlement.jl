"""
    Settlement

Production-grade post-CFMM auction settlement system providing atomic, 
high-performance settlement orchestration between auctions and CFMM routers.

# Architecture
This module follows depth-first scaling with max 7 siblings per directory level.
Each subtree represents an independent ownership boundary with minimal public APIs.

# Core Components
- `orchestration/` - Settlement orchestration and coordination
- `bridge/` - CFMM integration and protocol adapters  
- `execution/` - Atomic execution and state management
- `monitoring/` - Performance and latency tracking
- `protection/` - MEV protection and security
- `routing/` - Advanced multi-path routing optimization
- `cache/` - High-performance caching layer

# Performance
- Sub-100ms settlement latency
- Parallel execution support
- Lock-free data structures where possible
- Zero-allocation hot paths

# Usage
```julia
using Settlement

# Initialize with configuration
config = SettlementConfig(
    max_latency_ms = 100,
    enable_mev_protection = true,
    enable_parallel_execution = true
)

# Initialize settlement orchestrator
orchestrator = SettlementOrchestrator(
    cfmm_bridge = CFMMBridge(router),
    state_manager = StateManager(),
    config = config
)

# Process auction settlement
result = settle_auction(orchestrator, auction_result)
```
"""
module Settlement

using AuctionKit
using CFMMRouter
using Base.Threads
using Dates
using UUIDs
using Statistics
using LinearAlgebra
using SparseArrays
using DataStructures
using JSON3
using HTTP

# Core types
export SettlementOrchestrator, CFMMBridge, StateManager
export AtomicTransaction, SettlementResult, PriceImprovement
export SettlementConfig, RouteOptimizer, MEVProtection
export ProtocolAdapter, CacheManager, CircuitBreaker

# Main functions
export settle_auction, validate_settlement, rollback_settlement
export calculate_price_improvement, monitor_latency
export optimize_routes, detect_sandwich_attack, enable_protection

# Advanced functions
export parallel_settle, batch_settle, emergency_halt
export get_settlement_metrics, export_metrics, health_check

# Module includes - organized by functional domain
include("types/Types.jl")
using .Types

include("config/Config.jl")
using .Config

include("orchestration/Orchestration.jl")
using .Orchestration

include("bridge/Bridge.jl")
using .Bridge

include("execution/Execution.jl")
using .Execution

include("monitoring/Monitoring.jl")
using .Monitoring

include("protection/Protection.jl")
using .Protection

include("routing/Routing.jl")
using .Routing

include("cache/Cache.jl")
using .Cache

end # module Settlement