module HealthCheck

using Base.Threads: Atomic, SpinLock
using Dates
using Logging
using Statistics
using Sys
export HealthChecker, HealthStatus, HealthCheckResult, ComponentHealth, HealthDetailValue
export create_health_checker, add_health_check, run_health_checks
export get_system_health, check_readiness, check_liveness
export ResourceMonitor, monitor_resources

"""
Health status levels for system components.
"""
@enum HealthStatus begin
    HEALTHY     # Component is fully operational
    DEGRADED    # Component has issues but is functional
    UNHEALTHY   # Component is not functional
    CRITICAL    # Component failure affects system stability
    UNKNOWN     # Health status cannot be determined
end

"""
Union type for health check detail values - replaces Any type for type safety.
"""
const HealthDetailValue = Union{String, Float64, Int64, Bool, Vector{String}, NamedTuple}

"""
Result of a health check operation.
"""
struct HealthCheckResult
    component_name::Symbol
    status::HealthStatus
    message::String
    latency_ms::Float64
    timestamp::Float64
    details::Dict{String, HealthDetailValue}
    dependencies_status::Dict{Symbol, HealthStatus}
end

"""
Component health configuration and state.
"""
mutable struct ComponentHealth
    name::Symbol
    check_function::Function
    timeout_ms::Float64
    interval_ms::Float64
    dependencies::Set{Symbol}
    last_check_time::Float64
    last_result::Union{HealthCheckResult, Nothing}
    failure_count::Int
    max_failures::Int
    enabled::Bool
end

"""
Resource monitoring for system health.
"""
mutable struct ResourceMonitor
    cpu_threshold_percent::Float64
    memory_threshold_percent::Float64
    disk_threshold_percent::Float64
    check_interval_ms::Float64
    last_check::Float64
    current_stats::Dict{String, Float64}
    alert_callbacks::Vector{Function}
    lock::SpinLock
end

"""
Production health checker with comprehensive monitoring.
"""
mutable struct HealthChecker
    components::Dict{Symbol, ComponentHealth}
    resource_monitor::ResourceMonitor
    global_status::Atomic{HealthStatus}
    system_start_time::Float64
    last_full_check::Float64
    check_history::Vector{Tuple{Float64, HealthStatus}}
    critical_components::Set{Symbol}
    lock::SpinLock
    background_checks_enabled::Bool
end

"""
    create_health_checker(; kwargs...)

Create a production health checker with comprehensive monitoring capabilities.
"""
function create_health_checker(;
    cpu_threshold_percent::Float64=80.0,
    memory_threshold_percent::Float64=85.0,
    disk_threshold_percent::Float64=90.0,
    resource_check_interval_ms::Float64=30000.0,
    enable_background_checks::Bool=true)
    
    resource_monitor = ResourceMonitor(
        cpu_threshold_percent,
        memory_threshold_percent,
        disk_threshold_percent,
        resource_check_interval_ms,
        0.0,
        Dict{String, Float64}(),
        Function[],
        SpinLock()
    )
    
    current_time = time() * 1000
    
    checker = HealthChecker(
        Dict{Symbol, ComponentHealth}(),
        resource_monitor,
        Atomic{HealthStatus}(UNKNOWN),
        current_time,
        0.0,
        Tuple{Float64, HealthStatus}[],
        Set{Symbol}(),
        SpinLock(),
        enable_background_checks
    )
    
    # Add default system health checks
    add_default_health_checks!(checker)
    
    return checker
end

"""
    add_health_check(checker, name, check_fn; kwargs...)

Add a health check for a system component.
"""
function add_health_check(checker::HealthChecker, 
                         name::Symbol,
                         check_fn::Function;
                         timeout_ms::Float64=5000.0,
                         interval_ms::Float64=60000.0,
                         dependencies::Set{Symbol}=Set{Symbol}(),
                         max_failures::Int=3,
                         is_critical::Bool=false)
    
    lock(checker.lock) do
        component = ComponentHealth(
            name,
            check_fn,
            timeout_ms,
            interval_ms,
            dependencies,
            0.0,
            nothing,
            0,
            max_failures,
            true
        )
        
        checker.components[name] = component
        
        if is_critical
            push!(checker.critical_components, name)
        end
        
        @info "Health check added" component=name is_critical=is_critical dependencies=dependencies
    end
end

