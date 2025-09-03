module StateManager

using Base.Threads: @spawn, Atomic, ReentrantLock
using Dates
using UUIDs
# Define StateValue union type for type safety
const StateValue = Union{Float64, Int64, String, Bool, Vector{Float64}, Vector{Int64}, Set{UUID}, DateTime, UUID, Nothing}
const StateDict = Dict{String, StateValue}

export StateStore, StateSnapshot, StateTransaction, ConflictResolution, state_store, StateValue, StateDict
export begin_transaction, commit_transaction!, rollback_transaction!
export take_snapshot, restore_snapshot!, validate_state
export get_state, update_state!, resolve_conflicts

# State snapshot for rollback capability
struct StateSnapshot
    id::UUID
    timestamp::DateTime
    version::Int
    pool_reserves::Dict{Int,Vector{Float64}}
    token_balances::Dict{String,Dict{Int,Float64}}
    pending_settlements::Set{UUID}
    metadata::StateDict
    checksum::UInt64
end

# Transaction for optimistic concurrency control
mutable struct StateTransaction
    id::UUID
    start_version::Int
    read_set::Set{String}  # Keys read during transaction
    write_set::StateDict  # Keys to write
    timestamp::DateTime
    status::Symbol  # :active, :committed, :aborted
    isolation_level::Symbol  # :read_committed, :repeatable_read, :serializable
end

# Conflict resolution strategy
struct ConflictResolution
    strategy::Symbol  # :last_write_wins, :first_write_wins, :merge, :abort
    merge_function::Union{Function,Nothing}
    retry_count::Int
    backoff_ms::Float64
end

# Main state store with MVCC
mutable struct StateStore
    current_version::Atomic{Int}
    current_state::StateDict
    snapshots::Vector{StateSnapshot}
    active_transactions::Dict{UUID,StateTransaction}
    version_history::Dict{Int,StateDict}
    locks::Dict{String,ReentrantLock}
    global_lock::ReentrantLock
    max_snapshots::Int
    max_versions::Int
    conflict_resolution::ConflictResolution
end

"""
    state_store(; kwargs...)

Create a new state store with optimistic concurrency control.
"""
function state_store(;
    max_snapshots::Int=100,
    max_versions::Int=1000,
    conflict_strategy::Symbol=:last_write_wins,
    retry_count::Int=3,
    backoff_ms::Float64=10.0)
    
    resolution = ConflictResolution(
        conflict_strategy,
        nothing,
        retry_count,
        backoff_ms
    )
    
    return StateStore(
        Atomic{Int}(1),
        StateDict(),
        Vector{StateSnapshot}(),
        Dict{UUID,StateTransaction}(),
        Dict{Int,StateDict}(),
        Dict{String,ReentrantLock}(),
        ReentrantLock(),
        max_snapshots,
        max_versions,
        resolution
    )
end

# Compatibility alias - use state_store() instead
StateStore(args...; kwargs...) = state_store(args...; kwargs...)
end

"""
    begin_transaction(store; isolation_level)

Begin a new transaction with specified isolation level.
"""
function begin_transaction(store::StateStore;
                         isolation_level::Symbol=:read_committed)
    
    transaction_id = uuid4()
    
    lock(store.global_lock) do
        current_ver = store.current_version[]
        
        transaction = StateTransaction(
            transaction_id,
            current_ver,
            Set{String}(),
            StateDict(),
            now(),
            :active,
            isolation_level
        )
        
        store.active_transactions[transaction_id] = transaction
        
        return transaction
    end
end

"""
    commit_transaction!(store, transaction)

Attempt to commit a transaction using optimistic concurrency control.
"""
function commit_transaction!(store::StateStore, transaction::StateTransaction)
    if transaction.status != :active
        return (success=false, reason="Transaction not active")
    end
    
    lock(store.global_lock) do
        # Check for conflicts
        conflicts = detect_conflicts(store, transaction)
        
        if !isempty(conflicts)
            # Try to resolve conflicts
            resolution = resolve_conflicts(store, transaction, conflicts)
            
            if !resolution.success
                transaction.status = :aborted
                delete!(store.active_transactions, transaction.id)
                return (success=false, reason="Conflict resolution failed", conflicts=conflicts)
            end
        end
        
        # Apply writes
        new_version = atomic_add!(store.current_version, 1)
        
        # Create version snapshot
        version_state = copy(store.current_state)
        
        # Apply transaction writes
        for (key, value) in transaction.write_set
            store.current_state[key] = value
            version_state[key] = value
        end
        
        # Store version history
        store.version_history[new_version] = version_state
        
        # Clean old versions
        if length(store.version_history) > store.max_versions
            min_version = minimum(keys(store.version_history))
            delete!(store.version_history, min_version)
        end
        
        # Mark transaction as committed
        transaction.status = :committed
        delete!(store.active_transactions, transaction.id)
        
        return (success=true, reason="Committed", version=new_version)
    end
