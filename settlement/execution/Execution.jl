"""
    Execution

Atomic execution and state management module ensuring consistency and
recoverability of settlement operations.

# Components
- `StateManager` - State consistency and recovery
- `AtomicSettlement` - Two-phase commit protocol
- `PriceImprovement` - Price improvement calculation
- `recovery/` - Recovery and rollback mechanisms
"""
module Execution

export StateManager, AtomicTransaction, AtomicSettlement
export PriceImprovement, SettlementResult
export create_transaction, validate_transaction, finalize_transaction!

# Recovery submodule
include("recovery/Recovery.jl")
using .Recovery
include("StateManager.jl")
include("AtomicSettlement.jl")
include("PriceImprovement.jl")

end # module Execution