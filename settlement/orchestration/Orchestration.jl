"""
    Orchestration

Settlement orchestration module managing the coordination between auctions and CFMMs.
This module serves as the main control plane for settlement operations.

# Components
- `SettlementOrchestrator` - Main orchestration controller
- `PhantomAuction` - Lightweight auction overlay for price discovery
- `coordinator/` - Multi-party coordination logic
"""
module Orchestration

export SettlementOrchestrator, PhantomAuction
export orchestrate_settlement, create_phantom_auction

# Submodule for coordination logic (future extensibility)
include("coordinator/Coordinator.jl")
using .Coordinator

include("SettlementOrchestrator.jl")
include("PhantomAuction.jl")

end # module Orchestration