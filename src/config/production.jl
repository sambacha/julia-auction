module ProductionConfig

using ..CircuitBreaker: CircuitBreakerConfig, BackoffStrategy
using ..ErrorHandler: RetryPolicy
using Base.Threads: Threads
export ProductionConfiguration, create_production_config
export get_timeout_config, get_retry_config, get_circuit_breaker_config
export get_monitoring_config, get_performance_config

"""
Production configuration for the Julia auction system.
Optimized for <10ms p99 latency and high reliability.
"""
struct ProductionConfiguration
    # Performance targets
    p99_latency_target_ms::Float64
    p95_latency_target_ms::Float64
    max_acceptable_latency_ms::Float64

    # Timeout configurations
    auction_timeout_ms::Float64
    settlement_timeout_ms::Float64
    cfmm_bridge_timeout_ms::Float64
    phantom_auction_timeout_ms::Float64
    default_operation_timeout_ms::Float64

    # Circuit breaker settings
    circuit_breaker_failure_threshold::Int
    circuit_breaker_recovery_threshold::Int
    circuit_breaker_timeout_ms::Float64
    circuit_breaker_slow_call_threshold_ms::Float64
    circuit_breaker_volume_threshold::Int
    circuit_breaker_error_percentage_threshold::Float64

    # Retry policy settings
    max_retry_attempts::Int
    base_retry_delay_ms::Float64
    max_retry_delay_ms::Float64
    retry_backoff_strategy::BackoffStrategy
    retry_jitter_ratio::Float64

    # Monitoring thresholds
    slow_operation_threshold_ms::Float64
    memory_usage_threshold_percent::Float64
    cpu_usage_threshold_percent::Float64
    disk_usage_threshold_percent::Float64

    # Resource limits
    max_concurrent_auctions::Int
    max_pending_settlements::Int
    max_memory_usage_mb::Int
    thread_pool_size::Int

    # Health check intervals
    health_check_interval_ms::Float64
    resource_monitor_interval_ms::Float64
    performance_report_interval_ms::Float64

    # Alerting thresholds
    sla_violation_alert_threshold_percent::Float64
    error_rate_alert_threshold_percent::Float64
    consecutive_failures_alert_threshold::Int

    # Data retention
    metrics_retention_hours::Int
    log_retention_days::Int
    performance_data_retention_hours::Int

    # Feature flags
    enable_circuit_breakers::Bool
    enable_adaptive_timeouts::Bool
    enable_performance_monitoring::Bool
    enable_resource_monitoring::Bool
    enable_graceful_degradation::Bool
    enable_background_health_checks::Bool
end

