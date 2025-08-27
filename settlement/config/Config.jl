"""
    Config

Configuration management for the Settlement system. Provides type-safe
configuration with validation, hot-reloading, and environment-specific overrides.

# Features
- Type-safe configuration with validation
- Hot-reloading without restart
- Environment-specific overrides
- Configuration versioning
- Secret management integration
"""
module Config

using TOML
using JSON3
using Dates
using ..Types

# Configuration structures
Base.@kwdef struct PerformanceConfig
    max_latency_ms::Int = 100
    enable_parallel_execution::Bool = true
    max_parallel_routes::Int = 8
    batch_size::Int = 50
    cache_ttl_seconds::Int = 300
    connection_pool_size::Int = 20
    request_timeout_ms::Int = 5000
    enable_compression::Bool = true
end

Base.@kwdef struct SecurityConfig
    enable_mev_protection::Bool = true
    sandwich_detection_threshold::Float64 = 0.95
    commit_reveal_timeout_blocks::Int = 10
    max_slippage_percent::Float64 = 2.0
    require_signature_validation::Bool = true
    enable_rate_limiting::Bool = true
    rate_limit_requests_per_second::Int = 100
    enable_ip_whitelist::Bool = false
    whitelisted_ips::Vector{String} = String[]
end

Base.@kwdef struct RoutingConfig
    enable_multi_path::Bool = true
    max_path_splits::Int = 5
    min_path_value::Float64 = 100.0
    price_impact_threshold::Float64 = 0.01
    enable_dynamic_routing::Bool = true
    routing_algorithm::Symbol = :optimal  # :optimal, :fast, :balanced
    enable_route_caching::Bool = true
    route_cache_duration_ms::Int = 1000
end

Base.@kwdef struct MonitoringConfig
    enable_metrics::Bool = true
    metrics_port::Int = 9090
    enable_tracing::Bool = true
    trace_sample_rate::Float64 = 0.1
    enable_alerts::Bool = true
    alert_channels::Vector{String} = ["slack", "pagerduty"]
    health_check_interval_seconds::Int = 30
    enable_profiling::Bool = false
    log_level::Symbol = :info  # :debug, :info, :warn, :error
end

Base.@kwdef struct ProtocolConfig
    supported_protocols::Vector{Symbol} = [:uniswap_v2, :uniswap_v3, :balancer, :curve]
    protocol_endpoints::Dict{Symbol, String} = Dict()
    protocol_timeouts::Dict{Symbol, Int} = Dict()
    enable_protocol_fallback::Bool = true
    fallback_order::Vector{Symbol} = [:uniswap_v3, :uniswap_v2]
end

Base.@kwdef struct CircuitBreakerConfig
    enable_circuit_breakers::Bool = true
    failure_threshold::Int = 5
    success_threshold::Int = 3
    timeout_seconds::Int = 60
    half_open_max_attempts::Int = 3
    monitor_endpoints::Vector{String} = String[]
end

Base.@kwdef struct RetryConfig
    enable_retries::Bool = true
    max_attempts::Int = 3
    base_delay_ms::Int = 100
    max_delay_ms::Int = 5000
    exponential_base::Float64 = 2.0
    jitter_factor::Float64 = 0.1
    retryable_errors::Vector{Symbol} = [:timeout, :network, :rate_limit]
end

Base.@kwdef struct CacheConfig
    enable_caching::Bool = true
    cache_provider::Symbol = :memory  # :memory, :redis, :hybrid
    max_memory_mb::Int = 512
    eviction_policy::Symbol = :lru  # :lru, :lfu, :ttl
    enable_warming::Bool = true
    warming_interval_seconds::Int = 300
    compression_threshold_bytes::Int = 1024
end

# Main configuration structure
mutable struct SettlementConfig
    version::String
    environment::Symbol  # :development, :staging, :production
    performance::PerformanceConfig
    security::SecurityConfig
    routing::RoutingConfig
    monitoring::MonitoringConfig
    protocols::ProtocolConfig
    circuit_breakers::CircuitBreakerConfig
    retry::RetryConfig
    cache::CacheConfig
    custom::Dict{String, Any}
    loaded_at::DateTime
    config_file::Union{String, Nothing}
    
    function SettlementConfig(;
        version::String = "1.0.0",
        environment::Symbol = :development,
        performance::PerformanceConfig = PerformanceConfig(),
        security::SecurityConfig = SecurityConfig(),
        routing::RoutingConfig = RoutingConfig(),
        monitoring::MonitoringConfig = MonitoringConfig(),
        protocols::ProtocolConfig = ProtocolConfig(),
        circuit_breakers::CircuitBreakerConfig = CircuitBreakerConfig(),
        retry::RetryConfig = RetryConfig(),
        cache::CacheConfig = CacheConfig(),
        custom::Dict{String, Any} = Dict{String, Any}(),
        config_file::Union{String, Nothing} = nothing
    )
        new(version, environment, performance, security, routing,
            monitoring, protocols, circuit_breakers, retry, cache,
            custom, now(), config_file)
    end
end

