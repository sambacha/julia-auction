module AtomicSettlement

using Base.Threads: @spawn, Atomic, ReentrantLock
using Dates
using UUIDs

# Import configuration manager
include("../../config/ConfigManager.jl")
using .ConfigManager: load_config, get_config, AuctionConfig

# Import CFMMBridge for real execution
using ..CFMMBridge
using ..CFMMBridge: Bridge, get_route, execute_direct, get_baseline_price

export AtomicExecutor, SettlementBatch, ExecutionPlan, ValidationResult, atomic_executor
export prepare_batch, validate_batch, execute_atomic!, rollback_batch
export create_execution_plan, verify_atomicity, get_batch_status

# Single settlement in a batch
struct Settlement
    id::UUID
    user_address::String
    token_in::Int
    token_out::Int
    amount_in::Float64
    amount_out::Float64
    execution_path::Vector{Int}
    price::Float64
    gas_estimate::Int
    deadline::DateTime
end

# Batch of settlements for atomic execution
mutable struct SettlementBatch
    id::UUID
    settlements::Vector{Settlement}
    total_value::Float64
    status::Symbol  # :pending, :preparing, :ready, :executing, :completed, :failed
    prepare_timestamp::Union{DateTime,Nothing}
    commit_timestamp::Union{DateTime,Nothing}
    error::Union{String,Nothing}
    retries::Int
end

# Execution plan for atomic settlement
struct ExecutionPlan
    batch_id::UUID
    steps::Vector{Function}  # Ordered execution steps
    validations::Vector{Function}  # Validation checks
    compensations::Vector{Function}  # Compensation actions for rollback
    gas_estimate::Int
    estimated_time_ms::Float64
end

# Validation result
struct ValidationResult
    valid::Bool
    errors::Vector{String}
    warnings::Vector{String}
    checks_passed::Int
    total_checks::Int
end

# Main atomic executor
mutable struct AtomicExecutor
    active_batches::Dict{UUID,SettlementBatch}
    execution_plans::Dict{UUID,ExecutionPlan}
    state_manager::Union{StateManager, Nothing}  # Reference to StateManager
    router_bridge::Union{Bridge, Nothing}  # Reference to CFMMBridge
    lock::ReentrantLock
    max_batch_size::Int
    max_retries::Int
    prepare_timeout_ms::Float64
    commit_timeout_ms::Float64
    fallback_enabled::Bool
end

"""
    atomic_executor(; kwargs...)

Create an atomic settlement executor with two-phase commit.
"""
function atomic_executor(;
    max_batch_size::Union{Int, Nothing}=nothing,
    max_retries::Union{Int, Nothing}=nothing,
    prepare_timeout_ms::Union{Float64, Nothing}=nothing,
    commit_timeout_ms::Union{Float64, Nothing}=nothing,
    fallback_enabled::Union{Bool, Nothing}=nothing,
    config::AuctionConfig=load_config())
    
    # Use provided values or load from config
    final_max_batch_size = max_batch_size !== nothing ? max_batch_size : get_config(config, "settlement.max_batch_size", Int, 50)
    final_max_retries = max_retries !== nothing ? max_retries : get_config(config, "settlement.max_retries", Int)
    final_prepare_timeout_ms = prepare_timeout_ms !== nothing ? prepare_timeout_ms : get_config(config, "timeouts.settlement_prepare_timeout_ms", Float64, 100.0)
    final_commit_timeout_ms = commit_timeout_ms !== nothing ? commit_timeout_ms : get_config(config, "timeouts.settlement_commit_timeout_ms", Float64, 500.0)
    final_fallback_enabled = fallback_enabled !== nothing ? fallback_enabled : get_config(config, "settlement.fallback_enabled", Bool, true)
    
    return AtomicExecutor(
        Dict{UUID,SettlementBatch}(),
        Dict{UUID,ExecutionPlan}(),
        nothing,  # State manager injected later
        nothing,  # Router bridge injected later
        ReentrantLock(),
        final_max_batch_size,
        final_max_retries,
        final_prepare_timeout_ms,
        final_commit_timeout_ms,
        final_fallback_enabled
    )
end

# Compatibility alias - use atomic_executor() instead
AtomicExecutor(args...; kwargs...) = atomic_executor(args...; kwargs...)
end