"""
    create_production_config(; kwargs...)

Create optimized production configuration for the auction system.
"""
function create_production_config(;
    # Performance targets (aggressive for DeFi)
    p99_latency_target_ms::Float64 = 10.0,        # <10ms p99 target
    p95_latency_target_ms::Float64 = 5.0,         # <5ms p95 target
    max_acceptable_latency_ms::Float64 = 100.0,   # Hard limit

    # Timeout configurations (optimized for speed)
    auction_timeout_ms::Float64 = 50.0,           # Fast auction processing
    settlement_timeout_ms::Float64 = 200.0,       # Settlement operations
    cfmm_bridge_timeout_ms::Float64 = 100.0,      # CFMM bridge calls
    phantom_auction_timeout_ms::Float64 = 30.0,   # Phantom auction creation
    default_operation_timeout_ms::Float64 = 75.0, # Default for other ops

    # Circuit breaker (aggressive protection)
    circuit_breaker_failure_threshold::Int = 3,
    circuit_breaker_recovery_threshold::Int = 2,
    circuit_breaker_timeout_ms::Float64 = 15000.0,  # 15s recovery time
    circuit_breaker_slow_call_threshold_ms::Float64 = 25.0,  # 25ms threshold
    circuit_breaker_volume_threshold::Int = 5,      # Min calls before trip
    circuit_breaker_error_percentage_threshold::Float64 = 40.0,  # 40% error rate

    # Retry policy (fast retries)
    max_retry_attempts::Int = 2,                   # Limited retries for speed
    base_retry_delay_ms::Float64 = 10.0,          # Very fast initial retry
    max_retry_delay_ms::Float64 = 100.0,          # Cap retry delays
    retry_backoff_strategy::BackoffStrategy = BackoffStrategy.EXPONENTIAL_JITTER,
    retry_jitter_ratio::Float64 = 0.2,

    # Monitoring (strict thresholds)
    slow_operation_threshold_ms::Float64 = 15.0,   # Anything >15ms is slow
    memory_usage_threshold_percent::Float64 = 75.0,
    cpu_usage_threshold_percent::Float64 = 70.0,
    disk_usage_threshold_percent::Float64 = 80.0,

    # Resource limits (high performance)
    max_concurrent_auctions::Int = min(1000, Threads.nthreads() * 50),
    max_pending_settlements::Int = min(500, Threads.nthreads() * 25),
    max_memory_usage_mb::Int = 4096,               # 4GB limit
    thread_pool_size::Int = max(8, Threads.nthreads()),

    # Health check intervals (frequent monitoring)
    health_check_interval_ms::Float64 = 30000.0,   # 30s health checks
    resource_monitor_interval_ms::Float64 = 10000.0,  # 10s resource monitoring
    performance_report_interval_ms::Float64 = 60000.0,  # 1min performance reports

    # Alerting (sensitive thresholds)
    sla_violation_alert_threshold_percent::Float64 = 5.0,  # Alert if >5% violate SLA
    error_rate_alert_threshold_percent::Float64 = 1.0,     # Alert if >1% error rate
    consecutive_failures_alert_threshold::Int = 3,         # Alert after 3 failures

    # Data retention (reasonable for production)
    metrics_retention_hours::Int = 72,             # 3 days of metrics
    log_retention_days::Int = 7,                   # 1 week of logs
    performance_data_retention_hours::Int = 48,    # 2 days of performance data

    # Feature flags (all enabled for production)
    enable_circuit_breakers::Bool = true,
    enable_adaptive_timeouts::Bool = true,
    enable_performance_monitoring::Bool = true,
    enable_resource_monitoring::Bool = true,
    enable_graceful_degradation::Bool = true,
    enable_background_health_checks::Bool = true,
)
    return ProductionConfiguration(
        p99_latency_target_ms,
        p95_latency_target_ms,
        max_acceptable_latency_ms,
        auction_timeout_ms,
        settlement_timeout_ms,
        cfmm_bridge_timeout_ms,
        phantom_auction_timeout_ms,
        default_operation_timeout_ms,
        circuit_breaker_failure_threshold,
        circuit_breaker_recovery_threshold,
        circuit_breaker_timeout_ms,
        circuit_breaker_slow_call_threshold_ms,
        circuit_breaker_volume_threshold,
        circuit_breaker_error_percentage_threshold,
        max_retry_attempts,
        base_retry_delay_ms,
        max_retry_delay_ms,
        retry_backoff_strategy,
        retry_jitter_ratio,
        slow_operation_threshold_ms,
        memory_usage_threshold_percent,
        cpu_usage_threshold_percent,
        disk_usage_threshold_percent,
        max_concurrent_auctions,
        max_pending_settlements,
        max_memory_usage_mb,
        thread_pool_size,
        health_check_interval_ms,
        resource_monitor_interval_ms,
        performance_report_interval_ms,
        sla_violation_alert_threshold_percent,
        error_rate_alert_threshold_percent,
        consecutive_failures_alert_threshold,
        metrics_retention_hours,
        log_retention_days,
        performance_data_retention_hours,
        enable_circuit_breakers,
        enable_adaptive_timeouts,
        enable_performance_monitoring,
        enable_resource_monitoring,
        enable_graceful_degradation,
        enable_background_health_checks,
    )
end

"""
    get_timeout_config(config)

Extract timeout configurations for different operations.
"""
function get_timeout_config(config::ProductionConfiguration)
    return (
        auction = config.auction_timeout_ms,
        settlement = config.settlement_timeout_ms,
        cfmm_bridge = config.cfmm_bridge_timeout_ms,
        phantom_auction = config.phantom_auction_timeout_ms,
        default_operation = config.default_operation_timeout_ms,
        max_acceptable = config.max_acceptable_latency_ms,
    )
end

