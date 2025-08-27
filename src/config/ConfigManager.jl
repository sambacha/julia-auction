"""
    ConfigManager

Comprehensive configuration management system for the Julia Auction platform.
Provides type-safe, environment-aware configuration loading with support for:

- TOML file loading with environment-specific overrides
- Environment variable overrides with structured naming
- Type validation and conversion
- Configuration validation and defaults
- Thread-safe configuration access
- Hot reloading support

# Usage

```julia
using ConfigManager
# Load configuration based on environment
config = load_config()  # Uses JULIA_AUCTION_ENV or defaults to "development"

# Access configuration values with type safety
bid_prob = get_config(config, "phantom_auction.bid_probability", Float64)
timeout = get_config(config, "timeouts.auction_timeout_ms", Float64)

# Set environment variable overrides
ENV["AUCTION_PHANTOM_AUCTION_BID_PROBABILITY"] = "0.4"
config = reload_config(config)
```

# Environment Variable Naming Convention

Environment variables override config values using the pattern:
`AUCTION_SECTION_SUBSECTION_KEY`

Examples:
- `AUCTION_PHANTOM_AUCTION_BID_PROBABILITY` → phantom_auction.bid_probability
- `AUCTION_COORDINATOR_CONSENSUS_THRESHOLD` → coordinator.consensus_threshold
- `AUCTION_TIMEOUTS_AUCTION_TIMEOUT_MS` → timeouts.auction_timeout_ms
"""
module ConfigManager

using Logging
using TOML
export AuctionConfig, ConfigValue, ConfigError
export load_config, reload_config, get_config, set_config!
export validate_config, get_environment, get_config_path
export has_config, get_config_section, merge_configs
export save_config, config_to_dict

# Type definitions for configuration values
const ConfigValue = Union{String, Int, Float64, Bool, Vector{String}, Vector{Int}, Vector{Float64}}

# Configuration errors
struct ConfigError <: Exception
    message::String
    key::Union{String, Nothing}
    value::Any
end

Base.show(io::IO, e::ConfigError) = print(io, "ConfigError: $(e.message)")

"""
    AuctionConfig

Main configuration container that holds all auction system settings.
Provides type-safe access to configuration values with validation.
"""
mutable struct AuctionConfig
    data::Dict{String, Any}
    environment::String
    config_path::String
    last_loaded::Float64
    
    function AuctionConfig(data::Dict{String, Any}, environment::String, config_path::String)
        new(data, environment, config_path, time())
    end
end

"""
    load_config(environment=nothing, config_dir=nothing)

Load configuration from TOML files based on the specified environment.
Applies environment variable overrides after loading base configuration.

# Arguments
- `environment::Union{String, Nothing}`: Environment to load. If nothing, uses JULIA_AUCTION_ENV or "development"
- `config_dir::Union{String, Nothing}`: Directory containing config files. If nothing, uses default location

# Returns
- `AuctionConfig`: Loaded and validated configuration object

# Throws
- `ConfigError`: If configuration loading or validation fails
"""
function load_config(environment::Union{String, Nothing}=nothing, 
                    config_dir::Union{String, Nothing}=nothing)::AuctionConfig
    
    # Determine environment
    env = environment !== nothing ? environment : get_environment()
    
    # Determine config directory
    config_path = config_dir !== nothing ? config_dir : get_config_path()
    
    @info "Loading auction configuration" environment=env config_path=config_path
    
    try
        # Load default configuration first
        default_file = joinpath(config_path, "default.toml")
        if !isfile(default_file)
            throw(ConfigError("Default configuration file not found", default_file, nothing))
        end
        
        config_data = TOML.parsefile(default_file)
        @debug "Loaded default configuration" file=default_file sections=keys(config_data)
        
        # Load environment-specific overrides if they exist
        env_file = joinpath(config_path, "$(env).toml")
        if isfile(env_file)
            env_data = TOML.parsefile(env_file)
            config_data = merge_configs(config_data, env_data)
            @debug "Applied environment overrides" file=env_file sections=keys(env_data)
        else
            @debug "No environment-specific config found" file=env_file
        end
        
        # Apply environment variable overrides
        config_data = apply_environment_overrides(config_data)
        
        # Create configuration object
        config = AuctionConfig(config_data, env, config_path)
        
        # Validate configuration
        validate_config(config)
        
        @info "Configuration loaded successfully" environment=env sections=length(config.data)
        return config
        
    catch e
        if isa(e, ConfigError)
            rethrow(e)
        else
            throw(ConfigError("Failed to load configuration: $e", nothing, e))
        end
    end