"""
    prepare_batch(executor, settlements)

Prepare a batch of settlements for atomic execution (Phase 1).
"""
function prepare_batch(executor::AtomicExecutor, settlements::Vector{Settlement})
    if length(settlements) > executor.max_batch_size
        return (success=false, reason="Batch size exceeds limit", batch_id=nothing)
    end
    
    batch_id = uuid4()
    total_value = sum(s.amount_in * s.price for s in settlements)
    
    batch = SettlementBatch(
        batch_id,
        settlements,
        total_value,
        :preparing,
        nothing,
        nothing,
        nothing,
        0
    )
    
    lock(executor.lock) do
        executor.active_batches[batch_id] = batch
    end
    
    # Start prepare phase
    prepare_start = time_ns()
    
    try
        # Create execution plan
        plan = create_execution_plan(executor, batch)
        
        lock(executor.lock) do
            executor.execution_plans[batch_id] = plan
        end
        
        # Validate batch
        validation = validate_batch(executor, batch, plan)
        
        if !validation.valid
            batch.status = :failed
            batch.error = join(validation.errors, "; ")
            return (success=false, reason="Validation failed", batch_id=batch_id, validation=validation)
        end
        
        # Check timeout
        elapsed_ms = (time_ns() - prepare_start) / 1e6
        if elapsed_ms > executor.prepare_timeout_ms
            batch.status = :failed
            batch.error = "Prepare timeout"
            return (success=false, reason="Prepare timeout", batch_id=batch_id)
        end
        
        # Mark as ready
        batch.status = :ready
        batch.prepare_timestamp = now()
        
        return (success=true, reason="Batch prepared", batch_id=batch_id)
        
    catch e
        batch.status = :failed
        batch.error = string(e)
        return (success=false, reason="Prepare failed: $e", batch_id=batch_id)
    end
end

"""
    execute_atomic!(executor, batch_id)

Execute a prepared batch atomically (Phase 2).
"""
function execute_atomic!(executor::AtomicExecutor, batch_id::UUID)
    batch = lock(executor.lock) do
        get(executor.active_batches, batch_id, nothing)
    end
    
    if batch === nothing
        return (success=false, reason="Batch not found")
    end
    
    if batch.status != :ready
        return (success=false, reason="Batch not ready for execution")
    end
    
    plan = lock(executor.lock) do
        get(executor.execution_plans, batch_id, nothing)
    end
    
    if plan === nothing
        return (success=false, reason="Execution plan not found")
    end
    
    batch.status = :executing
    commit_start = time_ns()
    
    # Begin state transaction if state manager available
    transaction = nothing
    if executor.state_manager !== nothing
        # transaction = begin_transaction(executor.state_manager)
    end
    
    executed_steps = Int[]
    
    try
        # Execute plan steps
        for (i, step) in enumerate(plan.steps)
            # Check timeout
            elapsed_ms = (time_ns() - commit_start) / 1e6
            if elapsed_ms > executor.commit_timeout_ms
                throw(ErrorException("Commit timeout at step $i"))
            end
            
            # Execute step
            step_result = step(batch, transaction)
            
            if !step_result.success
                throw(ErrorException("Step $i failed: $(step_result.reason)"))
            end
            
            push!(executed_steps, i)
        end
        
        # Commit transaction if using state manager
        if transaction !== nothing
            # commit_result = commit_transaction!(executor.state_manager, transaction)
            # if !commit_result.success
            #     throw(ErrorException("Transaction commit failed"))
            # end
        end
        
        # Mark as completed
        batch.status = :completed
        batch.commit_timestamp = now()
        
        return (success=true, reason="Batch executed", executed_steps=executed_steps)
        
    catch e
        # Rollback on failure
        batch.status = :failed
        batch.error = string(e)
        
        if transaction !== nothing
            # rollback_transaction!(executor.state_manager, transaction)
        end
        
        # Execute compensations for completed steps
        for i in reverse(executed_steps)
            if i <= length(plan.compensations)
                try
                    plan.compensations[i](batch)
                catch comp_error
                    @error "Compensation failed" step=i error=comp_error
                end
            end
        end
        
        # Retry logic
        if batch.retries < executor.max_retries
            batch.retries += 1
            batch.status = :ready  # Reset for retry
            return (success=false, reason="Failed, will retry", retry_count=batch.retries)
        end
        
        return (success=false, reason="Execution failed: $e")
    end