end

"""
    rollback_transaction!(store, transaction)

Rollback an active transaction.
"""
function rollback_transaction!(store::StateStore, transaction::StateTransaction)
    lock(store.global_lock) do
        if transaction.status == :active
            transaction.status = :aborted
            delete!(store.active_transactions, transaction.id)
            
            # Clear any partial writes
            empty!(transaction.write_set)
            
            return true
        end
        return false
    end
end

"""
    take_snapshot(store)

Create a snapshot of the current state.
"""
function take_snapshot(store::StateStore)
    lock(store.global_lock) do
        snapshot_id = uuid4()
        current_ver = store.current_version[]
        
        # Deep copy state components
        pool_reserves = Dict{Int,Vector{Float64}}()
        token_balances = Dict{String,Dict{Int,Float64}}()
        pending = Set{UUID}()
        
        # Extract pool reserves
        for (key, value) in store.current_state
            if startswith(key, "pool:")
                pool_id = parse(Int, split(key, ":")[2])
                if isa(value, Vector{Float64})
                    pool_reserves[pool_id] = copy(value)
                end
            elseif startswith(key, "balance:")
                parts = split(key, ":")
                if length(parts) == 3
                    address = parts[2]
                    token_id = parse(Int, parts[3])
                    if !haskey(token_balances, address)
                        token_balances[address] = Dict{Int,Float64}()
                    end
                    token_balances[address][token_id] = value
                end
            elseif startswith(key, "pending:")
                settlement_id = UUID(split(key, ":")[2])
                push!(pending, settlement_id)
            end
        end
        
        # Calculate checksum
        checksum = calculate_state_checksum(store.current_state)
        
        snapshot = StateSnapshot(
            snapshot_id,
            now(),
            current_ver,
            pool_reserves,
            token_balances,
            pending,
            StateDict(),
            checksum
        )
        
        # Store snapshot
        push!(store.snapshots, snapshot)
        
        # Maintain snapshot limit
        if length(store.snapshots) > store.max_snapshots
            deleteat!(store.snapshots, 1:length(store.snapshots)-store.max_snapshots)
        end
        
        return snapshot
    end
end

"""
    restore_snapshot!(store, snapshot_id)

Restore state from a snapshot.
"""
function restore_snapshot!(store::StateStore, snapshot_id::UUID)
    lock(store.global_lock) do
        # Find snapshot
        snapshot_idx = findfirst(s -> s.id == snapshot_id, store.snapshots)
        
        if snapshot_idx === nothing
            return (success=false, reason="Snapshot not found")
        end
        
        snapshot = store.snapshots[snapshot_idx]
        
        # Abort all active transactions
        for transaction in values(store.active_transactions)
            transaction.status = :aborted
        end
        empty!(store.active_transactions)
        
        # Clear current state
        empty!(store.current_state)
        
        # Restore pool reserves
        for (pool_id, reserves) in snapshot.pool_reserves
            store.current_state["pool:$pool_id"] = copy(reserves)
        end
        
        # Restore token balances
        for (address, balances) in snapshot.token_balances
            for (token_id, balance) in balances
                store.current_state["balance:$address:$token_id"] = balance
            end
        end
        
        # Restore pending settlements
        for settlement_id in snapshot.pending_settlements
            store.current_state["pending:$settlement_id"] = true
        end
        
        # Update version
        store.current_version[] = snapshot.version
        
        # Verify checksum
        new_checksum = calculate_state_checksum(store.current_state)
        if new_checksum != snapshot.checksum
            @warn "Checksum mismatch after restore" expected=snapshot.checksum actual=new_checksum
        end
        
        return (success=true, reason="Restored", version=snapshot.version)
    end
end