"""
    get_retry_config(config)

Extract retry policy configurations.
"""
function get_retry_config(config::ProductionConfiguration)
    return RetryPolicy(
        config.max_retry_attempts,
        config.base_retry_delay_ms,
        config.max_retry_delay_ms,
        config.retry_backoff_strategy,
        config.retry_jitter_ratio,
        Set([:TRANSIENT, :TIMEOUT, :RATE_LIMITED]),  # Default retry categories
        1.5,  # Timeout multiplier
    )
end

"""
    get_circuit_breaker_config(config)

Extract circuit breaker configurations.
"""
function get_circuit_breaker_config(config::ProductionConfiguration)
    return CircuitBreakerConfig(
        config.circuit_breaker_failure_threshold,
        config.circuit_breaker_recovery_threshold,
        config.circuit_breaker_timeout_ms,
        config.circuit_breaker_slow_call_threshold_ms,
        10,  # half_open_max_calls
        config.circuit_breaker_volume_threshold,
        config.circuit_breaker_error_percentage_threshold,
        60000.0,  # monitoring_window_ms (1 minute)
    )
end

"""
    get_monitoring_config(config)

Extract monitoring and alerting configurations.
"""
function get_monitoring_config(config::ProductionConfiguration)
    return (
        slow_operation_threshold_ms = config.slow_operation_threshold_ms,
        memory_threshold_percent = config.memory_usage_threshold_percent,
        cpu_threshold_percent = config.cpu_usage_threshold_percent,
        disk_threshold_percent = config.disk_usage_threshold_percent,
        health_check_interval_ms = config.health_check_interval_ms,
        resource_monitor_interval_ms = config.resource_monitor_interval_ms,
        performance_report_interval_ms = config.performance_report_interval_ms,
        sla_violation_alert_threshold = config.sla_violation_alert_threshold_percent,
        error_rate_alert_threshold = config.error_rate_alert_threshold_percent,
        consecutive_failures_threshold = config.consecutive_failures_alert_threshold,
    )
end

"""
    get_performance_config(config)

Extract performance targets and limits.
"""
function get_performance_config(config::ProductionConfiguration)
    return (
        p99_target_ms = config.p99_latency_target_ms,
        p95_target_ms = config.p95_latency_target_ms,
        max_latency_ms = config.max_acceptable_latency_ms,
        max_concurrent_auctions = config.max_concurrent_auctions,
        max_pending_settlements = config.max_pending_settlements,
        max_memory_mb = config.max_memory_usage_mb,
        thread_pool_size = config.thread_pool_size,
    )
end

"""
Operation-specific configurations for different auction system components.
"""
const OPERATION_CONFIGS = Dict(
    # Core auction operations
    :auction_creation => (timeout_ms = 30.0, circuit_breaker_threshold = 2, max_retries = 1, p99_target_ms = 8.0),
    :bid_submission => (timeout_ms = 15.0, circuit_breaker_threshold = 3, max_retries = 2, p99_target_ms = 5.0),
    :auction_settlement =>
        (timeout_ms = 100.0, circuit_breaker_threshold = 3, max_retries = 2, p99_target_ms = 20.0),

    # CFMM operations
    :cfmm_bridge_call => (timeout_ms = 50.0, circuit_breaker_threshold = 2, max_retries = 1, p99_target_ms = 12.0),
    :cfmm_optimization =>
        (timeout_ms = 200.0, circuit_breaker_threshold = 5, max_retries = 3, p99_target_ms = 50.0),

    # Settlement operations
    :phantom_auction_creation =>
        (timeout_ms = 25.0, circuit_breaker_threshold = 2, max_retries = 1, p99_target_ms = 6.0),
    :atomic_settlement =>
        (timeout_ms = 150.0, circuit_breaker_threshold = 3, max_retries = 2, p99_target_ms = 30.0),
    :price_improvement => (timeout_ms = 75.0, circuit_breaker_threshold = 3, max_retries = 2, p99_target_ms = 15.0),

    # Monitoring operations
    :health_check => (timeout_ms = 5000.0, circuit_breaker_threshold = 5, max_retries = 1, p99_target_ms = 100.0),
    :metrics_collection =>
        (timeout_ms = 10000.0, circuit_breaker_threshold = 5, max_retries = 2, p99_target_ms = 500.0),
)