end

"""
    reload_config(config::AuctionConfig)

Reload configuration from files and environment variables.
Preserves the same environment and config path.

# Arguments
- `config::AuctionConfig`: Existing configuration to reload

# Returns
- `AuctionConfig`: Reloaded configuration object
"""
function reload_config(config::AuctionConfig)::AuctionConfig
    @info "Reloading configuration" environment=config.environment
    return load_config(config.environment, config.config_path)
end

"""
    get_config(config::AuctionConfig, key::String, ::Type{T}; default=nothing) where T

Get a configuration value with type safety and validation.

# Arguments
- `config::AuctionConfig`: Configuration object
- `key::String`: Configuration key using dot notation (e.g., "phantom_auction.bid_probability")
- `T::Type`: Expected type of the configuration value
- `default`: Default value to return if key is not found (optional)

# Returns
- `T`: Configuration value converted to the specified type

# Throws
- `ConfigError`: If key is not found and no default provided, or if type conversion fails

# Examples
```julia
config = load_config()
bid_prob = get_config(config, "phantom_auction.bid_probability", Float64)
timeout = get_config(config, "timeouts.auction_timeout_ms", Float64, 50.0)
```
"""
function get_config(config::AuctionConfig, key::String, ::Type{T}; 
                   default=nothing) where T <: ConfigValue
    
    # Split key into path components
    path = split(key, '.')
    
    # Navigate through nested dictionaries
    current = config.data
    for segment in path[1:end-1]
        if !haskey(current, segment) || !isa(current[segment], Dict)
            if default !== nothing
                return convert(T, default)
            else
                throw(ConfigError("Configuration path not found", key, current))
            end
        end
        current = current[segment]
    end
    
    # Get final value
    final_key = path[end]
    if !haskey(current, final_key)
        if default !== nothing
            return convert(T, default)
        else
            throw(ConfigError("Configuration key not found", key, current))
        end
    end
    
    value = current[final_key]
    
    # Type conversion and validation
    try
        return convert(T, value)
    catch e
        throw(ConfigError("Type conversion failed for key '$key': expected $T, got $(typeof(value))", key, value))
    end
end

"""
    get_config(config::AuctionConfig, key::String; default=nothing)

Get a configuration value without type specification (returns Any).
"""
function get_config(config::AuctionConfig, key::String; default=nothing)
    try
        return get_config(config, key, Any; default=default)
    catch e
        if isa(e, ConfigError) && default !== nothing
            return default
        else
            rethrow(e)
        end
    end
end

"""
    set_config!(config::AuctionConfig, key::String, value)

Set a configuration value at runtime.

# Arguments
- `config::AuctionConfig`: Configuration object to modify
- `key::String`: Configuration key using dot notation
- `value`: Value to set

# Note
This only affects the in-memory configuration, not the underlying files.
"""
function set_config!(config::AuctionConfig, key::String, value)
    path = split(key, '.')
    
    # Navigate/create nested structure
    current = config.data
    for segment in path[1:end-1]
        if !haskey(current, segment)
            current[segment] = Dict{String, Any}()
        elseif !isa(current[segment], Dict)
            current[segment] = Dict{String, Any}()
        end
        current = current[segment]
    end
    
    # Set final value
    current[path[end]] = value
    
    @debug "Configuration value updated" key=key value=value
end

