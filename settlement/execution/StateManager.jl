"""
    StateManager

Manages state consistency across settlement operations. Provides
checkpointing, validation, and recovery mechanisms.

# Responsibilities
- Track settlement state transitions
- Maintain consistency invariants
- Provide rollback capabilities
- Handle state recovery after failures
"""

using .Recovery: RecoveryManager, checkpoint_state, restore_checkpoint
using Base: UUID
using Dates

mutable struct SettlementState
    id::UUID
    status::Symbol  # :pending, :prepared, :committed, :rolled_back
    created_at::DateTime
    updated_at::DateTime
    checkpoints::Vector{Dict{String, Any}}
    metadata::Dict{Symbol, Any}
end

mutable struct StateManager
    active_states::Dict{UUID, SettlementState}
    recovery_manager::RecoveryManager
    state_lock::ReentrantLock
    config::NamedTuple
    
    function StateManager(;
        max_active_states::Int = 100,
        checkpoint_interval_ms::Int = 50,
        enable_persistence::Bool = false
    )
        config = (
            max_active_states = max_active_states,
            checkpoint_interval_ms = checkpoint_interval_ms,
            enable_persistence = enable_persistence
        )
        new(
            Dict{UUID, SettlementState}(),
            RecoveryManager(enable_persistence),
            ReentrantLock(),
            config
        )
    end
end

"""
    create_transaction(manager, auction_result)

Create a new atomic transaction from auction results.

# Returns
- `AtomicTransaction` ready for settlement
"""
function create_transaction(manager::StateManager, auction_result)
    lock(manager.state_lock) do
        # Generate unique transaction ID
        tx_id = UUID(rand(UInt128))
        
        # Create settlement state
        state = SettlementState(
            tx_id,
            :pending,
            now(),
            now(),
            Vector{Dict{String, Any}}(),
            Dict{Symbol, Any}(
                :auction_id => auction_result.auction_id,
                :winner_id => auction_result.winner_id,
                :winning_price => auction_result.winning_price
            )
        )
        
        # Store state
        manager.active_states[tx_id] = state
        
        # Create checkpoint
        if manager.config.enable_persistence
            checkpoint_state(manager.recovery_manager, state)
        end
        
        # Clean up old states if needed
        cleanup_old_states!(manager)
        
        return AtomicTransaction(
            tx_id,
            auction_result,
            state
        )
    end
end

"""
    validate_transaction(manager, transaction)

Validate transaction state consistency and invariants.

# Throws
- `ErrorException` if validation fails
"""
function validate_transaction(manager::StateManager, transaction::AtomicTransaction)
    lock(manager.state_lock) do
        state = get(manager.active_states, transaction.id, nothing)
        
        if state === nothing
            throw(ErrorException("Transaction not found: $(transaction.id)"))
        end
        
        # Validate state transitions
        if state.status == :rolled_back
            throw(ErrorException("Transaction already rolled back"))
        end
        
        if state.status == :committed
            throw(ErrorException("Transaction already committed"))
        end
        
        # Validate invariants
        validate_invariants(state, transaction)
        
        # Update status
        state.status = :prepared
        state.updated_at = now()
        
        return true
    end
end

"""
    finalize_transaction!(manager, transaction, execution_result)

Finalize the transaction with execution results.
"""
function finalize_transaction!(
    manager::StateManager,
    transaction::AtomicTransaction,
    execution_result
)
    lock(manager.state_lock) do
        state = manager.active_states[transaction.id]
        
        # Record execution result
        state.metadata[:execution_result] = execution_result
        state.metadata[:finalized_at] = now()
        
        # Update status
        state.status = :committed
        state.updated_at = now()
        
        # Final checkpoint
        if manager.config.enable_persistence
            checkpoint_state(manager.recovery_manager, state)
        end
        
        return state
    end
end

"""
    rollback_transaction!(manager, transaction)

Rollback a transaction to previous state.
"""
function rollback_transaction!(manager::StateManager, transaction::AtomicTransaction)
    lock(manager.state_lock) do
        state = get(manager.active_states, transaction.id, nothing)
        
        if state === nothing
            return  # Already cleaned up
        end
        
        # Restore from last checkpoint if available
        if !isempty(state.checkpoints)
            last_checkpoint = state.checkpoints[end]
            restore_from_checkpoint!(state, last_checkpoint)
        end
        
        # Update status
        state.status = :rolled_back
        state.updated_at = now()
        
        # Log rollback
        state.metadata[:rolled_back_at] = now()
        
        return state
    end
end

# Helper functions

function validate_invariants(state::SettlementState, transaction::AtomicTransaction)
    # Check basic invariants
    if transaction.auction_result.winning_price < 0
        throw(ErrorException("Invalid winning price"))
    end
    
    # Check state consistency
    if state.created_at > now()
        throw(ErrorException("Invalid timestamp"))
    end
    
    # Additional validation rules can be added here
    return true
end

function cleanup_old_states!(manager::StateManager)
    if length(manager.active_states) <= manager.config.max_active_states
        return
    end
    
    # Find and remove oldest completed states
    cutoff_time = now() - Minute(5)
    
    for (id, state) in manager.active_states
        if state.status in [:committed, :rolled_back] && 
           state.updated_at < cutoff_time
            delete!(manager.active_states, id)
        end
    end
end

function restore_from_checkpoint!(state::SettlementState, checkpoint::Dict)
    # Restore state fields from checkpoint
    for (key, value) in checkpoint
        if key == "metadata"
            merge!(state.metadata, value)
        elseif hasfield(SettlementState, Symbol(key))
            setfield!(state, Symbol(key), value)
        end
    end
end