module LatencyMonitor

using Base.Threads: Atomic, SpinLock
using Statistics
using Dates

export LatencyTracker, CircuitBreaker, AdaptiveBypass, LatencyMetrics
export record_latency!, check_circuit_breaker, should_bypass
export get_latency_stats, reset_metrics, configure_thresholds

# Latency metrics with microsecond precision
mutable struct LatencyMetrics
    min::Float64  # microseconds
    max::Float64
    mean::Float64
    median::Float64
    p95::Float64
    p99::Float64
    std_dev::Float64
    count::Int
    sum::Float64
    sum_squared::Float64
end

# Circuit breaker for high latency protection
mutable struct CircuitBreaker
    state::Atomic{Symbol}  # :closed, :open, :half_open
    failure_count::Atomic{Int}
    success_count::Atomic{Int}
    last_failure_time::Atomic{Float64}
    last_state_change::Atomic{Float64}
    threshold_ms::Float64
    failure_threshold::Int
    success_threshold::Int
    timeout_ms::Float64
    half_open_requests::Int
end

# Adaptive bypass logic
mutable struct AdaptiveBypass
    enabled::Atomic{Bool}
    bypass_threshold_ms::Float64
    recovery_threshold_ms::Float64
    consecutive_slow::Atomic{Int}
    consecutive_fast::Atomic{Int}
    slow_threshold::Int
    fast_threshold::Int
    bypass_rate::Atomic{Float64}
end

# Main latency tracker
mutable struct LatencyTracker
    components::Dict{Symbol,Vector{Float64}}  # Component-wise latencies
    metrics::Dict{Symbol,LatencyMetrics}
    circuit_breakers::Dict{Symbol,CircuitBreaker}
    bypass_logic::Dict{Symbol,AdaptiveBypass}
    global_metrics::LatencyMetrics
    lock::SpinLock
    max_samples::Int
    sample_window_ms::Float64
    last_cleanup::Float64
end

"""
    LatencyTracker(; kwargs...)

Create a latency tracker with microsecond precision and circuit breakers.
"""
function LatencyTracker(;
    max_samples::Int=10000,
    sample_window_ms::Float64=60000.0,  # 1 minute window
    default_threshold_ms::Float64=100.0,
    default_bypass_threshold_ms::Float64=50.0)
    
    return LatencyTracker(
        Dict{Symbol,Vector{Float64}}(),
        Dict{Symbol,LatencyMetrics}(),
        Dict{Symbol,CircuitBreaker}(),
        Dict{Symbol,AdaptiveBypass}(),
        create_empty_metrics(),
        SpinLock(),
        max_samples,
        sample_window_ms,
        time() * 1000
    )
end

"""
    record_latency!(tracker, component, latency_us; kwargs...)

Record latency measurement in microseconds for a component.
"""
function record_latency!(tracker::LatencyTracker, 
                        component::Symbol, 
                        latency_us::Float64;
                        check_circuit::Bool=true)
    
    current_time_ms = time() * 1000
    
    lock(tracker.lock) do
        # Initialize component if needed
        if !haskey(tracker.components, component)
            tracker.components[component] = Float64[]
            tracker.metrics[component] = create_empty_metrics()
            
            if check_circuit
                tracker.circuit_breakers[component] = create_circuit_breaker()
                tracker.bypass_logic[component] = create_adaptive_bypass()
            end
        end
        
        # Add sample
        push!(tracker.components[component], latency_us)
        
        # Update metrics
        update_metrics!(tracker.metrics[component], latency_us)
        update_metrics!(tracker.global_metrics, latency_us)
        
        # Check circuit breaker
        if check_circuit && haskey(tracker.circuit_breakers, component)
            latency_ms = latency_us / 1000.0
            update_circuit_breaker!(tracker.circuit_breakers[component], latency_ms)
            update_bypass_logic!(tracker.bypass_logic[component], latency_ms)
        end
        
        # Cleanup old samples periodically
        if current_time_ms - tracker.last_cleanup > tracker.sample_window_ms
            cleanup_old_samples!(tracker)
            tracker.last_cleanup = current_time_ms
        end
    end
end

"""
    check_circuit_breaker(tracker, component)

Check if circuit breaker is tripped for a component.
"""
function check_circuit_breaker(tracker::LatencyTracker, component::Symbol)
    lock(tracker.lock) do
        if !haskey(tracker.circuit_breakers, component)
            return (open=false, state=:closed, reason="No circuit breaker")
        end
        
        cb = tracker.circuit_breakers[component]
        state = cb.state[]
        
        if state == :open
            # Check if timeout has passed
            time_since_failure = time() * 1000 - cb.last_failure_time[]
            if time_since_failure > cb.timeout_ms
                # Transition to half-open
                cb.state[] = :half_open
                cb.success_count[] = 0
                cb.failure_count[] = 0
                return (open=false, state=:half_open, reason="Testing recovery")
            end
            return (open=true, state=:open, reason="Circuit open")
        elseif state == :half_open
            return (open=false, state=:half_open, reason="Testing recovery")
        else
            return (open=false, state=:closed, reason="Circuit closed")
        end
    end
