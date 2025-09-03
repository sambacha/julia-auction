module ErrorHandler

using Base.Threads: Atomic, SpinLock
using Dates
using Logging
using Random
export ProductionErrorHandler, ErrorCategory, RetryPolicy, BackoffStrategy
export create_error_handler, handle_with_retry, classify_error
export configure_retry_policy, get_error_statistics

"""
Error categories for different handling strategies.
"""
@enum ErrorCategory begin
    TRANSIENT     # Temporary failures, should retry
    PERMANENT     # Permanent failures, don't retry
    RATE_LIMITED  # Rate limit errors, backoff longer
    TIMEOUT       # Timeout errors, may retry with longer timeout
    CIRCUIT_OPEN  # Circuit breaker open, use fallback
    RESOURCE      # Resource exhaustion, backoff significantly
    UNKNOWN       # Unknown errors, conservative retry
end

"""
Backoff strategies for retries.
"""
@enum BackoffStrategy begin
    FIXED         # Fixed delay
    LINEAR        # Linear increase
    EXPONENTIAL   # Exponential backoff
    EXPONENTIAL_JITTER # Exponential with jitter
end

"""
Retry policy configuration.
"""
struct RetryPolicy
    max_attempts::Int
    base_delay_ms::Float64
    max_delay_ms::Float64
    backoff_strategy::BackoffStrategy
    jitter_ratio::Float64  # 0.0 to 1.0 for jitter amount
    retry_on_categories::Set{ErrorCategory}
    timeout_multiplier::Float64  # Multiply timeout on each retry
end

"""
Error statistics for monitoring.
"""
mutable struct ErrorStatistics
    total_errors::Atomic{Int}
    errors_by_category::Dict{ErrorCategory, Atomic{Int}}
    successful_retries::Atomic{Int}
    failed_retries::Atomic{Int}
    total_retry_attempts::Atomic{Int}
    last_error_time::Atomic{Float64}
    error_window::Vector{Tuple{Float64, ErrorCategory}}
    lock::SpinLock
end

"""
Production error handler with comprehensive retry and classification.
"""
mutable struct ProductionErrorHandler
    retry_policies::Dict{Symbol, RetryPolicy}
    fallback_handlers::Dict{Symbol, Function}
    error_classifiers::Vector{Function}
    statistics::ErrorStatistics
    default_policy::RetryPolicy
    degradation_strategies::Dict{Symbol, Function}
    lock::SpinLock
    name::String
end

"""
    create_error_handler(name::String; kwargs...)

Create a production-ready error handler with optimal defaults.
"""
function create_error_handler(name::String;
    default_max_attempts::Int=3,
    default_base_delay_ms::Float64=100.0,
    default_max_delay_ms::Float64=30000.0,
    default_backoff_strategy::BackoffStrategy=EXPONENTIAL_JITTER,
    default_jitter_ratio::Float64=0.1,
    default_timeout_multiplier::Float64=1.5)
    
    default_policy = RetryPolicy(
        default_max_attempts,
        default_base_delay_ms,
        default_max_delay_ms,
        default_backoff_strategy,
        default_jitter_ratio,
        Set([TRANSIENT, TIMEOUT, RATE_LIMITED]),
        default_timeout_multiplier
    )
    
    statistics = ErrorStatistics(
        Atomic{Int}(0),
        Dict(cat => Atomic{Int}(0) for cat in instances(ErrorCategory)),
        Atomic{Int}(0),
        Atomic{Int}(0),
        Atomic{Int}(0),
        Atomic{Float64}(0.0),
        Tuple{Float64, ErrorCategory}[],
        SpinLock()
    )
    
    # Default error classifiers
    classifiers = [
        classify_network_errors,
        classify_timeout_errors,
        classify_resource_errors,
        classify_http_errors,
        classify_julia_errors
    ]
    
    return ProductionErrorHandler(
        Dict{Symbol, RetryPolicy}(),
        Dict{Symbol, Function}(),
        classifiers,
        statistics,
        default_policy,
        Dict{Symbol, Function}(),
        SpinLock(),
        name
    )
end

