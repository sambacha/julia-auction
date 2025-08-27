"""
    LatencyMonitor

High-precision latency monitoring for settlement operations.
Tracks latencies at microsecond resolution across all settlement phases.

# Tracked Metrics
- Orchestration latency
- CFMM routing latency
- Phantom auction latency
- State management latency
- End-to-end settlement latency
"""

using .Metrics: MetricsCollector, record_metric
using .Alerts: AlertManager, check_threshold
using Dates

"""
Union type for metric values - replaces Any type for type safety in metrics collection.
"""
const MetricValue = Union{Float64, Int64, String, Bool, Vector{Float64}, NamedTuple}

mutable struct LatencyMonitor
    metrics_collector::MetricsCollector
    alert_manager::AlertManager
    latency_buckets::Dict{Symbol, Vector{Float64}}
    percentiles::Vector{Float64}
    window_size::Int
    
    function LatencyMonitor(;
        window_size::Int = 10000,
        percentiles::Vector{Float64} = [0.5, 0.9, 0.95, 0.99]
    )
        buckets = Dict{Symbol, Vector{Float64}}(
            :orchestration => Float64[],
            :cfmm_routing => Float64[],
            :phantom_auction => Float64[],
            :state_management => Float64[],
            :end_to_end => Float64[]
        )
        
        new(
            MetricsCollector(),
            AlertManager(),
            buckets,
            percentiles,
            window_size
        )
    end
end

"""
    LatencyTrace

Represents a detailed latency trace through the settlement pipeline.
"""
struct LatencyTrace
    transaction_id::UUID
    start_time::Int64  # nanoseconds
    end_time::Int64
    phases::Dict{Symbol, Tuple{Int64, Int64}}  # phase => (start_ns, end_ns)
    metadata::Dict{Symbol, MetricValue}
end

"""
    track_latency(monitor, phase, latency_us)

Record latency for a specific phase of settlement.

# Arguments
- `phase`: Symbol identifying the phase (:orchestration, :routing, etc.)
- `latency_us`: Latency in microseconds
"""
function track_latency(
    monitor::LatencyMonitor,
    phase::Symbol,
    latency_us::Float64
)
    # Store in appropriate bucket
    if haskey(monitor.latency_buckets, phase)
        push!(monitor.latency_buckets[phase], latency_us)
        
        # Maintain window size
        if length(monitor.latency_buckets[phase]) > monitor.window_size
            popfirst!(monitor.latency_buckets[phase])
        end
    end
    
    # Record in metrics collector
    record_metric(monitor.metrics_collector, Symbol("latency_$(phase)_us"), latency_us)
    
    # Check for alerts
    threshold = get_threshold_for_phase(phase)
    if latency_us > threshold
        trigger_latency_alert(monitor.alert_manager, phase, latency_us, threshold)
    end
end

"""
    start_trace(monitor, transaction_id)

Start a new latency trace for a transaction.

# Returns
- `LatencyTrace` object for tracking
"""
function start_trace(monitor::LatencyMonitor, transaction_id::UUID)
    return LatencyTrace(
        transaction_id,
        time_ns(),
        0,
        Dict{Symbol, Tuple{Int64, Int64}}(),
        Dict{Symbol, MetricValue}()
    )
end

"""
    mark_phase_start(trace, phase)

Mark the start of a settlement phase in the trace.
"""
function mark_phase_start(trace::LatencyTrace, phase::Symbol)
    trace.phases[phase] = (time_ns(), 0)
end

"""
    mark_phase_end(trace, phase)

Mark the end of a settlement phase and calculate latency.

# Returns
- Phase latency in microseconds
"""
function mark_phase_end(trace::LatencyTrace, phase::Symbol)
    if !haskey(trace.phases, phase)
        return 0.0
    end
    
    start_ns, _ = trace.phases[phase]
    end_ns = time_ns()
    trace.phases[phase] = (start_ns, end_ns)
    
    return (end_ns - start_ns) / 1000.0  # Convert to microseconds
end