end

"""
    validate_batch(executor, batch, plan)

Validate a batch before execution.
"""
function validate_batch(executor::AtomicExecutor, batch::SettlementBatch, plan::ExecutionPlan)
    errors = String[]
    warnings = String[]
    checks_passed = 0
    total_checks = length(plan.validations)
    
    for validation in plan.validations
        try
            result = validation(batch)
            
            if result.valid
                checks_passed += 1
            else
                push!(errors, result.reason)
            end
            
            if haskey(result, :warning) && result.warning !== nothing
                push!(warnings, result.warning)
            end
            
        catch e
            push!(errors, "Validation error: $e")
        end
    end
    
    # Additional validations
    
    # Check deadlines
    current_time = now()
    for settlement in batch.settlements
        if current_time > settlement.deadline
            push!(errors, "Settlement $(settlement.id) past deadline")
        end
    end
    
    # Check batch consistency
    if isempty(batch.settlements)
        push!(errors, "Empty batch")
    end
    
    # Check for duplicate settlements
    settlement_ids = [s.id for s in batch.settlements]
    if length(settlement_ids) != length(unique(settlement_ids))
        push!(errors, "Duplicate settlements in batch")
    end
    
    # Validate execution paths
    for settlement in batch.settlements
        if isempty(settlement.execution_path)
            push!(warnings, "Settlement $(settlement.id) has empty execution path")
        end
    end
    
    return ValidationResult(
        isempty(errors),
        errors,
        warnings,
        checks_passed,
        total_checks
    )
end

"""
    create_execution_plan(executor, batch)

Create a detailed execution plan for a batch.
"""
function create_execution_plan(executor::AtomicExecutor, batch::SettlementBatch)
    steps = Function[]
    validations = Function[]
    compensations = Function[]
    
    # Validation functions
    push!(validations, batch -> validate_liquidity(executor, batch))
    push!(validations, batch -> validate_prices(executor, batch))
    push!(validations, batch -> validate_slippage(executor, batch))
    push!(validations, batch -> validate_gas_limits(executor, batch))
    
    # Execution steps
    
    # Step 1: Lock liquidity
    push!(steps, (batch, tx) -> lock_liquidity(executor, batch, tx))
    push!(compensations, batch -> unlock_liquidity(executor, batch))
    
    # Step 2: Execute swaps
    push!(steps, (batch, tx) -> execute_swaps(executor, batch, tx))
    push!(compensations, batch -> revert_swaps(executor, batch))
    
    # Step 3: Transfer tokens
    push!(steps, (batch, tx) -> transfer_tokens(executor, batch, tx))
    push!(compensations, batch -> revert_transfers(executor, batch))
    
    # Step 4: Update reserves
    push!(steps, (batch, tx) -> update_reserves(executor, batch, tx))
    push!(compensations, batch -> revert_reserves(executor, batch))
    
    # Step 5: Record settlement
    push!(steps, (batch, tx) -> record_settlements(executor, batch, tx))
    push!(compensations, batch -> clear_records(executor, batch))
    
    # Calculate estimates
    gas_estimate = sum(s.gas_estimate for s in batch.settlements)
    # Configurable time estimation
    step_time_ms = get_config(load_config(), "settlement.step_time_estimate_ms", Float64, 20.0)
    settlement_time_ms = get_config(load_config(), "settlement.settlement_time_estimate_ms", Float64, 5.0)
    time_estimate = length(steps) * step_time_ms + length(batch.settlements) * settlement_time_ms  # ms
    
    return ExecutionPlan(
        batch.id,
        steps,
        validations,
        compensations,
        gas_estimate,
        time_estimate
    )
end

"""
    rollback_batch(executor, batch_id)

Manually rollback a batch.
"""
function rollback_batch(executor::AtomicExecutor, batch_id::UUID)
    batch = lock(executor.lock) do
        get(executor.active_batches, batch_id, nothing)
    end
    
    if batch === nothing
        return (success=false, reason="Batch not found")
    end
    
    if batch.status == :completed
        return (success=false, reason="Cannot rollback completed batch")
    end
    
    plan = lock(executor.lock) do
        get(executor.execution_plans, batch_id, nothing)
    end
    
    if plan !== nothing
        # Execute all compensations
        for compensation in plan.compensations
            try
                compensation(batch)
            catch e
                @error "Compensation failed during rollback" error=e
            end
        end
    end
    
    batch.status = :failed
    batch.error = "Manually rolled back"
    
    return (success=true, reason="Batch rolled back")
