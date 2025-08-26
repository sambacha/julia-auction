"""
    Bridge

CFMM integration bridge providing adapters and interfaces between the settlement
system and various CFMM protocols. Handles protocol-specific translations and
optimizations.

# Components
- `CFMMBridge` - Main CFMM interface adapter
- `adapters/` - Protocol-specific adapters (Uniswap, Balancer, etc.)
- `optimization/` - Route optimization and aggregation
"""
module Bridge

using CFMMRouter

export CFMMBridge, RouteOptimizer
export prepare_routes, execute_transaction, estimate_impact

# Protocol adapters submodule
include("adapters/Adapters.jl")
using .Adapters

# Route optimization submodule
include("optimization/Optimization.jl")
using .Optimization

include("CFMMBridge.jl")

end # module Bridge