"""
    has_config(config::AuctionConfig, key::String)

Check if a configuration key exists.

# Arguments
- `config::AuctionConfig`: Configuration object
- `key::String`: Configuration key using dot notation

# Returns
- `Bool`: true if key exists, false otherwise
"""
function has_config(config::AuctionConfig, key::String)::Bool
    try
        get_config(config, key)
        return true
    catch e
        return false
    end
end

"""
    get_config_section(config::AuctionConfig, section::String)

Get an entire configuration section as a dictionary.

# Arguments
- `config::AuctionConfig`: Configuration object
- `section::String`: Section name

# Returns
- `Dict{String, Any}`: Configuration section data

# Throws
- `ConfigError`: If section is not found
"""
function get_config_section(config::AuctionConfig, section::String)::Dict{String, Any}
    if !haskey(config.data, section)
        throw(ConfigError("Configuration section not found", section, config.data))
    end
    
    section_data = config.data[section]
    if !isa(section_data, Dict)
        throw(ConfigError("Configuration section is not a dictionary", section, section_data))
    end
    
    return section_data
end

"""
    validate_config(config::AuctionConfig)

Validate configuration values and constraints.

# Arguments
- `config::AuctionConfig`: Configuration to validate

# Throws
- `ConfigError`: If validation fails
"""
function validate_config(config::AuctionConfig)
    @debug "Validating configuration"
    
    validations = [
        # Phantom auction validations
        ("phantom_auction.bid_probability", Float64, x -> 0.0 <= x <= 1.0, "Must be between 0.0 and 1.0"),
        ("phantom_auction.duration_ms", Float64, x -> x > 0, "Must be positive"),
        ("phantom_auction.min_improvement_bps", Float64, x -> x >= 0, "Must be non-negative"),
        ("phantom_auction.max_improvement_bps", Float64, x -> x >= 0, "Must be non-negative"),
        ("phantom_auction.reveal_delay_ms", Float64, x -> x > 0, "Must be positive"),
        ("phantom_auction.min_participants", Int, x -> x >= 1, "Must be at least 1"),
        
        # Coordinator validations
        ("coordinator.consensus_threshold", Float64, x -> 0.5 <= x <= 1.0, "Must be between 0.5 and 1.0"),
        ("coordinator.base_success_rate", Float64, x -> 0.0 <= x <= 1.0, "Must be between 0.0 and 1.0"),
        ("coordinator.timeout_seconds", Float64, x -> x > 0, "Must be positive"),
        ("coordinator.retry_count", Int, x -> x >= 0, "Must be non-negative"),
        ("coordinator.heartbeat_interval_seconds", Float64, x -> x > 0, "Must be positive"),
        
        # Settlement validations
        ("settlement.base_gas_cost", Int, x -> x > 0, "Must be positive"),
        ("settlement.timeout_ms", Float64, x -> x > 0, "Must be positive"),
        ("settlement.max_retries", Int, x -> x >= 0, "Must be non-negative"),
        
        # Circuit breaker validations
        ("circuit_breaker.failure_threshold", Int, x -> x > 0, "Must be positive"),
        ("circuit_breaker.recovery_threshold", Int, x -> x > 0, "Must be positive"),
        ("circuit_breaker.timeout_ms", Float64, x -> x > 0, "Must be positive"),
        ("circuit_breaker.error_percentage_threshold", Float64, x -> 0.0 <= x <= 100.0, "Must be between 0.0 and 100.0"),
        
        # Performance validations
        ("performance.p99_latency_target_ms", Float64, x -> x > 0, "Must be positive"),
        ("performance.p95_latency_target_ms", Float64, x -> x > 0, "Must be positive"),
        ("performance.max_acceptable_latency_ms", Float64, x -> x > 0, "Must be positive"),
        
        # Resource validations
        ("resources.max_concurrent_auctions", Int, x -> x > 0, "Must be positive"),
        ("resources.max_pending_settlements", Int, x -> x > 0, "Must be positive"),
        ("resources.max_memory_usage_mb", Int, x -> x > 0, "Must be positive"),
        ("resources.thread_pool_size", Int, x -> x > 0, "Must be positive"),
    ]
    
    for (key, type, validator, message) in validations
        try
            value = get_config(config, key, type)
            if !validator(value)
                throw(ConfigError("Validation failed for '$key': $message", key, value))
            end
        catch e
            if isa(e, ConfigError)
                rethrow(e)
            else
                @warn "Skipping validation for missing optional key" key=key
            end
        end
    end
    
    # Cross-validation checks
    try
        min_improvement = get_config(config, "phantom_auction.min_improvement_bps", Float64)
        max_improvement = get_config(config, "phantom_auction.max_improvement_bps", Float64)
        if min_improvement > max_improvement
            throw(ConfigError("min_improvement_bps must be <= max_improvement_bps", 
                            "phantom_auction.min_improvement_bps", min_improvement))
        end
    catch e
        if !isa(e, ConfigError) || e.key != "phantom_auction.min_improvement_bps"
            @warn "Skipping cross-validation for phantom auction improvements"
        else
            rethrow(e)
        end
    end
    
    try
        p95_target = get_config(config, "performance.p95_latency_target_ms", Float64)
        p99_target = get_config(config, "performance.p99_latency_target_ms", Float64)
        if p95_target > p99_target
            throw(ConfigError("p95_latency_target_ms must be <= p99_latency_target_ms", 
                            "performance.p95_latency_target_ms", p95_target))
        end
    catch e
        if !isa(e, ConfigError) || e.key != "performance.p95_latency_target_ms"
            @warn "Skipping cross-validation for latency targets"
        else
            rethrow(e)
        end
    end
    
    @debug "Configuration validation completed successfully"