end

"""
    should_bypass(tracker, component)

Determine if component should be bypassed based on adaptive logic.
"""
function should_bypass(tracker::LatencyTracker, component::Symbol)
    lock(tracker.lock) do
        if !haskey(tracker.bypass_logic, component)
            return false
        end
        
        bypass = tracker.bypass_logic[component]
        
        if !bypass.enabled[]
            return false
        end
        
        # Use bypass rate for probabilistic bypassing
        return rand() < bypass.bypass_rate[]
    end
end

"""
    get_latency_stats(tracker, component)

Get detailed latency statistics for a component.
"""
function get_latency_stats(tracker::LatencyTracker, component::Union{Symbol,Nothing}=nothing)
    lock(tracker.lock) do
        if component === nothing
            # Return global metrics
            metrics = tracker.global_metrics
        else
            if !haskey(tracker.metrics, component)
                return nothing
            end
            metrics = tracker.metrics[component]
        end
        
        # Calculate percentiles if we have samples
        samples = component === nothing ? 
                  vcat(values(tracker.components)...) : 
                  get(tracker.components, component, Float64[])
        
        if !isempty(samples)
            sorted = sort(samples)
            n = length(sorted)
            
            p50_idx = max(1, round(Int, 0.50 * n))
            p95_idx = max(1, round(Int, 0.95 * n))
            p99_idx = max(1, round(Int, 0.99 * n))
            
            return (
                count = metrics.count,
                min_us = metrics.min,
                max_us = metrics.max,
                mean_us = metrics.mean,
                median_us = sorted[p50_idx],
                p95_us = sorted[p95_idx],
                p99_us = sorted[p99_idx],
                std_dev_us = metrics.std_dev,
                min_ms = metrics.min / 1000,
                max_ms = metrics.max / 1000,
                mean_ms = metrics.mean / 1000,
                median_ms = sorted[p50_idx] / 1000,
                p95_ms = sorted[p95_idx] / 1000,
                p99_ms = sorted[p99_idx] / 1000
            )
        else
            return (
                count = 0,
                min_us = 0.0,
                max_us = 0.0,
                mean_us = 0.0,
                median_us = 0.0,
                p95_us = 0.0,
                p99_us = 0.0,
                std_dev_us = 0.0,
                min_ms = 0.0,
                max_ms = 0.0,
                mean_ms = 0.0,
                median_ms = 0.0,
                p95_ms = 0.0,
                p99_ms = 0.0
            )
        end
    end
end

"""
    reset_metrics(tracker, component)

Reset metrics for a specific component or all components.
"""
function reset_metrics(tracker::LatencyTracker, component::Union{Symbol,Nothing}=nothing)
    lock(tracker.lock) do
        if component === nothing
            # Reset all
            empty!(tracker.components)
            empty!(tracker.metrics)
            tracker.global_metrics = create_empty_metrics()
        else
            # Reset specific component
            if haskey(tracker.components, component)
                empty!(tracker.components[component])
                tracker.metrics[component] = create_empty_metrics()
            end
        end
    end
end

"""
    configure_thresholds(tracker, component; kwargs...)

Configure circuit breaker and bypass thresholds for a component.
"""
function configure_thresholds(tracker::LatencyTracker, component::Symbol;
                             circuit_threshold_ms::Union{Float64,Nothing}=nothing,
                             failure_threshold::Union{Int,Nothing}=nothing,
                             bypass_threshold_ms::Union{Float64,Nothing}=nothing,
                             recovery_threshold_ms::Union{Float64,Nothing}=nothing)
    
    lock(tracker.lock) do
        # Configure circuit breaker
        if haskey(tracker.circuit_breakers, component)
            cb = tracker.circuit_breakers[component]
            if circuit_threshold_ms !== nothing
                cb.threshold_ms = circuit_threshold_ms
            end
            if failure_threshold !== nothing
                cb.failure_threshold = failure_threshold
            end
        end
        
        # Configure bypass logic
        if haskey(tracker.bypass_logic, component)
            bypass = tracker.bypass_logic[component]
            if bypass_threshold_ms !== nothing
                bypass.bypass_threshold_ms = bypass_threshold_ms
            end
            if recovery_threshold_ms !== nothing
                bypass.recovery_threshold_ms = recovery_threshold_ms
            end
        end
    end
