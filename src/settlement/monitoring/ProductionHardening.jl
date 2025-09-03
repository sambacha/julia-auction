module ProductionHardening

"""
Production Hardening Integration Module

This module provides a unified interface for all production hardening components
including circuit breakers, error handling, latency monitoring, health checks,
and configuration management.

Features:
- <10ms p99 latency monitoring with TimerOutputs
- Circuit breakers with automatic recovery
- Comprehensive error handling with retries and backoff
- Health checks with readiness/liveness probes
- Resource monitoring and alerting
- Production-optimized configuration
"""

using Base.Threads: Atomic
using Logging
using Statistics
# Load all production hardening components
include("CircuitBreaker.jl")
include("ErrorHandler.jl")
include("HealthCheck.jl")
include("latency/LatencyMonitor.jl")
include("../../../config/production.jl")

using .CircuitBreaker
using .ErrorHandler
using .HealthCheck
using .LatencyMonitor
using .ProductionConfig
# Re-export key types and functions
export ProductionHardeningSystem, create_production_system
export monitor_operation, execute_with_protection, get_system_status
export ProductionMetrics, SystemAlert, AlertSeverity, AlertDetailValue

"""
Alert severity levels for production monitoring.
"""
@enum AlertSeverity begin
    INFO
    WARNING
    ERROR
    CRITICAL
end

"""
Alert detail value union type for type safety.
"""
const AlertDetailValue = Union{String, Float64, Int64, Bool, Vector{String}, NamedTuple}

"""
System alert structure.
"""
struct SystemAlert
    severity::AlertSeverity
    component::Symbol
    message::String
    timestamp::Float64
    details::Dict{String, AlertDetailValue}
end

"""
Comprehensive production metrics.
"""
struct ProductionMetrics
    timestamp::Float64
    latency_metrics::Dict{Symbol, NamedTuple}
    circuit_breaker_metrics::Dict{Symbol, NamedTuple}
    error_metrics::NamedTuple
    health_metrics::NamedTuple
    resource_metrics::NamedTuple
    alerts::Vector{SystemAlert}
    sla_compliance::Dict{Symbol, Float64}
    system_uptime_ms::Float64
end

"""
Complete production hardening system.
"""
mutable struct ProductionHardeningSystem
    config::ProductionConfiguration
    latency_tracker::ProductionLatencyTracker
    circuit_breakers::Dict{Symbol, ProductionCircuitBreaker}
    error_handler::ProductionErrorHandler
    health_checker::HealthChecker
    alerts::Vector{SystemAlert}
    system_start_time::Float64
    last_metrics_collection::Float64
    enabled::Atomic{Bool}
end

