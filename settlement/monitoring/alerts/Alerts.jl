"""
    Alerts

Alert management for settlement monitoring.
Handles threshold detection and alert dispatch.
"""
module Alerts

export AlertManager, Alert, create_alert, send_alert, get_alert_summary

using Dates
struct Alert
    level::Symbol  # :info, :warning, :critical
    message::String
    timestamp::DateTime
    metadata::Dict{Symbol, Any}
end

mutable struct AlertManager
    alerts::Vector{Alert}
    thresholds::Dict{Symbol, Float64}
    handlers::Vector{Function}
    max_alerts::Int
    
    function AlertManager(; max_alerts::Int = 1000)
        new(
            Vector{Alert}(),
            Dict{Symbol, Float64}(),
            Vector{Function}(),
            max_alerts
        )
    end
end

"""
    create_alert(level, message, metadata)

Create a new alert.
"""
function create_alert(level::Symbol, message::String, metadata::Dict = Dict{Symbol, Any}())
    return Alert(level, message, now(), metadata)
end

"""
    send_alert(manager, alert)

Send an alert through the alert manager.
"""
function send_alert(manager::AlertManager, alert::Alert)
    push!(manager.alerts, alert)
    
    # Maintain max alerts
    if length(manager.alerts) > manager.max_alerts
        popfirst!(manager.alerts)
    end
    
    # Trigger handlers
    for handler in manager.handlers
        try
            handler(alert)
        catch e
            @error "Alert handler failed" exception=e
        end
    end
end

"""
    check_threshold(manager, metric_name, value)

Check if a metric value exceeds its threshold.

# Returns
- `true` if threshold exceeded
"""
function check_threshold(manager::AlertManager, metric_name::Symbol, value::Float64)
    threshold = get(manager.thresholds, metric_name, Inf)
    return value > threshold
end

"""
    get_alert_summary(manager, window_minutes)

Get summary of recent alerts.
"""
function get_alert_summary(manager::AlertManager, window_minutes::Int = 60)
    cutoff = now() - Minute(window_minutes)
    recent_alerts = filter(a -> a.timestamp >= cutoff, manager.alerts)
    
    summary = Dict{Symbol, Int}(
        :info => 0,
        :warning => 0,
        :critical => 0
    )
    
    for alert in recent_alerts
        summary[alert.level] = get(summary, alert.level, 0) + 1
    end
    
    return summary
end

"""
    add_handler!(manager, handler)

Add an alert handler function.
"""
function add_handler!(manager::AlertManager, handler::Function)
    push!(manager.handlers, handler)
end

"""
    set_threshold!(manager, metric_name, threshold)

Set alert threshold for a metric.
"""
function set_threshold!(manager::AlertManager, metric_name::Symbol, threshold::Float64)
    manager.thresholds[metric_name] = threshold
end

end # module Alerts