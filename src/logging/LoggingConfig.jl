"""
LoggingConfig.jl - Centralized logging configuration for Julia Auction System

This module provides structured, production-ready logging with:
- JSON format for structured logging
- Environment-based log levels
- Request correlation IDs
- Performance monitoring integration
"""

module LoggingConfig

using Dates
using JSON
using Logging
using UUIDs
export configure_logging!, create_logger, LogLevel, CorrelationContext
export @log_with_correlation, generate_correlation_id, set_correlation_id!
export create_json_formatter, create_console_formatter

# Thread-local correlation context for request tracking
const CORRELATION_CONTEXT = Ref{Union{String,Nothing}}(nothing)

"""
    CorrelationContext

Manages correlation IDs for distributed tracing across auction operations
"""
struct CorrelationContext
    correlation_id::String
    request_start::DateTime
    operation::String

    function CorrelationContext(operation::String = "unknown")
        correlation_id = generate_correlation_id()
        new(correlation_id, now(), operation)
    end
end

"""
    generate_correlation_id() -> String

Generate a unique correlation ID for request tracking
"""
function generate_correlation_id()::String
    return string(uuid4())[1:8]  # Use first 8 chars for brevity
end

"""
    set_correlation_id!(id::String)

Set the correlation ID for the current thread
"""
function set_correlation_id!(id::String)
    CORRELATION_CONTEXT[] = id
end

"""
    get_correlation_id() -> Union{String, Nothing}

Get the current correlation ID for this thread
"""
function get_correlation_id()::Union{String,Nothing}
    return CORRELATION_CONTEXT[]
end

"""
    JSONFormatter

Custom formatter for structured JSON logging
"""
struct JSONFormatter <: Logging.AbstractLogger
    min_level::LogLevel
    stream::IO

    function JSONFormatter(stream::IO = stderr, min_level = Logging.Info)
        new(min_level, stream)
    end
end

function Logging.min_enabled_level(logger::JSONFormatter)
    return logger.min_level
end

function Logging.shouldlog(logger::JSONFormatter, level, _module, group, id)
    return level >= logger.min_level
end

function Logging.handle_message(logger::JSONFormatter, level, message, _module, group, id, file, line; kwargs...)
    # Build structured log entry
    log_entry = Dict{String,Any}(
        "timestamp" => now(),
        "level" => string(level),
        "message" => string(message),
        "module" => string(_module),
        "file" => string(file),
        "line" => line,
    )

    # Add correlation ID if available
    correlation_id = get_correlation_id()
    if correlation_id !== nothing
        log_entry["correlation_id"] = correlation_id
    end

    # Add any additional key-value pairs from kwargs
    for (key, value) in kwargs
        if key == :exception && value isa Exception
            log_entry["exception"] = Dict(
                "type" => string(typeof(value)),
                "message" => string(value),
                "stacktrace" => string.(stacktrace(catch_backtrace())),
            )
        else
            log_entry[string(key)] = value
        end
    end

    # Write JSON log entry
    try
        json_line = JSON.json(log_entry)
        println(logger.stream, json_line)
        flush(logger.stream)
    catch e
        # Fallback to simple logging if JSON formatting fails
        println(logger.stream, "$(now()) [$level] $message")
        flush(logger.stream)
    end
end

"""
    ConsoleFormatter

Human-readable formatter for development and debugging
"""
struct ConsoleFormatter <: Logging.AbstractLogger
    min_level::LogLevel
    stream::IO

    function ConsoleFormatter(stream::IO = stderr, min_level = Logging.Info)
        new(min_level, stream)
    end
end

function Logging.min_enabled_level(logger::ConsoleFormatter)
    return logger.min_level
end

function Logging.shouldlog(logger::ConsoleFormatter, level, _module, group, id)
    return level >= logger.min_level
end

function Logging.handle_message(logger::ConsoleFormatter, level, message, _module, group, id, file, line; kwargs...)
    # Color coding for different log levels
    level_color = if level >= Logging.Error
        "\e[31m"  # Red
    elseif level >= Logging.Warn
        "\e[33m"  # Yellow
    elseif level >= Logging.Info
        "\e[32m"  # Green
    else
        "\e[36m"  # Cyan
    end
    reset_color = "\e[0m"

    # Format timestamp
    timestamp = Dates.format(now(), "yyyy-mm-dd HH:MM:SS.sss")

    # Build log line
    level_str = rpad(string(level), 5)
    correlation_part = ""
    correlation_id = get_correlation_id()
    if correlation_id !== nothing
        correlation_part = " [$correlation_id]"
    end

    log_line =
        "$(timestamp) $(level_color)$(level_str)$(reset_color)" *
        "$correlation_part $(basename(string(file))):$(line) - $(message)"

    # Add exception details if present
    if haskey(kwargs, :exception) && kwargs[:exception] isa Exception
        log_line *= "\n  Exception: $(kwargs[:exception])"
    end

    # Add other key-value pairs
    for (key, value) in kwargs
        if key != :exception
            log_line *= " $(key)=$(value)"
        end
    end

    println(logger.stream, log_line)
    flush(logger.stream)
end

"""
    create_json_formatter(;min_level = Info, stream = stderr) -> JSONFormatter

Create a JSON formatter for structured logging
"""
function create_json_formatter(; min_level::LogLevel = Logging.Info, stream::IO = stderr)::JSONFormatter
    return JSONFormatter(stream, min_level)
end

"""
    create_console_formatter(;min_level = Info, stream = stderr) -> ConsoleFormatter

Create a console formatter for human-readable logging
"""
function create_console_formatter(; min_level::LogLevel = Logging.Info, stream::IO = stderr)::ConsoleFormatter
    return ConsoleFormatter(stream, min_level)
end

"""
    configure_logging!(;environment = :production, level = nothing, format = :auto)

Configure global logging based on environment and preferences
"""
function configure_logging!(;
    environment::Symbol = :production,
    level::Union{LogLevel,Nothing} = nothing,
    format::Symbol = :auto,
)
    # Determine log level based on environment
    if level === nothing
        level = if environment == :development
            Logging.Debug
        elseif environment == :testing
            Logging.Warn
        else  # production
            Logging.Info
        end
    end

    # Choose formatter based on environment and format preference
    formatter = if format == :json || (format == :auto && environment == :production)
        create_json_formatter(min_level = level)
    else
        create_console_formatter(min_level = level)
    end

    # Set as global logger
    global_logger(formatter)

    @info "Logging configured" environment=environment level=level format=format
end

"""
    @log_with_correlation(level, message, correlation_id, args...)

Log a message with automatic correlation ID handling
"""
macro log_with_correlation(level, message, correlation_id, args...)
    quote
        old_correlation = get_correlation_id()
        set_correlation_id!($(esc(correlation_id)))
        try
            @logmsg $(esc(level)) $(esc(message)) $(esc.(args)...)
        finally
            if old_correlation !== nothing
                set_correlation_id!(old_correlation)
            else
                CORRELATION_CONTEXT[] = nothing
            end
        end
    end
end

"""
    create_logger(name::String; level = Info) -> Logger

Create a named logger instance (for compatibility with existing code)
"""
function create_logger(name::String; level::LogLevel = Logging.Info)
    # For now, return the current global logger
    # In future versions, this could create module-specific loggers
    return current_logger()
end

end  # module LoggingConfig
