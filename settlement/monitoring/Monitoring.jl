"""
    Monitoring

Performance monitoring and metrics collection for settlement operations.
Tracks latency, throughput, and system health metrics.

# Components
- `LatencyMonitor` - Microsecond-precision latency tracking
- `metrics/` - Detailed metrics collection
- `alerts/` - Alerting and threshold monitoring
"""
module Monitoring

export LatencyMonitor, MetricsCollector, PerformanceReport
export track_latency, get_metrics, generate_report

# Submodules
include("metrics/Metrics.jl")
using .Metrics

include("alerts/Alerts.jl")
using .Alerts

include("LatencyMonitor.jl")

end # module Monitoring