# Configuration loading
function load_config(file_path::String)::SettlementConfig
    if !isfile(file_path)
        throw(ArgumentError("Configuration file not found: $file_path"))
    end
    
    config_data = TOML.parsefile(file_path)
    
    # Parse environment
    environment = get(config_data, "environment", "development")
    environment = Symbol(environment)
    
    # Load each section
    perf = get(config_data, "performance", Dict())
    sec = get(config_data, "security", Dict())
    route = get(config_data, "routing", Dict())
    mon = get(config_data, "monitoring", Dict())
    proto = get(config_data, "protocols", Dict())
    cb = get(config_data, "circuit_breakers", Dict())
    retry = get(config_data, "retry", Dict())
    cache = get(config_data, "cache", Dict())
    custom = get(config_data, "custom", Dict())
    
    config = SettlementConfig(
        version = get(config_data, "version", "1.0.0"),
        environment = environment,
        performance = parse_performance_config(perf),
        security = parse_security_config(sec),
        routing = parse_routing_config(route),
        monitoring = parse_monitoring_config(mon),
        protocols = parse_protocol_config(proto),
        circuit_breakers = parse_circuit_breaker_config(cb),
        retry = parse_retry_config(retry),
        cache = parse_cache_config(cache),
        custom = custom,
        config_file = file_path
    )
    
    validate_config(config)
    return config
end

function parse_performance_config(data::Dict)::PerformanceConfig
    PerformanceConfig(
        max_latency_ms = get(data, "max_latency_ms", 100),
        enable_parallel_execution = get(data, "enable_parallel_execution", true),
        max_parallel_routes = get(data, "max_parallel_routes", 8),
        batch_size = get(data, "batch_size", 50),
        cache_ttl_seconds = get(data, "cache_ttl_seconds", 300),
        connection_pool_size = get(data, "connection_pool_size", 20),
        request_timeout_ms = get(data, "request_timeout_ms", 5000),
        enable_compression = get(data, "enable_compression", true)
    )
end

function parse_security_config(data::Dict)::SecurityConfig
    SecurityConfig(
        enable_mev_protection = get(data, "enable_mev_protection", true),
        sandwich_detection_threshold = get(data, "sandwich_detection_threshold", 0.95),
        commit_reveal_timeout_blocks = get(data, "commit_reveal_timeout_blocks", 10),
        max_slippage_percent = get(data, "max_slippage_percent", 2.0),
        require_signature_validation = get(data, "require_signature_validation", true),
        enable_rate_limiting = get(data, "enable_rate_limiting", true),
        rate_limit_requests_per_second = get(data, "rate_limit_requests_per_second", 100),
        enable_ip_whitelist = get(data, "enable_ip_whitelist", false),
        whitelisted_ips = get(data, "whitelisted_ips", String[])
    )
end

function parse_routing_config(data::Dict)::RoutingConfig
    RoutingConfig(
        enable_multi_path = get(data, "enable_multi_path", true),
        max_path_splits = get(data, "max_path_splits", 5),
        min_path_value = get(data, "min_path_value", 100.0),
        price_impact_threshold = get(data, "price_impact_threshold", 0.01),
        enable_dynamic_routing = get(data, "enable_dynamic_routing", true),
        routing_algorithm = Symbol(get(data, "routing_algorithm", "optimal")),
        enable_route_caching = get(data, "enable_route_caching", true),
        route_cache_duration_ms = get(data, "route_cache_duration_ms", 1000)
    )
end

function parse_monitoring_config(data::Dict)::MonitoringConfig
    MonitoringConfig(
        enable_metrics = get(data, "enable_metrics", true),
        metrics_port = get(data, "metrics_port", 9090),
        enable_tracing = get(data, "enable_tracing", true),
        trace_sample_rate = get(data, "trace_sample_rate", 0.1),
        enable_alerts = get(data, "enable_alerts", true),
        alert_channels = get(data, "alert_channels", ["slack", "pagerduty"]),
        health_check_interval_seconds = get(data, "health_check_interval_seconds", 30),
        enable_profiling = get(data, "enable_profiling", false),
        log_level = Symbol(get(data, "log_level", "info"))
    )
end

function parse_protocol_config(data::Dict)::ProtocolConfig
    protocols = get(data, "supported_protocols", ["uniswap_v2", "uniswap_v3", "balancer", "curve"])
    protocols = [Symbol(p) for p in protocols]
    
    endpoints = get(data, "protocol_endpoints", Dict())
    endpoints = Dict(Symbol(k) => v for (k, v) in endpoints)
    
    timeouts = get(data, "protocol_timeouts", Dict())
    timeouts = Dict(Symbol(k) => v for (k, v) in timeouts)
    
    fallback = get(data, "fallback_order", ["uniswap_v3", "uniswap_v2"])
    fallback = [Symbol(p) for p in fallback]
    
    ProtocolConfig(
        supported_protocols = protocols,
        protocol_endpoints = endpoints,
        protocol_timeouts = timeouts,
        enable_protocol_fallback = get(data, "enable_protocol_fallback", true),
        fallback_order = fallback
    )
end