"""
    get_operation_config(operation::Symbol)

Get specific configuration for an operation.
"""
function get_operation_config(operation::Symbol)
    return get(
        OPERATION_CONFIGS,
        operation,
        (timeout_ms = 75.0, circuit_breaker_threshold = 3, max_retries = 2, p99_target_ms = 10.0),
    )
end

"""
Environment-specific configurations.
"""
const ENVIRONMENT_CONFIGS = Dict(
    :development => (
        enable_debug_logging = true,
        relaxed_timeouts_multiplier = 5.0,
        disable_circuit_breakers = false,
        verbose_monitoring = true,
    ),
    :staging => (
        enable_debug_logging = false,
        relaxed_timeouts_multiplier = 2.0,
        disable_circuit_breakers = false,
        verbose_monitoring = true,
    ),
    :production => (
        enable_debug_logging = false,
        relaxed_timeouts_multiplier = 1.0,
        disable_circuit_breakers = false,
        verbose_monitoring = false,
    ),
    :testing => (
        enable_debug_logging = true,
        relaxed_timeouts_multiplier = 10.0,
        disable_circuit_breakers = true,
        verbose_monitoring = false,
    ),
)

"""
    get_environment_config(env::Symbol)

Get environment-specific configuration overrides.
"""
function get_environment_config(env::Symbol)
    return get(ENVIRONMENT_CONFIGS, env, ENVIRONMENT_CONFIGS[:production])
end

"""
    create_environment_config(base_config, env::Symbol)

Create environment-adjusted configuration.
"""
function create_environment_config(base_config::ProductionConfiguration, env::Symbol)
    env_overrides = get_environment_config(env)

    # Apply environment-specific multipliers
    timeout_multiplier = env_overrides.relaxed_timeouts_multiplier

    return ProductionConfiguration(
        base_config.p99_latency_target_ms * timeout_multiplier,
        base_config.p95_latency_target_ms * timeout_multiplier,
        base_config.max_acceptable_latency_ms * timeout_multiplier,
        base_config.auction_timeout_ms * timeout_multiplier,
        base_config.settlement_timeout_ms * timeout_multiplier,
        base_config.cfmm_bridge_timeout_ms * timeout_multiplier,
        base_config.phantom_auction_timeout_ms * timeout_multiplier,
        base_config.default_operation_timeout_ms * timeout_multiplier,
        base_config.circuit_breaker_failure_threshold,
        base_config.circuit_breaker_recovery_threshold,
        base_config.circuit_breaker_timeout_ms,
        base_config.circuit_breaker_slow_call_threshold_ms * timeout_multiplier,
        base_config.circuit_breaker_volume_threshold,
        base_config.circuit_breaker_error_percentage_threshold,
        base_config.max_retry_attempts,
        base_config.base_retry_delay_ms * timeout_multiplier,
        base_config.max_retry_delay_ms * timeout_multiplier,
        base_config.retry_backoff_strategy,
        base_config.retry_jitter_ratio,
        base_config.slow_operation_threshold_ms * timeout_multiplier,
        base_config.memory_usage_threshold_percent,
        base_config.cpu_usage_threshold_percent,
        base_config.disk_usage_threshold_percent,
        base_config.max_concurrent_auctions,
        base_config.max_pending_settlements,
        base_config.max_memory_usage_mb,
        base_config.thread_pool_size,
        base_config.health_check_interval_ms,
        base_config.resource_monitor_interval_ms,
        base_config.performance_report_interval_ms,
        base_config.sla_violation_alert_threshold_percent,
        base_config.error_rate_alert_threshold_percent,
        base_config.consecutive_failures_alert_threshold,
        base_config.metrics_retention_hours,
        base_config.log_retention_days,
        base_config.performance_data_retention_hours,
        base_config.enable_circuit_breakers && !env_overrides.disable_circuit_breakers,
        base_config.enable_adaptive_timeouts,
        base_config.enable_performance_monitoring,
        base_config.enable_resource_monitoring,
        base_config.enable_graceful_degradation,
        base_config.enable_background_health_checks,
    )
end

# Default production configuration instance
const DEFAULT_PRODUCTION_CONFIG = create_production_config()

"""
    get_default_production_config()

Get the default production configuration.
"""
function get_default_production_config()
    return DEFAULT_PRODUCTION_CONFIG
end

end # module