"""
    handle_with_retry(f, error_handler, operation_name; kwargs...)

Execute function with comprehensive error handling and retry logic.
"""
function handle_with_retry(f::Function, 
                          handler::ProductionErrorHandler,
                          operation_name::Symbol;
                          timeout_ms::Union{Float64, Nothing}=nothing,
                          context::Dict=Dict(),
                          enable_degradation::Bool=true)
    
    policy = get(handler.retry_policies, operation_name, handler.default_policy)
    attempt = 1
    last_error = nothing
    start_time = time() * 1000
    
    while attempt <= policy.max_attempts
        try
            # Apply timeout if specified
            if timeout_ms !== nothing
                current_timeout = timeout_ms * (policy.timeout_multiplier ^ (attempt - 1))
                result = execute_with_timeout(f, current_timeout)
            else
                result = f()
            end
            
            # Record success
            if attempt > 1
                atomic_add!(handler.statistics.successful_retries, 1)
                @info "Operation $(operation_name) succeeded after retry" 
                    attempt=attempt handler=handler.name
            end
            
            return result
            
        catch e
            last_error = e
            error_category = classify_error(handler, e)
            current_time = time() * 1000
            
            # Record error statistics
            record_error(handler.statistics, error_category, current_time)
            
            @debug "Error in operation $(operation_name)" 
                attempt=attempt 
                category=error_category 
                error=string(e)
                handler=handler.name
            
            # Check if we should retry
            if attempt >= policy.max_attempts || !should_retry(policy, error_category)
                atomic_add!(handler.statistics.failed_retries, 1)
                
                # Try degradation strategy if available
                if enable_degradation && haskey(handler.degradation_strategies, operation_name)
                    try
                        @warn "Attempting graceful degradation for $(operation_name)" 
                            handler=handler.name
                        return handler.degradation_strategies[operation_name](e, context)
                    catch degradation_error
                        @error "Degradation strategy failed" 
                            operation=operation_name 
                            original_error=string(e)
                            degradation_error=string(degradation_error)
                            handler=handler.name
                    end
                end
                
                # Try fallback handler if available
                if haskey(handler.fallback_handlers, operation_name)
                    try
                        @warn "Using fallback handler for $(operation_name)" 
                            handler=handler.name
                        return handler.fallback_handlers[operation_name](e, context)
                    catch fallback_error
                        @error "Fallback handler failed" 
                            operation=operation_name 
                            original_error=string(e)
                            fallback_error=string(fallback_error)
                            handler=handler.name
                    end
                end
                
                rethrow(e)
            end
            
            # Calculate delay
            delay_ms = calculate_backoff_delay(policy, attempt, error_category)
            
            @debug "Retrying operation $(operation_name)" 
                attempt=attempt 
                delay_ms=delay_ms 
                category=error_category
                handler=handler.name
            
            atomic_add!(handler.statistics.total_retry_attempts, 1)
            
            # Sleep before retry
            if delay_ms > 0
                sleep(delay_ms / 1000.0)
            end
            
            attempt += 1
        end
    end
end

"""
Execute function with timeout protection.
"""
function execute_with_timeout(f::Function, timeout_ms::Float64)
    # Simple timeout implementation using Task
    task = @async f()
    
    start_time = time()
    while !istaskdone(task)
        if (time() - start_time) * 1000 > timeout_ms
            @warn "Operation timed out" timeout_ms=timeout_ms
            # Note: In production, you'd want more sophisticated timeout handling
            throw(TimeoutError("Operation exceeded timeout of $(timeout_ms)ms"))
        end
        sleep(0.001)  # Small sleep to prevent busy waiting
    end
    
    if istaskfailed(task)
        throw(task.exception)
    end
    
    return task.result
end

"""
Timeout error type.
"""
struct TimeoutError <: Exception
    message::String
end

"""
Classify error into appropriate category for handling.
"""
function classify_error(handler::ProductionErrorHandler, error::Exception)
    for classifier in handler.error_classifiers
        category = classifier(error)
        if category !== nothing
            return category
        end
    end
    return UNKNOWN
end

"""
Classify network-related errors.
"""
function classify_network_errors(error::Exception)
    error_str = string(typeof(error))
    error_msg = string(error)
    
    if occursin("Connection", error_str) || occursin("Network", error_str)
        return TRANSIENT
    elseif occursin("DNS", error_str) || occursin("Host", error_str)
        return TRANSIENT
    elseif occursin("Timeout", error_str) || occursin("timeout", error_msg)
        return TIMEOUT
    elseif occursin("429", error_msg) || occursin("rate limit", lowercase(error_msg))
        return RATE_LIMITED
    end
    
    return nothing
end

"""
Classify timeout-related errors.
"""
function classify_timeout_errors(error::Exception)
    if isa(error, TimeoutError)
        return TIMEOUT
    end
    
    error_msg = lowercase(string(error))
    if occursin("timeout", error_msg) || occursin("deadline", error_msg)
        return TIMEOUT
    end
    
    return nothing
end

"""
Classify resource-related errors.
"""
function classify_resource_errors(error::Exception)
    error_str = string(typeof(error))
    error_msg = lowercase(string(error))
    
    if occursin("OutOfMemory", error_str) || occursin("memory", error_msg)
        return RESOURCE
    elseif occursin("DiskSpace", error_str) || occursin("disk", error_msg)
        return RESOURCE
    elseif occursin("ThreadError", error_str) || occursin("pool", error_msg)
        return RESOURCE
    end
    
    return nothing
end

"""
Classify HTTP-related errors.
"""
function classify_http_errors(error::Exception)
    error_msg = string(error)
    
    # Look for HTTP status codes in error message
    if occursin(r"[45]\d{2}", error_msg)
        status_match = match(r"([45]\d{2})", error_msg)
        if status_match !== nothing
            status_code = parse(Int, status_match.captures[1])
            
            if status_code in [408, 429, 502, 503, 504]
                return status_code == 429 ? RATE_LIMITED : TRANSIENT
            elseif status_code in [400, 401, 403, 404, 422]
                return PERMANENT
            else
                return TRANSIENT
            end
        end
    end
    
    return nothing
