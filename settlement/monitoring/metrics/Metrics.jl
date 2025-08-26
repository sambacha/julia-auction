"""
    Metrics

Detailed metrics collection and aggregation for settlement monitoring.
"""
module Metrics

export MetricsCollector, record_metric, get_metric, reset_collector!

using Dates

mutable struct MetricsCollector
    metrics::Dict{Symbol, Vector{Tuple{DateTime, Float64}}}
    aggregates::Dict{Symbol, Dict{Symbol, Float64}}
    retention_hours::Int
    
    function MetricsCollector(; retention_hours::Int = 24)
        new(
            Dict{Symbol, Vector{Tuple{DateTime, Float64}}}(),
            Dict{Symbol, Dict{Symbol, Float64}}(),
            retention_hours
        )
    end
end

"""
    record_metric(collector, name, value)

Record a metric value with timestamp.
"""
function record_metric(collector::MetricsCollector, name::Symbol, value::Float64)
    if !haskey(collector.metrics, name)
        collector.metrics[name] = Vector{Tuple{DateTime, Float64}}()
        collector.aggregates[name] = Dict{Symbol, Float64}(
            :sum => 0.0,
            :count => 0.0,
            :min => Inf,
            :max => -Inf
        )
    end
    
    # Record with timestamp
    push!(collector.metrics[name], (now(), value))
    
    # Update aggregates
    agg = collector.aggregates[name]
    agg[:sum] += value
    agg[:count] += 1
    agg[:min] = min(agg[:min], value)
    agg[:max] = max(agg[:max], value)
    
    # Clean old data
    cleanup_old_metrics!(collector, name)
end

"""
    get_metric(collector, name, window_minutes)

Get metric values within the specified time window.
"""
function get_metric(
    collector::MetricsCollector,
    name::Symbol,
    window_minutes::Int = 60
)
    if !haskey(collector.metrics, name)
        return Float64[]
    end
    
    cutoff = now() - Minute(window_minutes)
    values = Float64[]
    
    for (timestamp, value) in collector.metrics[name]
        if timestamp >= cutoff
            push!(values, value)
        end
    end
    
    return values
end

function cleanup_old_metrics!(collector::MetricsCollector, name::Symbol)
    cutoff = now() - Hour(collector.retention_hours)
    filter!(x -> x[1] >= cutoff, collector.metrics[name])
end

function reset_collector!(collector::MetricsCollector)
    empty!(collector.metrics)
    empty!(collector.aggregates)
end

end # module Metrics