"""
    get_metrics(monitor, phase)

Get detailed latency metrics for a specific phase.

# Returns
- NamedTuple with percentiles and statistics
"""
function get_metrics(monitor::LatencyMonitor, phase::Symbol = :end_to_end)
    latencies = get(monitor.latency_buckets, phase, Float64[])
    
    if isempty(latencies)
        return (
            count = 0,
            mean = 0.0,
            min = 0.0,
            max = 0.0,
            percentiles = Dict(p => 0.0 for p in monitor.percentiles)
        )
    end
    
    sorted = sort(latencies)
    percentile_values = Dict{Float64, Float64}()
    
    for p in monitor.percentiles
        idx = ceil(Int, length(sorted) * p)
        idx = clamp(idx, 1, length(sorted))
        percentile_values[p] = sorted[idx]
    end
    
    return (
        count = length(latencies),
        mean = sum(latencies) / length(latencies),
        min = minimum(latencies),
        max = maximum(latencies),
        percentiles = percentile_values
    )
end

"""
    generate_report(monitor)

Generate a comprehensive performance report.

# Returns
- `PerformanceReport` with detailed metrics
"""
function generate_report(monitor::LatencyMonitor)
    report_data = Dict{Symbol, MetricValue}()
    
    # Collect metrics for each phase
    for phase in keys(monitor.latency_buckets)
        report_data[phase] = get_metrics(monitor, phase)
    end
    
    # Calculate SLA compliance
    report_data[:sla_compliance] = calculate_sla_compliance(monitor)
    
    # Get alert summary
    report_data[:alerts] = get_alert_summary(monitor.alert_manager)
    
    return PerformanceReport(
        timestamp = now(),
        metrics = report_data,
        recommendations = generate_recommendations(report_data)
    )
end

struct PerformanceReport
    timestamp::DateTime
    metrics::Dict{Symbol, MetricValue}
    recommendations::Vector{String}
end

# Helper functions

function get_threshold_for_phase(phase::Symbol)
    # Define latency thresholds for each phase (in microseconds)
    thresholds = Dict(
        :orchestration => 1000.0,    # 1ms
        :cfmm_routing => 5000.0,      # 5ms
        :phantom_auction => 100.0,    # 100μs
        :state_management => 500.0,   # 500μs
        :end_to_end => 10000.0       # 10ms
    )
    
    return get(thresholds, phase, 10000.0)
end

function trigger_latency_alert(alert_manager::AlertManager, phase::Symbol, latency::Float64, threshold::Float64)
    alert = create_alert(
        :high_latency,
        "High latency detected in $(phase): $(latency)μs (threshold: $(threshold)μs)",
        Dict(:phase => phase, :latency => latency, :threshold => threshold)
    )
    
    send_alert(alert_manager, alert)
end

function calculate_sla_compliance(monitor::LatencyMonitor)
    # Calculate percentage of requests meeting SLA
    end_to_end = get(monitor.latency_buckets, :end_to_end, Float64[])
    
    if isempty(end_to_end)
        return 100.0
    end
    
    sla_threshold = 10000.0  # 10ms SLA
    compliant = count(l -> l <= sla_threshold, end_to_end)
    
    return compliant / length(end_to_end) * 100
end

function generate_recommendations(metrics::Dict{Symbol, MetricValue})
    recommendations = String[]
    
    # Check orchestration latency
    if haskey(metrics, :orchestration)
        orch_metrics = metrics[:orchestration]
        if orch_metrics.mean > 500.0
            push!(recommendations, 
                  "Consider optimizing orchestration logic - mean latency $(orch_metrics.mean)μs exceeds target")
        end
    end
    
    # Check routing latency
    if haskey(metrics, :cfmm_routing)
        routing_metrics = metrics[:cfmm_routing]
        if routing_metrics.percentiles[0.99] > 10000.0
            push!(recommendations,
                  "P99 routing latency is high ($(routing_metrics.percentiles[0.99])μs) - consider route caching")
        end
    end
    
    # Check SLA compliance
    if haskey(metrics, :sla_compliance) && metrics[:sla_compliance] < 99.0
        push!(recommendations,
              "SLA compliance is $(metrics[:sla_compliance])% - investigate latency spikes")
    end
    
    return recommendations
end

"""
    reset_metrics!(monitor)

Reset all collected metrics (useful for testing or periodic cleanup).
"""
function reset_metrics!(monitor::LatencyMonitor)
    for phase in keys(monitor.latency_buckets)
        empty!(monitor.latency_buckets[phase])
    end
    reset_collector!(monitor.metrics_collector)
end