function parse_circuit_breaker_config(data::Dict)::CircuitBreakerConfig
    CircuitBreakerConfig(
        enable_circuit_breakers = get(data, "enable_circuit_breakers", true),
        failure_threshold = get(data, "failure_threshold", 5),
        success_threshold = get(data, "success_threshold", 3),
        timeout_seconds = get(data, "timeout_seconds", 60),
        half_open_max_attempts = get(data, "half_open_max_attempts", 3),
        monitor_endpoints = get(data, "monitor_endpoints", String[])
    )
end

function parse_retry_config(data::Dict)::RetryConfig
    errors = get(data, "retryable_errors", ["timeout", "network", "rate_limit"])
    errors = [Symbol(e) for e in errors]
    
    RetryConfig(
        enable_retries = get(data, "enable_retries", true),
        max_attempts = get(data, "max_attempts", 3),
        base_delay_ms = get(data, "base_delay_ms", 100),
        max_delay_ms = get(data, "max_delay_ms", 5000),
        exponential_base = get(data, "exponential_base", 2.0),
        jitter_factor = get(data, "jitter_factor", 0.1),
        retryable_errors = errors
    )
end

function parse_cache_config(data::Dict)::CacheConfig
    CacheConfig(
        enable_caching = get(data, "enable_caching", true),
        cache_provider = Symbol(get(data, "cache_provider", "memory")),
        max_memory_mb = get(data, "max_memory_mb", 512),
        eviction_policy = Symbol(get(data, "eviction_policy", "lru")),
        enable_warming = get(data, "enable_warming", true),
        warming_interval_seconds = get(data, "warming_interval_seconds", 300),
        compression_threshold_bytes = get(data, "compression_threshold_bytes", 1024)
    )
end

# Configuration validation
function validate_config(config::SettlementConfig)
    # Performance validation
    @assert config.performance.max_latency_ms > 0 "max_latency_ms must be positive"
    @assert config.performance.max_parallel_routes > 0 "max_parallel_routes must be positive"
    @assert config.performance.batch_size > 0 "batch_size must be positive"
    
    # Security validation
    @assert 0 <= config.security.sandwich_detection_threshold <= 1 "sandwich_detection_threshold must be between 0 and 1"
    @assert config.security.max_slippage_percent >= 0 "max_slippage_percent must be non-negative"
    @assert config.security.rate_limit_requests_per_second > 0 "rate_limit_requests_per_second must be positive"
    
    # Routing validation
    @assert config.routing.max_path_splits > 0 "max_path_splits must be positive"
    @assert config.routing.min_path_value >= 0 "min_path_value must be non-negative"
    @assert config.routing.price_impact_threshold >= 0 "price_impact_threshold must be non-negative"
    @assert config.routing.routing_algorithm in [:optimal, :fast, :balanced] "Invalid routing_algorithm"
    
    # Monitoring validation
    @assert config.monitoring.metrics_port > 0 "metrics_port must be positive"
    @assert 0 <= config.monitoring.trace_sample_rate <= 1 "trace_sample_rate must be between 0 and 1"
    @assert config.monitoring.log_level in [:debug, :info, :warn, :error] "Invalid log_level"
    
    # Cache validation
    @assert config.cache.max_memory_mb > 0 "max_memory_mb must be positive"
    @assert config.cache.cache_provider in [:memory, :redis, :hybrid] "Invalid cache_provider"
    @assert config.cache.eviction_policy in [:lru, :lfu, :ttl] "Invalid eviction_policy"
    
    return true
end

# Hot reload support
mutable struct ConfigManager
    config::SettlementConfig
    file_watcher::Union{Timer, Nothing}
    reload_callbacks::Vector{Function}
    last_modified::DateTime
    
    function ConfigManager(config::SettlementConfig)
        new(config, nothing, Function[], now())
    end
end

function enable_hot_reload!(manager::ConfigManager, check_interval::Int = 5)
    if manager.config.config_file === nothing
        @warn "Cannot enable hot reload without config file"
        return
    end
    
    manager.file_watcher = Timer(check_interval; interval=check_interval) do timer
        check_and_reload!(manager)
    end
end

function check_and_reload!(manager::ConfigManager)
    file_path = manager.config.config_file
    if file_path === nothing || !isfile(file_path)
        return
    end
    
    mtime = Dates.unix2datetime(mtime(file_path))
    if mtime > manager.last_modified
        try
            new_config = load_config(file_path)
            manager.config = new_config
            manager.last_modified = mtime
            
            # Trigger callbacks
            for callback in manager.reload_callbacks
                callback(new_config)
            end
            
            @info "Configuration reloaded" file=file_path
        catch e
            @error "Failed to reload configuration" error=e
        end
    end
end

function register_reload_callback!(manager::ConfigManager, callback::Function)
    push!(manager.reload_callbacks, callback)
end

# Export everything
export SettlementConfig, ConfigManager
export PerformanceConfig, SecurityConfig, RoutingConfig
export MonitoringConfig, ProtocolConfig, CircuitBreakerConfig
export RetryConfig, CacheConfig
export load_config, validate_config
export enable_hot_reload!, register_reload_callback!

end # module Config