"""
    run_health_checks(checker; component=nothing)

Run health checks for all components or a specific component.
"""
function run_health_checks(checker::HealthChecker; component::Union{Symbol, Nothing}=nothing)
    current_time = time() * 1000
    results = Dict{Symbol, HealthCheckResult}()
    
    lock(checker.lock) do
        components_to_check = if component !== nothing
            haskey(checker.components, component) ? [component] : Symbol[]
        else
            collect(keys(checker.components))
        end
        
        # Sort by dependencies (dependencies first)
        sorted_components = sort_by_dependencies(checker, components_to_check)
        
        for comp_name in sorted_components
            comp = checker.components[comp_name]
            
            if !comp.enabled
                continue
            end
            
            # Check if it's time for this component's health check
            if current_time - comp.last_check_time < comp.interval_ms && comp.last_result !== nothing
                results[comp_name] = comp.last_result
                continue
            end
            
            # Get dependency status
            dep_status = get_dependency_status(checker, comp.dependencies, results)
            
            # Perform health check with timeout
            result = perform_health_check(comp, dep_status, current_time)
            
            # Update component state
            comp.last_check_time = current_time
            comp.last_result = result
            
            if result.status in [UNHEALTHY, CRITICAL]
                comp.failure_count += 1
            else
                comp.failure_count = 0
            end
            
            results[comp_name] = result
            
            @debug "Health check completed" 
                component=comp_name 
                status=result.status 
                latency_ms=result.latency_ms
        end
        
        # Update global status
        global_status = determine_global_status(checker, results)
        checker.global_status[] = global_status
        
        # Record in history
        push!(checker.check_history, (current_time, global_status))
        
        # Cleanup old history (keep last 24 hours)
        cutoff_time = current_time - 24 * 3600 * 1000.0
        filter!(entry -> entry[1] >= cutoff_time, checker.check_history)
        
        checker.last_full_check = current_time
    end
    
    return results
end

"""
Perform individual health check with timeout protection.
"""
function perform_health_check(component::ComponentHealth, 
                             dependency_status::Dict{Symbol, HealthStatus},
                             current_time::Float64)::HealthCheckResult
    
    start_time = time() * 1000
    
    try
        # Simple timeout implementation
        check_task = @async component.check_function()
        
        # Wait for result or timeout
        result = nothing
        elapsed = 0.0
        
        while !istaskdone(check_task) && elapsed < component.timeout_ms
            sleep(0.01)
            elapsed = (time() * 1000) - start_time
        end
        
        if istaskdone(check_task)
            if istaskfailed(check_task)
                error_msg = "Health check failed: $(check_task.exception)"
                @error error_msg component=component.name
                
                return HealthCheckResult(
                    component.name,
                    UNHEALTHY,
                    error_msg,
                    elapsed,
                    current_time,
                    Dict{String, HealthDetailValue}("error" => string(check_task.exception)),
                    dependency_status
                )
            else
                # Health check completed successfully
                check_result = check_task.result
                
                if isa(check_result, HealthCheckResult)
                    return check_result
                elseif isa(check_result, Bool)
                    status = check_result ? HEALTHY : UNHEALTHY
                    message = check_result ? "Health check passed" : "Health check failed"
                    
                    return HealthCheckResult(
                        component.name,
                        status,
                        message,
                        elapsed,
                        current_time,
                        Dict{String, HealthDetailValue}(),
                        dependency_status
                    )
                else
                    # Assume healthy if unrecognized return type
                    return HealthCheckResult(
                        component.name,
                        HEALTHY,
                        "Health check returned: $(check_result)",
                        elapsed,
                        current_time,
                        Dict{String, HealthDetailValue}("result" => string(check_result)),
                        dependency_status
                    )
                end
            end
        else
            # Timeout occurred
            @warn "Health check timeout" component=component.name timeout_ms=component.timeout_ms
            
            return HealthCheckResult(
                component.name,
                DEGRADED,
                "Health check timed out after $(component.timeout_ms)ms",
                component.timeout_ms,
                current_time,
                Dict{String, HealthDetailValue}("timeout" => true),
                dependency_status
            )
        end
        
    catch e
        elapsed = (time() * 1000) - start_time
        error_msg = "Health check exception: $(e)"
        @error error_msg component=component.name exception=e
        
        return HealthCheckResult(
            component.name,
            CRITICAL,
            error_msg,
            elapsed,
            current_time,
            Dict{String, HealthDetailValue}("exception" => string(e)),
            dependency_status
        )
    end
end

"""
Get status of component dependencies.
"""
function get_dependency_status(checker::HealthChecker, 
                              dependencies::Set{Symbol},
                              current_results::Dict{Symbol, HealthCheckResult})
    
    dep_status = Dict{Symbol, HealthStatus}()
    
    for dep in dependencies
        if haskey(current_results, dep)
            dep_status[dep] = current_results[dep].status
        elseif haskey(checker.components, dep) && checker.components[dep].last_result !== nothing
            dep_status[dep] = checker.components[dep].last_result.status
        else
            dep_status[dep] = UNKNOWN
        end
    end
    
    return dep_status
end