"""
    get_state(store, key, transaction)

Read state value within a transaction context.
"""
function get_state(store::StateStore, key::String, transaction::Union{StateTransaction,Nothing}=nothing)
    if transaction !== nothing && transaction.status == :active
        # Record read in transaction
        push!(transaction.read_set, key)
        
        # Check write set first
        if haskey(transaction.write_set, key)
            return transaction.write_set[key]
        end
        
        # Isolation level handling
        if transaction.isolation_level == :serializable
            # Use snapshot from transaction start
            version = transaction.start_version
            if haskey(store.version_history, version)
                return get(store.version_history[version], key, nothing)
            end
        end
    end
    
    # Read from current state
    lock(store.global_lock) do
        return get(store.current_state, key, nothing)
    end
end

"""
    update_state!(store, key, value, transaction)

Update state value within a transaction context.
"""
function update_state!(store::StateStore, key::String, value::StateValue,
                      transaction::Union{StateTransaction,Nothing}=nothing)
    
    if transaction !== nothing && transaction.status == :active
        # Add to write set
        transaction.write_set[key] = value
        return true
    else
        # Direct update (auto-commit)
        lock(store.global_lock) do
            store.current_state[key] = value
            atomic_add!(store.current_version, 1)
            return true
        end
    end
end

"""
    validate_state(store)

Validate state consistency and invariants.
"""
function validate_state(store::StateStore)
    lock(store.global_lock) do
        issues = String[]
        
        # Check pool reserves
        for (key, value) in store.current_state
            if startswith(key, "pool:")
                if isa(value, Vector{Float64})
                    # Check for negative reserves
                    if any(v -> v < 0, value)
                        push!(issues, "Negative reserves in $key")
                    end
                    
                    # Check for zero liquidity
                    if all(v -> v ≈ 0, value)
                        push!(issues, "Zero liquidity in $key")
                    end
                else
                    push!(issues, "Invalid type for $key")
                end
            elseif startswith(key, "balance:")
                if !isa(value, Number)
                    push!(issues, "Invalid balance type for $key")
                elseif value < 0
                    push!(issues, "Negative balance in $key")
                end
            end
        end
        
        # Check version consistency
        current_ver = store.current_version[]
        if !isempty(store.version_history)
            max_stored = maximum(keys(store.version_history))
            if max_stored > current_ver
                push!(issues, "Version inconsistency: stored=$max_stored, current=$current_ver")
            end
        end
        
        return (valid=isempty(issues), issues=issues)
    end
end

# Conflict detection and resolution

function detect_conflicts(store::StateStore, transaction::StateTransaction)
    conflicts = String[]
    
    # Check if any read values have changed
    for key in transaction.read_set
        if haskey(store.version_history, transaction.start_version)
            old_value = get(store.version_history[transaction.start_version], key, nothing)
            current_value = get(store.current_state, key, nothing)
            
            if old_value != current_value
                push!(conflicts, key)
            end
        end
    end
    
    # Check write-write conflicts with other transactions
    for other_tx in values(store.active_transactions)
        if other_tx.id != transaction.id && other_tx.status == :active
            for key in keys(transaction.write_set)
                if key in keys(other_tx.write_set)
                    push!(conflicts, "write-write:$key")
                end
            end
        end
    end
    
    return conflicts
end

"""
    resolve_conflicts(store, transaction, conflicts)

Attempt to resolve conflicts based on resolution strategy.
"""
function resolve_conflicts(store::StateStore, transaction::StateTransaction, conflicts::Vector{String})
    strategy = store.conflict_resolution.strategy
    
    if strategy == :abort
        return (success=false, reason="Abort on conflict")
    elseif strategy == :last_write_wins
        # Allow transaction to proceed
        return (success=true, reason="Last write wins")
    elseif strategy == :first_write_wins
        # Check if we're first
        our_time = transaction.timestamp
        for other_tx in values(store.active_transactions)
            if other_tx.id != transaction.id && other_tx.timestamp < our_time
                # Another transaction is older
                return (success=false, reason="First write wins - older transaction exists")
            end
        end
        return (success=true, reason="First write wins - we are first")
    elseif strategy == :merge && store.conflict_resolution.merge_function !== nothing
        # Custom merge logic
        try
            merged = store.conflict_resolution.merge_function(transaction, conflicts, store.current_state)
            transaction.write_set = merged
            return (success=true, reason="Merged")
        catch e
            return (success=false, reason="Merge failed: $e")
        end
    else
        return (success=false, reason="Unknown resolution strategy")
    end
end

# Helper functions

function calculate_state_checksum(state::StateDict)
    # Simple checksum based on sorted keys and values
    checksum = UInt64(0)
    for key in sort(collect(keys(state)))
        checksum = checksum ⊻ hash(key)
        checksum = checksum ⊻ hash(state[key])
    end
    return checksum
end

end # module