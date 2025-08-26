"""
    SettlementOrchestrator

Main orchestration controller for settlement operations. Coordinates between
auction results, CFMM execution, and state management to ensure atomic settlement.

# Fields
- `cfmm_bridge::CFMMBridge` - Interface to CFMM router
- `state_manager::StateManager` - State consistency management
- `phantom_auction::PhantomAuction` - Price discovery overlay
- `config::OrchestratorConfig` - Configuration parameters

# Key Methods
- `settle_auction` - Main settlement entry point
- `prepare_settlement` - Phase 1 of two-phase commit
- `commit_settlement` - Phase 2 of two-phase commit
- `rollback_settlement` - Abort and rollback on failure
"""

using ...Bridge: CFMMBridge
using ...Execution: StateManager, AtomicTransaction

struct OrchestratorConfig
    max_retry_attempts::Int
    settlement_timeout_ms::Int
    price_improvement_threshold::Float64
    enable_phantom_auction::Bool
    
    function OrchestratorConfig(;
        max_retry_attempts::Int = 3,
        settlement_timeout_ms::Int = 100,
        price_improvement_threshold::Float64 = 0.001,
        enable_phantom_auction::Bool = true
    )
        new(max_retry_attempts, settlement_timeout_ms, 
            price_improvement_threshold, enable_phantom_auction)
    end
end

mutable struct SettlementOrchestrator
    cfmm_bridge::CFMMBridge
    state_manager::StateManager
    phantom_auction::Union{PhantomAuction, Nothing}
    config::OrchestratorConfig
    active_transactions::Vector{AtomicTransaction}
    
    function SettlementOrchestrator(
        cfmm_bridge::CFMMBridge,
        state_manager::StateManager;
        config::OrchestratorConfig = OrchestratorConfig()
    )
        phantom = config.enable_phantom_auction ? PhantomAuction() : nothing
        new(cfmm_bridge, state_manager, phantom, config, AtomicTransaction[])
    end
end

"""
    orchestrate_settlement(orchestrator, auction_result)

Main orchestration entry point. Coordinates the entire settlement process
including phantom auction overlay, CFMM routing, and atomic commitment.

# Returns
- `SettlementResult` with execution details and metrics
"""
function orchestrate_settlement(
    orchestrator::SettlementOrchestrator,
    auction_result::AuctionResult
)
    # Phase 1: Prepare settlement
    transaction = prepare_settlement(orchestrator, auction_result)
    
    # Phase 2: Execute phantom auction if enabled
    if orchestrator.phantom_auction !== nothing
        phantom_result = run_phantom_auction(
            orchestrator.phantom_auction,
            transaction
        )
        transaction = merge_phantom_result(transaction, phantom_result)
    end
    
    # Phase 3: Commit to CFMM
    try
        result = commit_settlement(orchestrator, transaction)
        return result
    catch e
        rollback_settlement(orchestrator, transaction)
        rethrow(e)
    end
end

function prepare_settlement(
    orchestrator::SettlementOrchestrator,
    auction_result::AuctionResult
)
    # Create atomic transaction
    transaction = create_transaction(orchestrator.state_manager, auction_result)
    
    # Validate state consistency
    validate_transaction(orchestrator.state_manager, transaction)
    
    # Prepare CFMM routes
    routes = prepare_routes(orchestrator.cfmm_bridge, transaction)
    transaction.routes = routes
    
    push!(orchestrator.active_transactions, transaction)
    return transaction
end

function commit_settlement(
    orchestrator::SettlementOrchestrator,
    transaction::AtomicTransaction
)
    # Execute on CFMM
    execution_result = execute_transaction(
        orchestrator.cfmm_bridge,
        transaction
    )
    
    # Update state
    finalize_transaction!(orchestrator.state_manager, transaction, execution_result)
    
    # Clean up
    filter!(t -> t.id != transaction.id, orchestrator.active_transactions)
    
    return SettlementResult(transaction, execution_result)
end

function rollback_settlement(
    orchestrator::SettlementOrchestrator,
    transaction::AtomicTransaction
)
    # Rollback state changes
    rollback_transaction!(orchestrator.state_manager, transaction)
    
    # Clean up active transactions
    filter!(t -> t.id != transaction.id, orchestrator.active_transactions)
    
    @warn "Settlement rolled back" transaction_id=transaction.id
end