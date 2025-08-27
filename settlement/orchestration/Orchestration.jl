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

# Export coordinator functionality
export CoordinationContext, ConsensusProtocol, Participant, Vote
export coordinate_settlement, register_participant, unregister_participant
export check_consensus, monitor_health, handle_failure

# Submodule for coordination logic (future extensibility)
include("coordinator/Coordinator.jl")
using .Coordinator
include("SettlementOrchestrator.jl")
include("PhantomAuction.jl")

end # module Orchestration