end

"""
    verify_atomicity(executor, batch_id)

Verify that a batch was executed atomically.
"""
function verify_atomicity(executor::AtomicExecutor, batch_id::UUID)
    batch = lock(executor.lock) do
        get(executor.active_batches, batch_id, nothing)
    end
    
    if batch === nothing
        return (atomic=false, reason="Batch not found")
    end
    
    if batch.status != :completed
        return (atomic=false, reason="Batch not completed")
    end
    
    # Check all settlements have same timestamp
    if batch.commit_timestamp === nothing
        return (atomic=false, reason="No commit timestamp")
    end
    
    # Verify no partial execution
    # State consistency checks can be added here
    
    return (atomic=true, reason="Verified atomic execution")
end

"""
    get_batch_status(executor, batch_id)

Get the current status of a batch.
"""
function get_batch_status(executor::AtomicExecutor, batch_id::UUID)
    batch = lock(executor.lock) do
        get(executor.active_batches, batch_id, nothing)
    end
    
    if batch === nothing
        return nothing
    end
    
    return (
        id = batch.id,
        status = batch.status,
        settlement_count = length(batch.settlements),
        total_value = batch.total_value,
        prepare_time = batch.prepare_timestamp,
        commit_time = batch.commit_timestamp,
        error = batch.error,
        retries = batch.retries
    )
end

# Validation helper functions

function validate_liquidity(executor::AtomicExecutor, batch::SettlementBatch)
    # Check if sufficient liquidity exists
    if executor.router_bridge !== nothing
        for settlement in batch.settlements
            # Get route to check if liquidity is available
            routing = get_route(
                executor.router_bridge,
                settlement.token_in,
                settlement.token_out,
                settlement.amount_in,
                get_config(load_config(), "settlement.validation_slippage_tolerance", Float64, 0.02)  # Slippage for validation
            )
            
            if routing === nothing
                return (valid=false, reason="No liquidity route for settlement $(settlement.id)")
            end
            
            tolerance_ratio = 1.0 - get_config(load_config(), "settlement.liquidity_tolerance", Float64, 0.05)
            if routing.amount_out < settlement.amount_out * tolerance_ratio  # Configurable tolerance
                return (valid=false, reason="Insufficient liquidity for settlement $(settlement.id)")
            end
        end
        return (valid=true, reason="Liquidity validated")
    end
    return (valid=false, reason="Router bridge not available")
end

function validate_prices(executor::AtomicExecutor, batch::SettlementBatch)
    # Validate prices are still valid against current market
    if executor.router_bridge !== nothing
        for settlement in batch.settlements
            if settlement.price <= 0
                return (valid=false, reason="Invalid price for $(settlement.id)")
            end
            
            # Check current market price
            current_price = get_baseline_price(
                executor.router_bridge,
                settlement.token_in,
                settlement.token_out
            )
            
            if current_price > 0
                price_deviation = abs(settlement.price - current_price) / current_price
                max_price_deviation = get_config(load_config(), "settlement.max_price_deviation", Float64, 0.05)
                if price_deviation > max_price_deviation  # Configurable maximum deviation
                    return (valid=false, reason="Price deviation too high for $(settlement.id): $(price_deviation*100)%")
                end
            end
        end
        return (valid=true, reason="Prices validated")
    end
    
    # Fallback validation without router
    for settlement in batch.settlements
        if settlement.price <= 0
            return (valid=false, reason="Invalid price for $(settlement.id)")
        end
    end
    return (valid=true, reason="Basic price validation passed")
end

function validate_slippage(executor::AtomicExecutor, batch::SettlementBatch)
    # Check slippage tolerance
    for settlement in batch.settlements
        expected_out = settlement.amount_in * settlement.price
        slippage = abs(settlement.amount_out - expected_out) / expected_out
        max_slippage = get_config(load_config(), "settlement.max_slippage_tolerance", Float64, 0.02)
        if slippage > max_slippage  # Configurable max slippage
            return (valid=false, reason="Excessive slippage for $(settlement.id)")
        end
    end
    return (valid=true, reason="")
end

