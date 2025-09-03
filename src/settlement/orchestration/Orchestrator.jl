"""
    Orchestrator

Main orchestration logic for CFMM settlement with two-phase commit protocol.
"""
module Orchestrator

using Base.Threads
using Dates
using UUIDs

using ..SettlementTypes
using ..MEVProtection
using ..RouteOptimizer
using ..RouteCache
using ..AtomicExecution
using ..SettlementMonitor

export SettlementOrchestrator, process_settlement, emergency_halt, resume_operations

"""
    SettlementOrchestrator

Main orchestrator for settlement operations.
"""
mutable struct SettlementOrchestrator
    config::SettlementConfig
    route_optimizer::RouteOptimizer.Optimizer
    mev_protector::MEVProtection.Protector
    cache::RouteCache.Cache
    monitor::SettlementMonitor.Monitor
    executor::AtomicExecution.Executor

    # State management
    circuit_breaker_state::Atomic{CircuitBreakerState}
    total_settlements::Atomic{Int}
    failed_settlements::Atomic{Int}
    last_failure::DateTime

    # Performance tracking
    latency_buffer::CircularBuffer{Float64}
    success_rate_buffer::CircularBuffer{Bool}

    # Lock for critical sections
    state_lock::ReentrantLock
end

"""
    SettlementOrchestrator(config::SettlementConfig)

Create a new settlement orchestrator with the given configuration.
"""
function SettlementOrchestrator(config::SettlementConfig)
    return SettlementOrchestrator(
        config,
        RouteOptimizer.Optimizer(config.routing),
        MEVProtection.Protector(config.mev_protection),
        RouteCache.Cache(config.cache),
        SettlementMonitor.Monitor(config.monitoring),
        AtomicExecution.Executor(config.execution),
        Atomic{CircuitBreakerState}(CLOSED),
        Atomic{Int}(0),
        Atomic{Int}(0),
        DateTime(0),
        CircularBuffer{Float64}(1000),
        CircularBuffer{Bool}(1000),
        ReentrantLock(),
    )
end

"""
    process_settlement(orchestrator::SettlementOrchestrator,
                      transaction::SettlementTransaction) -> SettlementResult

Process a settlement transaction through the complete pipeline.
"""
function process_settlement(
    orchestrator::SettlementOrchestrator,
    transaction::SettlementTransaction{T},
)::SettlementResult{T} where {T<:Real}
    start_time = time_ns()

    # Check circuit breaker
    if orchestrator.circuit_breaker_state[] == OPEN
        return _create_error_result(transaction, "Circuit breaker is open")
    end

    try
        # Phase 1: Preparation
        preparation_result = _prepare_settlement(orchestrator, transaction)
        if !preparation_result.success
            return preparation_result
        end

        # Phase 2: Execution
        execution_result = _execute_settlement(orchestrator, transaction, preparation_result)

        # Update metrics
        elapsed_ms = (time_ns() - start_time) / 1_000_000
        _update_metrics(orchestrator, execution_result.success, elapsed_ms)

        return execution_result

    catch e
        _handle_settlement_error(orchestrator, e)
        return _create_error_result(transaction, string(e))
    end
end

"""
    _prepare_settlement(orchestrator, transaction)

Phase 1: Prepare settlement with validation, routing, and MEV protection.
"""
function _prepare_settlement(
    orchestrator::SettlementOrchestrator,
    transaction::SettlementTransaction{T},
) where {T<:Real}
    routing_start = time_ns()

    # Step 1: Validate transaction
    validation_error = _validate_transaction(transaction)
    if !isnothing(validation_error)
        return _create_error_result(transaction, validation_error)
    end

    # Step 2: Check cache for routes
    cache_key = RouteCache.generate_key(transaction)
    cached_routes = RouteCache.get(orchestrator.cache, cache_key)

    routes = if !isnothing(cached_routes)
        cached_routes
    else
        # Step 3: Calculate optimal routes
        routes = RouteOptimizer.find_optimal_routes(orchestrator.route_optimizer, transaction)

        # Cache the routes
        RouteCache.put!(orchestrator.cache, cache_key, routes)
        routes
    end

    routing_latency = (time_ns() - routing_start) / 1_000_000

    # Step 4: Assess MEV risk and apply protection
    mev_risk = MEVProtection.assess_risk(orchestrator.mev_protector, transaction)
    protection_strategy = MEVProtection.select_protection(orchestrator.mev_protector, mev_risk)

    protected_routes = MEVProtection.apply_protection(orchestrator.mev_protector, routes, protection_strategy)

    return (
        success = true,
        routes = protected_routes,
        mev_risk = mev_risk,
        protection_strategy = protection_strategy,
        routing_latency = routing_latency,
    )
