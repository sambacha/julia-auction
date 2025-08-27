module CircuitBreaker

using Base.Threads: Atomic, SpinLock
using Dates
using Logging
# Import configuration manager
include("../../config/ConfigManager.jl")
using .ConfigManager: load_config, get_config, AuctionConfig
export ProductionCircuitBreaker, CircuitBreakerConfig, CircuitState, ConfigValue
export create_circuit_breaker, execute_with_circuit_breaker, get_circuit_state
export reset_circuit_breaker, configure_circuit_breaker, get_circuit_metrics

"""
Circuit breaker states for production-ready failure handling.
"""
@enum CircuitState begin
    CLOSED       # Normal operation
    OPEN         # Circuit tripped, rejecting requests
    HALF_OPEN    # Testing recovery
end

"""
Union type for configuration values - replaces Any type for type safety.
"""
const ConfigValue = Union{Int, Float64, Bool, String}

"""
Configuration for production circuit breaker.
"""
struct CircuitBreakerConfig
    failure_threshold::Int          # Number of failures to trip circuit
    recovery_threshold::Int         # Successes needed in half-open to close
    timeout_ms::Float64            # Time to wait before trying half-open
    slow_call_threshold_ms::Float64 # Calls slower than this count as failures
    half_open_max_calls::Int       # Max calls allowed in half-open state
    volume_threshold::Int          # Minimum calls before circuit can trip
    error_percentage_threshold::Float64  # Percentage of errors to trip circuit
    monitoring_window_ms::Float64  # Sliding window for error calculation
end

"""
Production-grade circuit breaker with comprehensive monitoring.
"""
mutable struct ProductionCircuitBreaker
    config::CircuitBreakerConfig
    state::Atomic{CircuitState}
    failure_count::Atomic{Int}
    success_count::Atomic{Int}
    half_open_calls::Atomic{Int}
    last_failure_time::Atomic{Float64}
    last_state_change::Atomic{Float64}
    total_calls::Atomic{Int}
    total_failures::Atomic{Int}
    recent_calls::Vector{Tuple{Float64, Bool}}  # (timestamp, success)
    lock::SpinLock
    name::String
end

"""
    create_circuit_breaker(name::String; kwargs...)

Create a production-ready circuit breaker with optimal defaults.
"""
function create_circuit_breaker(name::String;
    failure_threshold::Union{Int, Nothing}=nothing,
    recovery_threshold::Union{Int, Nothing}=nothing,
    timeout_ms::Union{Float64, Nothing}=nothing,
    slow_call_threshold_ms::Union{Float64, Nothing}=nothing,
    half_open_max_calls::Union{Int, Nothing}=nothing,
    volume_threshold::Union{Int, Nothing}=nothing,
    error_percentage_threshold::Union{Float64, Nothing}=nothing,
    monitoring_window_ms::Union{Float64, Nothing}=nothing,
    config::AuctionConfig=load_config())
    
    # Use provided values or load from config
    final_failure_threshold = failure_threshold !== nothing ? failure_threshold : get_config(config, "circuit_breaker.failure_threshold", Int)
    final_recovery_threshold = recovery_threshold !== nothing ? recovery_threshold : get_config(config, "circuit_breaker.recovery_threshold", Int)
    final_timeout_ms = timeout_ms !== nothing ? timeout_ms : get_config(config, "circuit_breaker.timeout_ms", Float64)
    final_slow_call_threshold_ms = slow_call_threshold_ms !== nothing ? slow_call_threshold_ms : get_config(config, "circuit_breaker.slow_call_threshold_ms", Float64)
    final_half_open_max_calls = half_open_max_calls !== nothing ? half_open_max_calls : get_config(config, "circuit_breaker.half_open_max_calls", Int)
    final_volume_threshold = volume_threshold !== nothing ? volume_threshold : get_config(config, "circuit_breaker.volume_threshold", Int)
    final_error_percentage_threshold = error_percentage_threshold !== nothing ? error_percentage_threshold : get_config(config, "circuit_breaker.error_percentage_threshold", Float64)
    final_monitoring_window_ms = monitoring_window_ms !== nothing ? monitoring_window_ms : get_config(config, "circuit_breaker.monitoring_window_ms", Float64)
    
    cb_config = CircuitBreakerConfig(
        final_failure_threshold,
        final_recovery_threshold,
        final_timeout_ms,
        final_slow_call_threshold_ms,
        final_half_open_max_calls,
        final_volume_threshold,
        final_error_percentage_threshold,
        final_monitoring_window_ms
    )
    
    return ProductionCircuitBreaker(
        cb_config,
        Atomic{CircuitState}(CLOSED),
        Atomic{Int}(0),
        Atomic{Int}(0),
        Atomic{Int}(0),
        Atomic{Float64}(0.0),
        Atomic{Float64}(time() * 1000),
        Atomic{Int}(0),
        Atomic{Int}(0),
        Tuple{Float64, Bool}[],
        SpinLock(),
        name
    )