"""
Sort components by dependencies to ensure proper check order.
"""
function sort_by_dependencies(checker::HealthChecker, components::Vector{Symbol})
    # Simple topological sort for dependency resolution
    sorted = Symbol[]
    remaining = Set(components)
    
    while !isempty(remaining)
        # Find components with no unresolved dependencies
        ready = filter(comp -> {
            deps = checker.components[comp].dependencies
            isempty(setdiff(deps, sorted))
        }, remaining)
        
        if isempty(ready)
            # Circular dependency or missing dependency, add remaining components
            append!(sorted, collect(remaining))
            break
        end
        
        append!(sorted, ready)
        setdiff!(remaining, ready)
    end
    
    return sorted
end

"""
Determine overall system health status.
"""
function determine_global_status(checker::HealthChecker, results::Dict{Symbol, HealthCheckResult})
    if isempty(results)
        return UNKNOWN
    end
    
    # Check critical components first
    for critical_comp in checker.critical_components
        if haskey(results, critical_comp)
            result = results[critical_comp]
            if result.status == CRITICAL
                return CRITICAL
            elseif result.status == UNHEALTHY
                return UNHEALTHY
            end
        end
    end
    
    # Count status distribution
    status_counts = Dict{HealthStatus, Int}()
    for result in values(results)
        status_counts[result.status] = get(status_counts, result.status, 0) + 1
    end
    
    total_components = length(results)
    critical_count = get(status_counts, CRITICAL, 0)
    unhealthy_count = get(status_counts, UNHEALTHY, 0)
    degraded_count = get(status_counts, DEGRADED, 0)
    
    if critical_count > 0
        return CRITICAL
    elseif unhealthy_count > total_components * 0.3  # >30% unhealthy
        return UNHEALTHY
    elseif unhealthy_count > 0 || degraded_count > total_components * 0.2  # >20% degraded
        return DEGRADED
    else
        return HEALTHY
    end
end

"""
    get_system_health(checker)

Get comprehensive system health status.
"""
function get_system_health(checker::HealthChecker)
    current_time = time() * 1000
    
    # Run health checks if needed
    results = run_health_checks(checker)
    
    # Get resource status
    resource_status = monitor_resources(checker.resource_monitor)
    
    # Calculate uptime
    uptime_ms = current_time - checker.system_start_time
    
    lock(checker.lock) do
        component_summary = Dict{Symbol, NamedTuple}()
        
        for (name, result) in results
            component_summary[name] = (
                status = result.status,
                message = result.message,
                last_check = result.timestamp,
                latency_ms = result.latency_ms,
                failure_count = checker.components[name].failure_count
            )
        end
        
        return (
            overall_status = checker.global_status[],
            uptime_ms = uptime_ms,
            last_check_time = checker.last_full_check,
            component_health = component_summary,
            resource_usage = resource_status,
            critical_components = collect(checker.critical_components),
            health_history_24h = length(checker.check_history)
        )
    end
end

"""
    check_readiness(checker)

Check if system is ready to serve requests (Kubernetes readiness probe).
"""
function check_readiness(checker::HealthChecker)
    results = run_health_checks(checker)
    
    # System is ready if no critical components are unhealthy
    for (name, result) in results
        if name in checker.critical_components && result.status in [UNHEALTHY, CRITICAL]
            return false
        end
    end
    
    # Check resource constraints
    resource_status = monitor_resources(checker.resource_monitor)
    if resource_status.memory_percent > 95.0 || resource_status.cpu_percent > 95.0
        return false
    end
    
    return true
end

"""
    check_liveness(checker)

Check if system is alive and responding (Kubernetes liveness probe).
"""
function check_liveness(checker::HealthChecker)
    current_time = time() * 1000
    
    # System is alive if we can respond to this check
    # and haven't been stuck for too long
    if checker.last_full_check > 0
        time_since_last_check = current_time - checker.last_full_check
        if time_since_last_check > 300000.0  # 5 minutes
            @warn "System appears stuck - no health checks in 5 minutes"
            return false
        end
    end
    
    # Check if we can still allocate memory and perform basic operations
    try
        test_array = rand(100)
        sum(test_array)
        return true
    catch e
        @error "Liveness check failed - basic operations failing" exception=e
        return false
    end
end