end

"""
    _execute_settlement(orchestrator, transaction, preparation_result)

Phase 2: Execute settlement with atomic guarantees.
"""
function _execute_settlement(
    orchestrator::SettlementOrchestrator,
    transaction::SettlementTransaction{T},
    preparation_result,
) where {T<:Real}
    execution_start = time_ns()

    # Two-phase commit protocol
    commit_coordinator = AtomicExecution.create_coordinator(orchestrator.executor, transaction)

    # Phase 2a: Prepare all participants
    prepare_results = AtomicExecution.prepare_phase(commit_coordinator, preparation_result.routes)

    if !all(r -> r.vote == :commit, prepare_results)
        # Abort if any participant votes no
        AtomicExecution.abort_phase(commit_coordinator)
        return _create_error_result(transaction, "Two-phase commit aborted")
    end

    # Phase 2b: Commit all participants
    commit_results = AtomicExecution.commit_phase(commit_coordinator)

    execution_latency = (time_ns() - execution_start) / 1_000_000

    # Create receipt
    receipt = if all(r -> r.success, commit_results)
        _create_receipt(transaction, commit_results)
    else
        nothing
    end

    # Create metrics
    metrics = SettlementMetrics(
        routing_latency_ms = preparation_result.routing_latency,
        execution_latency_ms = execution_latency,
        total_latency_ms = preparation_result.routing_latency + execution_latency,
        pools_queried = length(preparation_result.routes),
        routes_evaluated = length(preparation_result.routes),
        cache_hit = !isnothing(cached_routes),
        mev_protection_used = preparation_result.protection_strategy != NO_PROTECTION,
    )

    return SettlementResult{T}(
        transaction = transaction,
        receipt = receipt,
        metrics = metrics,
        execution_paths = preparation_result.routes,
        timestamp = now(),
        success = !isnothing(receipt),
        error = isnothing(receipt) ? "Execution failed" : nothing,
    )
end

"""
    _validate_transaction(transaction::SettlementTransaction)

Validate a settlement transaction.
"""
function _validate_transaction(transaction::SettlementTransaction)::Union{String,Nothing}
    # Check deadline
    if transaction.deadline < now()
        return "Transaction deadline has passed"
    end

    # Check amount
    if transaction.amount <= 0
        return "Invalid transaction amount"
    end

    # Check slippage
    if transaction.max_slippage < 0 || transaction.max_slippage > 1
        return "Invalid slippage tolerance"
    end

    return nothing
end

"""
    _update_metrics(orchestrator, success, latency_ms)

Update orchestrator metrics after settlement.
"""
function _update_metrics(orchestrator::SettlementOrchestrator, success::Bool, latency_ms::Float64)
    lock(orchestrator.state_lock) do
        # Update counters
        atomic_add!(orchestrator.total_settlements, 1)
        if !success
            atomic_add!(orchestrator.failed_settlements, 1)
            orchestrator.last_failure = now()
        end

        # Update buffers
        push!(orchestrator.latency_buffer, latency_ms)
        push!(orchestrator.success_rate_buffer, success)

        # Check circuit breaker conditions
        _check_circuit_breaker(orchestrator)
    end

    # Send metrics to monitor
    SettlementMonitor.record_settlement(orchestrator.monitor, success, latency_ms)
end