end

"""
    execute_with_circuit_breaker(f, circuit_breaker, fallback=nothing)

Execute function with circuit breaker protection. Returns (result, executed, state).
"""
function execute_with_circuit_breaker(f::Function, 
                                     cb::ProductionCircuitBreaker,
                                     fallback::Union{Function, Nothing}=nothing)
    current_time = time() * 1000
    
    # Check if circuit allows execution
    can_execute, current_state = should_execute(cb, current_time)
    
    if !can_execute
        @debug "Circuit breaker $(cb.name) rejecting call" state=current_state
        
        if fallback !== nothing
            try
                result = fallback()
                return (result, false, current_state)
            catch e
                @error "Fallback failed for circuit breaker $(cb.name)" exception=e
                rethrow(e)
            end
        else
            throw(CircuitBreakerOpenException("Circuit breaker $(cb.name) is open"))
        end
    end
    
    # Execute the function with timing
    start_time = time() * 1000
    success = false
    result = nothing
    
    try
        result = f()
        execution_time = time() * 1000 - start_time
        
        # Determine if call was successful based on timing and result
        success = execution_time < cb.config.slow_call_threshold_ms
        
        record_execution_result(cb, current_time, execution_time, success)
        return (result, true, get_circuit_state(cb))
        
    catch e
        execution_time = time() * 1000 - start_time
        record_execution_result(cb, current_time, execution_time, false)
        rethrow(e)
    end
end

"""
Exception thrown when circuit breaker is open.
"""
struct CircuitBreakerOpenException <: Exception
    message::String
end

"""
Check if circuit breaker should allow execution.
"""
function should_execute(cb::ProductionCircuitBreaker, current_time::Float64)
    current_state = cb.state[]
    
    if current_state == CLOSED
        return (true, CLOSED)
    elseif current_state == OPEN
        # Check if timeout has elapsed for half-open transition
        if current_time - cb.last_failure_time[] >= cb.config.timeout_ms
            # Attempt transition to half-open
            if cb.state[] == OPEN  # Double-check with atomic
                cb.state[] = HALF_OPEN
                cb.half_open_calls[] = 0
                cb.success_count[] = 0
                cb.last_state_change[] = current_time
                @info "Circuit breaker $(cb.name) transitioning to HALF_OPEN"
                return (true, HALF_OPEN)
            end
        end
        return (false, OPEN)
    else # HALF_OPEN
        # Allow limited calls in half-open state
        if cb.half_open_calls[] < cb.config.half_open_max_calls
            return (true, HALF_OPEN)
        else
            return (false, HALF_OPEN)
        end
    end
end

"""
Record the result of an execution attempt.
"""
function record_execution_result(cb::ProductionCircuitBreaker, 
                                current_time::Float64,
                                execution_time::Float64, 
                                success::Bool)
    
    lock(cb.lock) do
        # Update counters
        atomic_add!(cb.total_calls, 1)
        if !success
            atomic_add!(cb.total_failures, 1)
            atomic_add!(cb.failure_count, 1)
            cb.last_failure_time[] = current_time
        end
        
        # Add to recent calls for sliding window analysis
        push!(cb.recent_calls, (current_time, success))
        cleanup_old_calls!(cb, current_time)
        
        current_state = cb.state[]
        
        if current_state == HALF_OPEN
            atomic_add!(cb.half_open_calls, 1)
            
            if success
                atomic_add!(cb.success_count, 1)
                
                # Check if we have enough successes to close circuit
                if cb.success_count[] >= cb.config.recovery_threshold
                    cb.state[] = CLOSED
                    cb.failure_count[] = 0
                    cb.success_count[] = 0
                    cb.half_open_calls[] = 0
                    cb.last_state_change[] = current_time
                    @info "Circuit breaker $(cb.name) recovered to CLOSED"
                end
            else
                # Failure in half-open, back to open
                cb.state[] = OPEN
                cb.last_state_change[] = current_time
                @warn "Circuit breaker $(cb.name) failed during recovery, back to OPEN"
            end
            
        elseif current_state == CLOSED
            # Check if we should trip the circuit
            should_trip = should_trip_circuit(cb, current_time)
            
            if should_trip
                cb.state[] = OPEN
                cb.last_state_change[] = current_time
                @error "Circuit breaker $(cb.name) tripped to OPEN" 
                    failure_count=cb.failure_count[] 
                    total_calls=cb.total_calls[]
                    error_rate=calculate_error_rate(cb, current_time)
            else
                # Reset failure count on successful operations
                if success && cb.failure_count[] > 0
                    atomic_sub!(cb.failure_count, max(1, div(cb.failure_count[], 2)))
                end
            end
        end
    end
end