"""
    create_production_system(; kwargs...)

Create a complete production hardening system with all components integrated.
"""
function create_production_system(;
    environment::Symbol=:production,
    custom_config::Union{ProductionConfiguration, Nothing}=nothing,
    enable_background_monitoring::Bool=true)
    
    @info "Initializing production hardening system" environment=environment
    
    # Create or use provided configuration
    base_config = custom_config !== nothing ? custom_config : create_production_config()
    config = create_environment_config(base_config, environment)
    
    @info "Configuration loaded" 
        p99_target=config.p99_latency_target_ms
        circuit_breakers_enabled=config.enable_circuit_breakers
        monitoring_enabled=config.enable_performance_monitoring
    
    # Initialize latency monitoring
    latency_tracker = create_production_tracker(
        slow_operation_threshold_ms=config.slow_operation_threshold_ms,
        p99_target_ms=config.p99_latency_target_ms,
        max_samples=10000,
        sample_window_ms=config.performance_report_interval_ms
    )
    
    # Set performance targets for known operations
    for (operation, op_config) in ProductionConfig.OPERATION_CONFIGS
        set_performance_target(latency_tracker, operation, op_config.p99_target_ms)
    end
    
    @info "Latency monitoring initialized with $(length(ProductionConfig.OPERATION_CONFIGS)) operation targets"
    
    # Initialize circuit breakers for critical operations
    circuit_breakers = Dict{Symbol, ProductionCircuitBreaker}()
    
    if config.enable_circuit_breakers
        critical_operations = [:auction_creation, :bid_submission, :settlement, :cfmm_bridge_call]\n        \n        for operation in critical_operations\n            op_config = get_operation_config(operation)\n            cb = create_circuit_breaker(\n                string(operation),\n                failure_threshold=op_config.circuit_breaker_threshold,\n                timeout_ms=config.circuit_breaker_timeout_ms,\n                slow_call_threshold_ms=op_config.timeout_ms * 0.8  # 80% of timeout\n            )\n            circuit_breakers[operation] = cb\n        end\n        \n        @info \"Circuit breakers initialized\" operations=collect(keys(circuit_breakers))\n    end\n    \n    # Initialize error handler\n    error_handler = create_error_handler(\n        \"production_system\",\n        default_max_attempts=config.max_retry_attempts,\n        default_base_delay_ms=config.base_retry_delay_ms,\n        default_backoff_strategy=config.retry_backoff_strategy\n    )\n    \n    # Configure operation-specific retry policies\n    for (operation, op_config) in ProductionConfig.OPERATION_CONFIGS\n        retry_policy = RetryPolicy(\n            op_config.max_retries,\n            config.base_retry_delay_ms,\n            config.max_retry_delay_ms,\n            config.retry_backoff_strategy,\n            config.retry_jitter_ratio,\n            Set([ErrorHandler.TRANSIENT, ErrorHandler.TIMEOUT, ErrorHandler.RATE_LIMITED]),\n            1.5\n        )\n        configure_retry_policy(error_handler, operation, retry_policy)\n    end\n    \n    @info \"Error handling configured with operation-specific policies\"\n    \n    # Initialize health monitoring\n    health_checker = create_health_checker(\n        cpu_threshold_percent=config.cpu_usage_threshold_percent,\n        memory_threshold_percent=config.memory_usage_threshold_percent,\n        enable_background_checks=config.enable_background_health_checks\n    )\n    \n    # Add system health checks\n    add_system_health_checks!(health_checker, circuit_breakers, latency_tracker, config)\n    \n    @info \"Health monitoring initialized with system health checks\"\n    \n    current_time = time() * 1000\n    system = ProductionHardeningSystem(\n        config,\n        latency_tracker,\n        circuit_breakers,\n        error_handler,\n        health_checker,\n        SystemAlert[],\n        current_time,\n        current_time,\n        Atomic{Bool}(true)\n    )\n    \n    # Start background monitoring if enabled\n    if enable_background_monitoring\n        start_background_monitoring!(system)\n    end\n    \n    @info \"Production hardening system fully initialized and ready\"\n    return system\nend\n\n\"\"\"    monitor_operation(system, operation_name, f; kwargs...)\n\nExecute operation with comprehensive monitoring and protection.\n\"\"\"\nfunction monitor_operation(system::ProductionHardeningSystem,\n                         operation_name::Symbol,\n                         f::Function;\n                         timeout_ms::Union{Float64, Nothing}=nothing,\n                         enable_circuit_breaker::Bool=true,\n                         enable_error_handling::Bool=true,\n                         context::Dict=Dict())\n    \n    if !system.enabled[]\n        @warn \"Production hardening system is disabled\" operation=operation_name\n        return f()\n    end\n    \n    # Get operation configuration\n    op_config = get_operation_config(operation_name)\n    actual_timeout = timeout_ms !== nothing ? timeout_ms : op_config.timeout_ms\n    \n    # Execute with comprehensive protection\n    start_time = time() * 1000\n    \n    try\n        if enable_circuit_breaker && haskey(system.circuit_breakers, operation_name)\n            # Execute with circuit breaker protection\n            cb = system.circuit_breakers[operation_name]\n            result, executed, cb_state = execute_with_circuit_breaker(cb) do\n                execute_monitored_operation(system, operation_name, f, actual_timeout, context)\n            end\n            \n            if !executed\n                @warn \"Circuit breaker prevented execution\" \n                    operation=operation_name \n                    state=cb_state\n                \n                # Record circuit breaker prevention as alert\n                alert = SystemAlert(\n                    WARNING,\n                    operation_name,\n                    \"Circuit breaker prevented execution (state: $cb_state)\",\n                    start_time,\n                    Dict(\"circuit_state\" => string(cb_state))\n                )\n                push!(system.alerts, alert)\n            end\n            \n            return result\n        else\n            # Execute without circuit breaker\n            return execute_monitored_operation(system, operation_name, f, actual_timeout, context)\n        end\n        \n    catch e\n        if enable_error_handling\n            # Handle with retry logic\n            return handle_with_retry(system.error_handler, operation_name,\n                                   timeout_ms=actual_timeout,\n                                   context=context) do\n                execute_monitored_operation(system, operation_name, f, actual_timeout, context)\n            end\n        else\n            rethrow(e)\n        end\n    end\nend\n\n\"\"\"    execute_with_protection(system, operation_name, f; kwargs...)\n\nAlias for monitor_operation with full protection enabled.\n\"\"\"\nfunction execute_with_protection(system::ProductionHardeningSystem,\n                                operation_name::Symbol,\n                                f::Function;\n                                kwargs...)\n    return monitor_operation(system, operation_name, f; kwargs...)\nend\n\n\"\"\"Execute operation with timing and monitoring.\"\"\"\nfunction execute_monitored_operation(system::ProductionHardeningSystem,\n                                    operation_name::Symbol,\n                                    f::Function,\n                                    timeout_ms::Float64,\n                                    context::Dict)\n    \n    # Execute with latency monitoring using TimerOutputs\n    result = @timed_operation system.latency_tracker operation_name begin\n        if timeout_ms > 0\n            # Simple timeout protection\n            task = @async f()\n            start_time = time()\n            \n            while !istaskdone(task) && (time() - start_time) * 1000 < timeout_ms\n                sleep(0.001)\n            end\n            \n            if istaskdone(task)\n                if istaskfailed(task)\n                    throw(task.exception)\n                else\n                    task.result\n                end\n            else\n                @warn \"Operation timeout\" operation=operation_name timeout_ms=timeout_ms\n                throw(ErrorHandler.TimeoutError(\"Operation $operation_name timed out after $(timeout_ms)ms\"))\n            end\n        else\n            f()\n        end\n    end\n    \n    return result\nend\n\n\"\"\"    get_system_status(system)\n\nGet comprehensive system status and metrics.\n\"\"\"\nfunction get_system_status(system::ProductionHardeningSystem)\n    current_time = time() * 1000\n    \n    # Collect latency metrics\n    latency_report = generate_performance_report(system.latency_tracker)\n    \n    # Collect circuit breaker metrics\n    cb_metrics = Dict{Symbol, NamedTuple}()\n    for (name, cb) in system.circuit_breakers\n        cb_metrics[name] = get_circuit_metrics(cb)\n    end\n    \n    # Collect error metrics\n    error_metrics = get_error_statistics(system.error_handler)\n    \n    # Collect health metrics\n    health_metrics = get_system_health(system.health_checker)\n    \n    # Collect resource metrics\n    resource_metrics = monitor_resources(system.health_checker.resource_monitor)\n    \n    # Calculate SLA compliance\n    sla_compliance = calculate_sla_compliance(system, latency_report)\n    \n    # Check for new alerts\n    new_alerts = check_for_alerts(system, latency_report, cb_metrics, error_metrics, health_metrics)\n    append!(system.alerts, new_alerts)\n    \n    # Clean up old alerts (keep last 24 hours)\n    cutoff_time = current_time - 24 * 3600 * 1000.0\n    filter!(alert -> alert.timestamp >= cutoff_time, system.alerts)\n    \n    system.last_metrics_collection = current_time\n    \n    return ProductionMetrics(\n        current_time,\n        latency_report.latency_by_component,\n        cb_metrics,\n        error_metrics,\n        health_metrics,\n        resource_metrics,\n        copy(system.alerts),\n        sla_compliance,\n        current_time - system.system_start_time\n    )\nend\n\n\"\"\"Calculate SLA compliance for all operations.\"\"\"\nfunction calculate_sla_compliance(system::ProductionHardeningSystem, latency_report)\n    sla_compliance = Dict{Symbol, Float64}()\n    \n    for (operation, stats) in latency_report.latency_by_component\n        if stats !== nothing && haskey(system.latency_tracker.performance_targets, operation)\n            target_ms = system.latency_tracker.performance_targets[operation]\n            \n            # Calculate percentage of operations meeting SLA\n            if haskey(system.latency_tracker.components, operation)\n                samples = system.latency_tracker.components[operation]\n                meeting_sla = count(sample -> (sample / 1000.0) <= target_ms, samples)\n                sla_compliance[operation] = (meeting_sla / length(samples)) * 100.0\n            else\n                sla_compliance[operation] = 100.0\n            end\n        end\n    end\n    \n    return sla_compliance\nend\n\n\"\"\"Check for system alerts based on current metrics.\"\"\"\nfunction check_for_alerts(system::ProductionHardeningSystem, \n                         latency_report, \n                         cb_metrics, \n                         error_metrics, \n                         health_metrics)\n    alerts = SystemAlert[]\n    current_time = time() * 1000\n    \n    # Check for latency SLA violations\n    for (operation, violation_percent) in latency_report.sla_violations\n        if violation_percent > system.config.sla_violation_alert_threshold_percent\n            alert = SystemAlert(\n                ERROR,\n                operation,\n                \"SLA violation: $(round(violation_percent, digits=1))% of operations exceed target\",\n                current_time,\n                Dict(\"violation_percent\" => violation_percent)\n            )\n            push!(alerts, alert)\n        end\n    end\n    \n    # Check circuit breaker states\n    for (name, metrics) in cb_metrics\n        if metrics.state == CircuitBreaker.OPEN\n            alert = SystemAlert(\n                CRITICAL,\n                name,\n                \"Circuit breaker is OPEN - system protection active\",\n                current_time,\n                Dict(\"error_rate\" => metrics.error_rate_percent,\n                     \"total_failures\" => metrics.total_failures)\n            )\n            push!(alerts, alert)\n        elseif metrics.error_rate_percent > system.config.error_rate_alert_threshold_percent\n            alert = SystemAlert(\n                WARNING,\n                name,\n                \"High error rate: $(round(metrics.error_rate_percent, digits=1))%\",\n                current_time,\n                Dict(\"error_rate\" => metrics.error_rate_percent)\n            )\n            push!(alerts, alert)\n        end\n    end\n    \n    # Check overall system health\n    if health_metrics.overall_status == HealthCheck.CRITICAL\n        alert = SystemAlert(\n            CRITICAL,\n            :system,\n            \"System health is CRITICAL\",\n            current_time,\n            Dict(\"health_status\" => string(health_metrics.overall_status))\n        )\n        push!(alerts, alert)\n    elseif health_metrics.overall_status == HealthCheck.UNHEALTHY\n        alert = SystemAlert(\n            ERROR,\n            :system,\n            \"System health is UNHEALTHY\",\n            current_time,\n            Dict(\"health_status\" => string(health_metrics.overall_status))\n        )\n        push!(alerts, alert)\n    end\n    \n    return alerts\nend\n\n\"\"\"Add comprehensive system health checks.\"\"\"\nfunction add_system_health_checks!(health_checker, circuit_breakers, latency_tracker, config)\n    # Circuit breaker health\n    for (name, cb) in circuit_breakers\n        add_health_check(health_checker, Symbol(\"circuit_$(name)\"), () -> {\n            metrics = get_circuit_metrics(cb)\n            if metrics.state == CircuitBreaker.OPEN\n                return HealthCheckResult(\n                    Symbol(\"circuit_$(name)\"),\n                    HealthCheck.UNHEALTHY,\n                    \"Circuit breaker is open\",\n                    0.0,\n                    time() * 1000,\n                    Dict(\"state\" => string(metrics.state)),\n                    Dict{Symbol, HealthCheck.HealthStatus}()\n                )\n            else\n                return true\n            end\n        }, is_critical=true)\n    end\n    \n    # Performance health\n    add_health_check(health_checker, :performance, () -> {\n        slow_ops = check_slow_operations(latency_tracker)\n        critical_slow = filter(alert -> alert.latency_ms > alert.p99_target_ms * 2, slow_ops)\n        \n        if !isempty(critical_slow)\n            return HealthCheckResult(\n                :performance,\n                HealthCheck.DEGRADED,\n                \"$(length(critical_slow)) operations significantly exceed targets\",\n                0.0,\n                time() * 1000,\n                Dict(\"slow_operations\" => length(critical_slow)),\n                Dict{Symbol, HealthCheck.HealthStatus}()\n            )\n        else\n            return true\n        end\n    })\nend\n\n\"\"\"Start background monitoring tasks.\"\"\"\nfunction start_background_monitoring!(system::ProductionHardeningSystem)\n    @info \"Starting background monitoring tasks\"\n    \n    # Note: In a real production system, you would use proper task scheduling\n    # This is a simplified version for demonstration\n    \n    # Schedule periodic health checks\n    # In production, use a proper scheduler like cron or systemd timers\n    \n    @info \"Background monitoring configured (would start tasks in production)\"\nend\n\n\"\"\"Gracefully shutdown the production hardening system.\"\"\"\nfunction shutdown!(system::ProductionHardeningSystem)\n    @info \"Shutting down production hardening system\"\n    \n    system.enabled[] = false\n    \n    # Generate final report\n    final_metrics = get_system_status(system)\n    \n    @info \"Production hardening system shutdown complete\" \n        total_alerts=length(final_metrics.alerts)\n        uptime_hours=final_metrics.system_uptime_ms/1000/3600\nend\n\nend # module