"""
    _check_circuit_breaker(orchestrator)

Check and update circuit breaker state based on failure rate.
"""
function _check_circuit_breaker(orchestrator::SettlementOrchestrator)
    # Calculate recent failure rate
    recent_results = collect(orchestrator.success_rate_buffer)
    if length(recent_results) >= 10
        failure_rate = 1.0 - mean(recent_results[(end-9):end])

        current_state = orchestrator.circuit_breaker_state[]

        if current_state == CLOSED && failure_rate > 0.5
            # Trip circuit breaker
            atomic_xchg!(orchestrator.circuit_breaker_state, OPEN)
            @warn "Circuit breaker tripped" failure_rate

        elseif current_state == OPEN
            # Check if we should try half-open
            time_since_failure = now() - orchestrator.last_failure
            if time_since_failure > Second(30)
                atomic_xchg!(orchestrator.circuit_breaker_state, HALF_OPEN)
            end

        elseif current_state == HALF_OPEN && failure_rate < 0.1
            # Resume normal operation
            atomic_xchg!(orchestrator.circuit_breaker_state, CLOSED)
            @info "Circuit breaker reset"
        end
    end
end

"""
    emergency_halt(orchestrator::SettlementOrchestrator)

Emergency halt of all settlement operations.
"""
function emergency_halt(orchestrator::SettlementOrchestrator)
    lock(orchestrator.state_lock) do
        atomic_xchg!(orchestrator.circuit_breaker_state, OPEN)
        @error "Emergency halt activated"

        # Notify monitor
        SettlementMonitor.trigger_alert(orchestrator.monitor, "EMERGENCY_HALT", "Manual emergency halt activated")
    end
end

"""
    resume_operations(orchestrator::SettlementOrchestrator)

Resume settlement operations after emergency halt.
"""
function resume_operations(orchestrator::SettlementOrchestrator)
    lock(orchestrator.state_lock) do
        atomic_xchg!(orchestrator.circuit_breaker_state, HALF_OPEN)
        @info "Resuming operations in half-open mode"

        # Clear failure buffers
        empty!(orchestrator.success_rate_buffer)
    end
end

"""
    _create_error_result(transaction, error_msg)

Create an error result for a failed settlement.
"""
function _create_error_result(
    transaction::SettlementTransaction{T},
    error_msg::String,
)::SettlementResult{T} where {T<:Real}
    return SettlementResult{T}(
        transaction = transaction,
        receipt = nothing,
        metrics = SettlementMetrics(
            routing_latency_ms = 0.0,
            execution_latency_ms = 0.0,
            total_latency_ms = 0.0,
            pools_queried = 0,
            routes_evaluated = 0,
            cache_hit = false,
            mev_protection_used = false,
        ),
        execution_paths = Vector{ExecutionPath{T}}(),
        timestamp = now(),
        success = false,
        error = error_msg,
    )
end

"""
    _create_receipt(transaction, commit_results)

Create a settlement receipt from commit results.
"""
function _create_receipt(transaction::SettlementTransaction{T}, commit_results)::SettlementReceipt{T} where {T<:Real}

    # Aggregate results from all commits
    total_gas = sum(r -> r.gas_used, commit_results)
    total_received = sum(r -> r.amount_out, commit_results)
    total_fees = sum(r -> r.protocol_fee, commit_results)

    effective_price = if transaction.is_buy
        transaction.amount / total_received
    else
        total_received / transaction.amount
    end

    return SettlementReceipt{T}(
        transaction_hash = string(uuid4()),
        block_number = 0,  # Would be from blockchain
        gas_used = total_gas,
        effective_price = effective_price,
        amount_received = total_received,
        protocol_fees = total_fees,
        mev_protection_cost = T(0),  # Calculate from protection strategy
        timestamp = now(),
    )
end

"""
    _handle_settlement_error(orchestrator, error)

Handle and log settlement errors.
"""
function _handle_settlement_error(orchestrator::SettlementOrchestrator, error)
    @error "Settlement failed" exception = error

    # Record error in monitor
    SettlementMonitor.record_error(orchestrator.monitor, string(error), stacktrace(catch_backtrace()))
end

end # module Orchestrator
