"""
    Settlement

Post-CFMM auction settlement system providing atomic, high-performance settlement
orchestration between auctions and CFMM routers.

# Architecture
This module follows depth-first scaling with max 7 siblings per directory level.
Each subtree represents an independent ownership boundary with minimal public APIs.

# Core Components
- `orchestration/` - Settlement orchestration and coordination
- `bridge/` - CFMM integration and protocol adapters
- `execution/` - Atomic execution and state management
- `monitoring/` - Performance and latency tracking

# Usage
```julia
using Settlement
# Initialize settlement orchestrator
orchestrator = SettlementOrchestrator(
    cfmm_bridge = CFMMBridge(router),
    state_manager = StateManager()
)

# Process auction settlement
result = settle_auction(orchestrator, auction_result)
```
"""
module Settlement

using AuctionKit
using CFMMRouter
# Export main types
export SettlementOrchestrator, CFMMBridge, StateManager
export AtomicTransaction, SettlementResult, PriceImprovement

# Export main functions
export settle_auction, validate_settlement, rollback_settlement
export calculate_price_improvement, monitor_latency

# Module includes - organized by functional domain
include("orchestration/Orchestration.jl")
using .Orchestration
include("bridge/Bridge.jl")
using .Bridge
include("execution/Execution.jl")
using .Execution
include("monitoring/Monitoring.jl")
using .Monitoring
end # module Settlement