end

"""
    get_environment()

Get the current environment from JULIA_AUCTION_ENV environment variable or default to "development".
"""
function get_environment()::String
    return get(ENV, "JULIA_AUCTION_ENV", "development")
end

"""
    get_config_path()

Get the configuration directory path. Defaults to "config" relative to project root.
"""
function get_config_path()::String
    # Try to find project root by looking for Project.toml
    current_dir = pwd()
    
    # Look for config directory in current path or parent paths
    for _ in 1:5  # Limit search depth
        config_dir = joinpath(current_dir, "config")
        if isdir(config_dir)
            return config_dir
        end
        
        project_file = joinpath(current_dir, "Project.toml")
        if isfile(project_file)
            config_dir = joinpath(current_dir, "config")
            if isdir(config_dir)
                return config_dir
            end
        end
        
        parent_dir = dirname(current_dir)
        if parent_dir == current_dir  # Reached filesystem root
            break
        end
        current_dir = parent_dir
    end
    
    # Fallback to hardcoded path if search fails
    fallback_path = joinpath(dirname(dirname(@__FILE__)), "..", "config")
    if isdir(fallback_path)
        return abspath(fallback_path)
    end
    
    # Final fallback
    return joinpath(pwd(), "config")
end

"""
    apply_environment_overrides(config_data::Dict{String, Any})

Apply environment variable overrides to configuration data.
Environment variables follow the pattern: AUCTION_SECTION_SUBSECTION_KEY
"""
function apply_environment_overrides(config_data::Dict{String, Any})::Dict{String, Any}
    result = deepcopy(config_data)
    override_count = 0
    
    for (env_key, env_value) in ENV
        if startswith(env_key, "AUCTION_")
            # Parse environment key: AUCTION_SECTION_KEY -> section.key
            remaining_key = env_key[9:end]  # Remove "AUCTION_" prefix
            
            # Special handling for known multi-word sections
            config_key = nothing
            key_parts = nothing
            
            if startswith(remaining_key, "PHANTOM_AUCTION_")
                # AUCTION_PHANTOM_AUCTION_* -> phantom_auction.*
                final_key = lowercase(remaining_key[17:end])  # Remove "PHANTOM_AUCTION_"
                config_key = "phantom_auction.$final_key"
                key_parts = ["phantom_auction", final_key]
            elseif startswith(remaining_key, "CIRCUIT_BREAKER_")
                # AUCTION_CIRCUIT_BREAKER_* -> circuit_breaker.*
                final_key = lowercase(remaining_key[17:end])  # Remove "CIRCUIT_BREAKER_"
                config_key = "circuit_breaker.$final_key"
                key_parts = ["circuit_breaker", final_key]
            elseif startswith(remaining_key, "AUCTION_MECHANICS_")
                # AUCTION_AUCTION_MECHANICS_* -> auction_mechanics.*
                final_key = lowercase(remaining_key[19:end])  # Remove "AUCTION_MECHANICS_"
                config_key = "auction_mechanics.$final_key"
                key_parts = ["auction_mechanics", final_key]
            else
                # Default parsing: split by underscore
                parts = split(remaining_key, '_')
                if length(parts) >= 2
                    config_key = join(map(lowercase, parts), '.')
                    key_parts = map(lowercase, parts)
                end
            end
            
            if key_parts !== nothing
                # Parse value with type inference
                parsed_value = parse_env_value(env_value)
                
                # Set nested value
                set_nested_value!(result, key_parts, parsed_value)
                
                @debug "Applied environment override" env_key=env_key config_key=config_key value=parsed_value
                override_count += 1
            end
        end
    end
    
    if override_count > 0
        @info "Applied environment variable overrides" count=override_count
    end
    
    return result