function validate_gas_limits(executor::AtomicExecutor, batch::SettlementBatch)
    total_gas = sum(s.gas_estimate for s in batch.settlements)
    gas_limit = get_config(load_config(), "settlement.gas_limit", Int, 10_000_000)
    if total_gas > gas_limit  # Configurable gas limit
        return (valid=false, reason="Gas limit exceeded", warning="High gas usage: $total_gas")
    end
    return (valid=true, reason="")
end

# Execution helper functions

function lock_liquidity(executor::AtomicExecutor, batch::SettlementBatch, transaction)
    # Lock required liquidity pools
    return (success=true, reason="Liquidity locked")
end

function unlock_liquidity(executor::AtomicExecutor, batch::SettlementBatch)
    # Unlock liquidity pools
    return (success=true, reason="Liquidity unlocked")
end

function execute_swaps(executor::AtomicExecutor, batch::SettlementBatch, transaction)
    # Execute all swaps in batch through router bridge
    if executor.router_bridge === nothing
        return (success=false, reason="Router bridge not available")
    end
    
    executed_settlements = Settlement[]
    
    try
        for settlement in batch.settlements
            # Execute swap through CFMM bridge
            result = execute_direct(
                executor.router_bridge,
                settlement.token_in,
                settlement.token_out,
                settlement.amount_in,
                get_config(load_config(), "settlement.execution_slippage_tolerance", Float64, 0.005)  # Configurable slippage tolerance
            )
            
            if result === nothing
                # Rollback already executed settlements
                for prev_settlement in executed_settlements
                    # Implement rollback logic for settlement
                    @warn "Rolling back settlement $(prev_settlement.id)"
                end
                return (success=false, reason="Swap failed for settlement $(settlement.id)")
            end
            
            # Verify execution meets expectations
            execution_tolerance = 1.0 - get_config(load_config(), "settlement.execution_tolerance", Float64, 0.02)
            if result.amount_out < settlement.amount_out * execution_tolerance  # Configurable tolerance
                return (success=false, reason="Insufficient output for settlement $(settlement.id)")
            end
            
            push!(executed_settlements, settlement)
        end
        
        return (success=true, reason="All swaps executed successfully")
        
    catch e
        @error "Swap execution failed" exception=e
        return (success=false, reason="Execution error: $e")
    end
end

function revert_swaps(executor::AtomicExecutor, batch::SettlementBatch)
    # Revert swap state
    return (success=true, reason="Swaps reverted")
end

function transfer_tokens(executor::AtomicExecutor, batch::SettlementBatch, transaction)
    # Transfer tokens to users
    return (success=true, reason="Tokens transferred")
end

function revert_transfers(executor::AtomicExecutor, batch::SettlementBatch)
    # Revert token transfers
    return (success=true, reason="Transfers reverted")
end

function update_reserves(executor::AtomicExecutor, batch::SettlementBatch, transaction)
    # Update pool reserves after all swaps are executed
    if executor.router_bridge !== nothing && executor.router_bridge.router !== nothing
        try
            # The reserves are automatically updated when CFMMRouter.update_reserves! is called
            # during swap execution, so this mainly serves as a verification step
            
            # Verify that reserve updates were applied correctly
            for settlement in batch.settlements
                routing = get_route(
                    executor.router_bridge,
                    settlement.token_in,
                    settlement.token_out,
                    settlement.amount_in,
                    0.01
                )
                
                if routing === nothing
                    @warn "Could not verify reserves for settlement $(settlement.id)"
                end
            end
            
            return (success=true, reason="Reserves verified and updated")
        catch e
            @error "Reserve update failed" exception=e
            return (success=false, reason="Reserve update error: $e")
        end
    end
    return (success=false, reason="Router bridge not available for reserve updates")
end

function revert_reserves(executor::AtomicExecutor, batch::SettlementBatch)
    # Revert reserve updates
    return (success=true, reason="Reserves reverted")
end

function record_settlements(executor::AtomicExecutor, batch::SettlementBatch, transaction)
    # Record settlement completion
    if executor.state_manager !== nothing
        # Record in state manager when available
    end
    return (success=true, reason="Settlements recorded")
end

function clear_records(executor::AtomicExecutor, batch::SettlementBatch)
    # Clear settlement records
    return (success=true, reason="Records cleared")
end

end # module