"""
Determine if circuit should be tripped based on failure patterns.
"""
function should_trip_circuit(cb::ProductionCircuitBreaker, current_time::Float64)
    # Must have minimum volume of calls
    if cb.total_calls[] < cb.config.volume_threshold
        return false
    end
    
    # Check consecutive failures
    if cb.failure_count[] >= cb.config.failure_threshold
        return true
    end
    
    # Check error percentage in sliding window
    error_rate = calculate_error_rate(cb, current_time)
    if error_rate >= cb.config.error_percentage_threshold
        return true
    end
    
    return false
end

"""
Calculate error rate within the monitoring window.
"""
function calculate_error_rate(cb::ProductionCircuitBreaker, current_time::Float64)
    window_start = current_time - cb.config.monitoring_window_ms
    
    calls_in_window = filter(call -> call[1] >= window_start, cb.recent_calls)
    
    if isempty(calls_in_window)
        return 0.0
    end
    
    failures = count(call -> !call[2], calls_in_window)
    return (failures / length(calls_in_window)) * 100.0
end

"""
Clean up old call records outside monitoring window.
"""
function cleanup_old_calls!(cb::ProductionCircuitBreaker, current_time::Float64)
    cutoff_time = current_time - cb.config.monitoring_window_ms
    
    # Remove calls older than monitoring window
    filter!(call -> call[1] >= cutoff_time, cb.recent_calls)
    
    # Limit memory usage - make this configurable
    max_records = get_config(load_config(), "resources.max_records", Int, 1000)
    if length(cb.recent_calls) > max_records
        cb.recent_calls = cb.recent_calls[(end-max_records+1):end]
    end
end

"""
Get current circuit breaker state and metrics.
"""
function get_circuit_state(cb::ProductionCircuitBreaker)
    current_time = time() * 1000
    
    lock(cb.lock) do
        error_rate = calculate_error_rate(cb, current_time)
        calls_in_window = count(call -> call[1] >= current_time - cb.config.monitoring_window_ms, 
                               cb.recent_calls)
        
        return (
            name = cb.name,
            state = cb.state[],
            failure_count = cb.failure_count[],
            success_count = cb.success_count[],
            total_calls = cb.total_calls[],
            total_failures = cb.total_failures[],
            error_rate_percent = error_rate,
            calls_in_window = calls_in_window,
            time_since_state_change_ms = current_time - cb.last_state_change[],
            half_open_calls = cb.half_open_calls[]
        )
    end
end

"""
Get comprehensive circuit breaker metrics for monitoring.
"""
function get_circuit_metrics(cb::ProductionCircuitBreaker)
    current_time = time() * 1000
    state_info = get_circuit_state(cb)
    
    lock(cb.lock) do
        # Calculate additional metrics
        uptime_ms = current_time - cb.last_state_change[]
        success_rate = cb.total_calls[] > 0 ? 
            ((cb.total_calls[] - cb.total_failures[]) / cb.total_calls[] * 100) : 100.0
        
        return merge(state_info, (
            success_rate_percent = success_rate,
            uptime_ms = uptime_ms,
            config = cb.config,
            recent_calls_count = length(cb.recent_calls)
        ))
    end
end

"""
Reset circuit breaker to closed state.
"""
function reset_circuit_breaker(cb::ProductionCircuitBreaker)
    lock(cb.lock) do
        cb.state[] = CLOSED
        cb.failure_count[] = 0
        cb.success_count[] = 0
        cb.half_open_calls[] = 0
        cb.total_calls[] = 0
        cb.total_failures[] = 0
        cb.last_state_change[] = time() * 1000
        empty!(cb.recent_calls)
        
        @info "Circuit breaker $(cb.name) manually reset to CLOSED"
    end
end

"""
Configure circuit breaker parameters at runtime.
"""
function configure_circuit_breaker(cb::ProductionCircuitBreaker; kwargs...)
    lock(cb.lock) do
        config_dict = Dict{Symbol, ConfigValue}()
        
        for (key, value) in kwargs
            if hasfield(CircuitBreakerConfig, key)
                config_dict[key] = value
            end
        end
        
        if !isempty(config_dict)
            # Create new config with updated values
            old_config = cb.config
            new_config = CircuitBreakerConfig(
                get(config_dict, :failure_threshold, old_config.failure_threshold),
                get(config_dict, :recovery_threshold, old_config.recovery_threshold),
                get(config_dict, :timeout_ms, old_config.timeout_ms),
                get(config_dict, :slow_call_threshold_ms, old_config.slow_call_threshold_ms),
                get(config_dict, :half_open_max_calls, old_config.half_open_max_calls),
                get(config_dict, :volume_threshold, old_config.volume_threshold),
                get(config_dict, :error_percentage_threshold, old_config.error_percentage_threshold),
                get(config_dict, :monitoring_window_ms, old_config.monitoring_window_ms)
            )
            
            cb.config = new_config
            @info "Circuit breaker $(cb.name) configuration updated" changes=config_dict
        end
    end
end

end # module