end

# Helper functions

function create_empty_metrics()
    return LatencyMetrics(
        Inf,   # min
        0.0,   # max
        0.0,   # mean
        0.0,   # median
        0.0,   # p95
        0.0,   # p99
        0.0,   # std_dev
        0,     # count
        0.0,   # sum
        0.0    # sum_squared
    )
end

function create_circuit_breaker(;
    threshold_ms::Float64=100.0,
    failure_threshold::Int=5,
    success_threshold::Int=3,
    timeout_ms::Float64=30000.0)
    
    return CircuitBreaker(
        Atomic{Symbol}(:closed),
        Atomic{Int}(0),
        Atomic{Int}(0),
        Atomic{Float64}(0.0),
        Atomic{Float64}(time() * 1000),
        threshold_ms,
        failure_threshold,
        success_threshold,
        timeout_ms,
        10  # half-open requests
    )
end

function create_adaptive_bypass(;
    bypass_threshold_ms::Float64=50.0,
    recovery_threshold_ms::Float64=20.0,
    slow_threshold::Int=3,
    fast_threshold::Int=5)
    
    return AdaptiveBypass(
        Atomic{Bool}(false),
        bypass_threshold_ms,
        recovery_threshold_ms,
        Atomic{Int}(0),
        Atomic{Int}(0),
        slow_threshold,
        fast_threshold,
        Atomic{Float64}(0.0)
    )
end

function update_metrics!(metrics::LatencyMetrics, value::Float64)
    metrics.count += 1
    metrics.sum += value
    metrics.sum_squared += value * value
    metrics.min = min(metrics.min, value)
    metrics.max = max(metrics.max, value)
    metrics.mean = metrics.sum / metrics.count
    
    if metrics.count > 1
        variance = (metrics.sum_squared - metrics.sum^2 / metrics.count) / (metrics.count - 1)
        metrics.std_dev = sqrt(max(0, variance))
    end
end

function update_circuit_breaker!(cb::CircuitBreaker, latency_ms::Float64)
    current_time_ms = time() * 1000
    state = cb.state[]
    
    if latency_ms > cb.threshold_ms
        # Failure condition
        atomic_add!(cb.failure_count, 1)
        cb.last_failure_time[] = current_time_ms
        
        if state == :closed && cb.failure_count[] >= cb.failure_threshold
            # Trip circuit breaker
            cb.state[] = :open
            cb.last_state_change[] = current_time_ms
        elseif state == :half_open
            # Failed during recovery, reopen
            cb.state[] = :open
            cb.last_state_change[] = current_time_ms
        end
    else
        # Success condition
        if state == :half_open
            atomic_add!(cb.success_count, 1)
            
            if cb.success_count[] >= cb.success_threshold
                # Recovery successful, close circuit
                cb.state[] = :closed
                cb.failure_count[] = 0
                cb.success_count[] = 0
                cb.last_state_change[] = current_time_ms
            end
        elseif state == :closed
            # Reset failure count on success
            if cb.failure_count[] > 0
                atomic_sub!(cb.failure_count, 1)
            end
        end
    end
end

function update_bypass_logic!(bypass::AdaptiveBypass, latency_ms::Float64)
    if latency_ms > bypass.bypass_threshold_ms
        # Slow response
        atomic_add!(bypass.consecutive_slow, 1)
        bypass.consecutive_fast[] = 0
        
        if bypass.consecutive_slow[] >= bypass.slow_threshold
            bypass.enabled[] = true
            # Increase bypass rate
            current_rate = bypass.bypass_rate[]
            bypass.bypass_rate[] = min(1.0, current_rate + 0.1)
        end
    elseif latency_ms < bypass.recovery_threshold_ms
        # Fast response
        atomic_add!(bypass.consecutive_fast, 1)
        bypass.consecutive_slow[] = 0
        
        if bypass.consecutive_fast[] >= bypass.fast_threshold
            # Decrease bypass rate
            current_rate = bypass.bypass_rate[]
            new_rate = max(0.0, current_rate - 0.2)
            bypass.bypass_rate[] = new_rate
            
            if new_rate == 0.0
                bypass.enabled[] = false
            end
        end
    end
end

function cleanup_old_samples!(tracker::LatencyTracker)
    for (component, samples) in tracker.components
        if length(samples) > tracker.max_samples
            # Keep only recent samples
            keep_count = div(tracker.max_samples, 2)
            deleteat!(samples, 1:(length(samples) - keep_count))
            
            # Recalculate metrics
            if !isempty(samples)
                metrics = create_empty_metrics()
                for sample in samples
                    update_metrics!(metrics, sample)
                end
                tracker.metrics[component] = metrics
            end
        end
    end
end

end # module