end

"""
Classify Julia-specific errors.
"""
function classify_julia_errors(error::Exception)
    if isa(error, BoundsError) || isa(error, ArgumentError)
        return PERMANENT
    elseif isa(error, InterruptException)
        return PERMANENT
    elseif isa(error, LoadError) || isa(error, MethodError)
        return PERMANENT
    elseif isa(error, SystemError)
        return TRANSIENT
    end
    
    return nothing
end

"""
Determine if error should trigger retry based on policy.
"""
function should_retry(policy::RetryPolicy, category::ErrorCategory)
    return category in policy.retry_on_categories
end

"""
Calculate backoff delay based on strategy and attempt number.
"""
function calculate_backoff_delay(policy::RetryPolicy, attempt::Int, category::ErrorCategory)
    base_delay = policy.base_delay_ms
    
    # Apply category-specific multipliers
    if category == RATE_LIMITED
        base_delay *= 2.0  # Longer delays for rate limiting
    elseif category == RESOURCE
        base_delay *= 3.0  # Much longer delays for resource exhaustion
    end
    
    delay = if policy.backoff_strategy == FIXED
        base_delay
    elseif policy.backoff_strategy == LINEAR
        base_delay * attempt
    elseif policy.backoff_strategy == EXPONENTIAL
        base_delay * (2 ^ (attempt - 1))
    elseif policy.backoff_strategy == EXPONENTIAL_JITTER
        exponential_delay = base_delay * (2 ^ (attempt - 1))
        jitter = policy.jitter_ratio * exponential_delay * (rand() - 0.5) * 2
        exponential_delay + jitter
    else
        base_delay
    end
    
    # Clamp to maximum delay
    return min(delay, policy.max_delay_ms)
end

"""
Record error occurrence in statistics.
"""
function record_error(stats::ErrorStatistics, category::ErrorCategory, timestamp::Float64)
    lock(stats.lock) do
        atomic_add!(stats.total_errors, 1)
        atomic_add!(stats.errors_by_category[category], 1)
        stats.last_error_time[] = timestamp
        
        # Add to sliding window
        push!(stats.error_window, (timestamp, category))
        
        # Clean up old entries (keep last hour)
        cutoff_time = timestamp - 3600000.0  # 1 hour in ms
        filter!(entry -> entry[1] >= cutoff_time, stats.error_window)
    end
end

"""
Get comprehensive error statistics.
"""
function get_error_statistics(handler::ProductionErrorHandler)
    lock(handler.statistics.lock) do
        current_time = time() * 1000
        
        # Calculate error rates
        total_errors = handler.statistics.total_errors[]
        successful_retries = handler.statistics.successful_retries[]
        failed_retries = handler.statistics.failed_retries[]
        total_attempts = handler.statistics.total_retry_attempts[]
        
        # Recent error rates (last hour)
        cutoff_time = current_time - 3600000.0
        recent_errors = filter(entry -> entry[1] >= cutoff_time, handler.statistics.error_window)
        
        error_by_category = Dict{ErrorCategory, Int}()
        for (cat, counter) in handler.statistics.errors_by_category
            error_by_category[cat] = counter[]
        end
        
        recent_by_category = Dict{ErrorCategory, Int}()
        for cat in instances(ErrorCategory)
            recent_by_category[cat] = count(entry -> entry[2] == cat, recent_errors)
        end
        
        retry_success_rate = total_attempts > 0 ? 
            (successful_retries / total_attempts) * 100.0 : 0.0
        
        return (
            handler_name = handler.name,
            total_errors = total_errors,
            errors_by_category = error_by_category,
            recent_errors_1h = length(recent_errors),
            recent_by_category_1h = recent_by_category,
            successful_retries = successful_retries,
            failed_retries = failed_retries,
            total_retry_attempts = total_attempts,
            retry_success_rate_percent = retry_success_rate,
            last_error_time = handler.statistics.last_error_time[],
            time_since_last_error_ms = current_time - handler.statistics.last_error_time[]
        )
    end
end

"""
Configure retry policy for specific operations.
"""
function configure_retry_policy(handler::ProductionErrorHandler, 
                               operation::Symbol,
                               policy::RetryPolicy)
    lock(handler.lock) do
        handler.retry_policies[operation] = policy
        @info "Retry policy configured" operation=operation handler=handler.name
    end
end

"""
Add fallback handler for specific operations.
"""
function add_fallback_handler(handler::ProductionErrorHandler,
                             operation::Symbol,
                             fallback_fn::Function)
    lock(handler.lock) do
        handler.fallback_handlers[operation] = fallback_fn
        @info "Fallback handler added" operation=operation handler=handler.name
    end
end

"""
Add graceful degradation strategy for specific operations.
"""
function add_degradation_strategy(handler::ProductionErrorHandler,
                                 operation::Symbol,
                                 degradation_fn::Function)
    lock(handler.lock) do
        handler.degradation_strategies[operation] = degradation_fn
        @info "Degradation strategy added" operation=operation handler=handler.name
    end
end

end # module