"""
    monitor_resources(resource_monitor)

Monitor system resources (CPU, memory, disk).
"""
function monitor_resources(monitor::ResourceMonitor)
    current_time = time() * 1000
    
    # Check if it's time for resource monitoring
    if current_time - monitor.last_check < monitor.check_interval_ms && !isempty(monitor.current_stats)
        return (
            cpu_percent = get(monitor.current_stats, "cpu_percent", 0.0),
            memory_percent = get(monitor.current_stats, "memory_percent", 0.0),
            memory_used_gb = get(monitor.current_stats, "memory_used_gb", 0.0),
            memory_total_gb = get(monitor.current_stats, "memory_total_gb", 0.0),
            disk_usage_percent = get(monitor.current_stats, "disk_percent", 0.0),
            timestamp = monitor.last_check
        )
    end
    
    lock(monitor.lock) do
        try
            # Get memory information
            memory_info = Sys.free_memory()
            total_memory = Sys.total_memory()
            used_memory = total_memory - memory_info
            memory_percent = (used_memory / total_memory) * 100.0
            
            # CPU usage (simplified - would need system-specific implementation for accurate CPU)
            cpu_percent = 0.0  # Placeholder - would need platform-specific implementation
            
            # Disk usage (simplified)
            disk_percent = 0.0  # Placeholder - would need platform-specific implementation
            
            # Update current stats
            monitor.current_stats = Dict(
                "cpu_percent" => cpu_percent,
                "memory_percent" => memory_percent,
                "memory_used_gb" => used_memory / (1024^3),
                "memory_total_gb" => total_memory / (1024^3),
                "disk_percent" => disk_percent
            )
            
            monitor.last_check = current_time
            
            # Check for alerts
            check_resource_alerts(monitor)
            
            return (
                cpu_percent = cpu_percent,
                memory_percent = memory_percent,
                memory_used_gb = monitor.current_stats["memory_used_gb"],
                memory_total_gb = monitor.current_stats["memory_total_gb"],
                disk_usage_percent = disk_percent,
                timestamp = current_time
            )
            
        catch e
            @error "Resource monitoring failed" exception=e
            return (
                cpu_percent = 0.0,
                memory_percent = 0.0,
                memory_used_gb = 0.0,
                memory_total_gb = 0.0,
                disk_usage_percent = 0.0,
                timestamp = current_time
            )
        end
    end
end

"""
Check for resource usage alerts.
"""
function check_resource_alerts(monitor::ResourceMonitor)
    stats = monitor.current_stats
    
    cpu_percent = get(stats, "cpu_percent", 0.0)
    memory_percent = get(stats, "memory_percent", 0.0)
    disk_percent = get(stats, "disk_percent", 0.0)
    
    if cpu_percent > monitor.cpu_threshold_percent
        @warn "High CPU usage detected" cpu_percent=cpu_percent threshold=monitor.cpu_threshold_percent
        for callback in monitor.alert_callbacks
            try
                callback(:cpu, cpu_percent, monitor.cpu_threshold_percent)
            catch e
                @error "Alert callback failed" callback=callback exception=e
            end
        end
    end
    
    if memory_percent > monitor.memory_threshold_percent
        @warn "High memory usage detected" memory_percent=memory_percent threshold=monitor.memory_threshold_percent
        for callback in monitor.alert_callbacks
            try
                callback(:memory, memory_percent, monitor.memory_threshold_percent)
            catch e
                @error "Alert callback failed" callback=callback exception=e
            end
        end
    end
    
    if disk_percent > monitor.disk_threshold_percent
        @warn "High disk usage detected" disk_percent=disk_percent threshold=monitor.disk_threshold_percent
        for callback in monitor.alert_callbacks
            try
                callback(:disk, disk_percent, monitor.disk_threshold_percent)
            catch e
                @error "Alert callback failed" callback=callback exception=e
            end
        end
    end
end

"""
Add default system health checks.
"""
function add_default_health_checks!(checker::HealthChecker)
    # Memory health check
    add_health_check(checker, :memory, () -> {
        resource_status = monitor_resources(checker.resource_monitor)
        if resource_status.memory_percent > 90.0
            return HealthCheckResult(
                :memory,
                UNHEALTHY,
                "Memory usage critical: $(round(resource_status.memory_percent, digits=1))%",
                0.0,
                time() * 1000,
                Dict{String, HealthDetailValue}("memory_percent" => resource_status.memory_percent),
                Dict{Symbol, HealthStatus}()
            )
        elseif resource_status.memory_percent > 80.0
            return HealthCheckResult(
                :memory,
                DEGRADED,
                "Memory usage high: $(round(resource_status.memory_percent, digits=1))%",
                0.0,
                time() * 1000,
                Dict{String, HealthDetailValue}("memory_percent" => resource_status.memory_percent),
                Dict{Symbol, HealthStatus}()
            )
        else
            return true
        end
    }, is_critical=true)
    
    # Basic connectivity health check
    add_health_check(checker, :system_basic, () -> {
        try
            # Test basic Julia operations
            test_result = 1 + 1
            current_time = time()
            return test_result == 2 && current_time > 0
        catch e
            return false
        end
    }, is_critical=true)
end

"""
Add alert callback for resource monitoring.
"""
function add_resource_alert_callback(checker::HealthChecker, callback::Function)
    lock(checker.resource_monitor.lock) do
        push!(checker.resource_monitor.alert_callbacks, callback)
    end
end

end # module