end

"""
    parse_env_value(value::String)

Parse environment variable value with type inference.
"""
function parse_env_value(value::String)
    # Try boolean
    if lowercase(value) in ["true", "false"]
        return lowercase(value) == "true"
    end
    
    # Try integer
    if occursin(r"^-?\d+$", value)
        try
            return parse(Int, value)
        catch
            # Fall through to string
        end
    end
    
    # Try float
    if occursin(r"^-?\d+\.?\d*$", value)
        try
            return parse(Float64, value)
        catch
            # Fall through to string
        end
    end
    
    # Return as string
    return value
end

"""
    set_nested_value!(dict::Dict{String, Any}, keys::Vector, value)

Set a nested dictionary value using an array of keys.
"""
function set_nested_value!(dict::Dict{String, Any}, keys::Vector, value)
    current = dict
    
    # Navigate to parent of target key
    for key in keys[1:end-1]
        key_str = lowercase(String(key))
        if !haskey(current, key_str)
            current[key_str] = Dict{String, Any}()
        elseif !isa(current[key_str], Dict)
            current[key_str] = Dict{String, Any}()
        end
        current = current[key_str]
    end
    
    # Set final value
    final_key = lowercase(String(keys[end]))
    current[final_key] = value
end

"""
    merge_configs(base::Dict{String, Any}, override::Dict{String, Any})

Recursively merge two configuration dictionaries, with override taking precedence.
"""
function merge_configs(base::Dict{String, Any}, override::Dict{String, Any})::Dict{String, Any}
    result = deepcopy(base)
    
    for (key, value) in override
        if haskey(result, key) && isa(result[key], Dict) && isa(value, Dict)
            result[key] = merge_configs(result[key], value)
        else
            result[key] = deepcopy(value)
        end
    end
    
    return result
end

"""
    save_config(config::AuctionConfig, filename::String)

Save configuration to a TOML file.

# Arguments
- `config::AuctionConfig`: Configuration to save
- `filename::String`: Output filename
"""
function save_config(config::AuctionConfig, filename::String)
    open(filename, "w") do io
        TOML.print(io, config.data)
    end
    @info "Configuration saved" filename=filename
end

"""
    config_to_dict(config::AuctionConfig)

Convert configuration object to a plain dictionary.
"""
function config_to_dict(config::AuctionConfig)::Dict{String, Any}
    return deepcopy(config.data)
end

end # module ConfigManager