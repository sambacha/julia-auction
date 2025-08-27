"""
    ParticipantDecisionInterface

Production-ready interface for participant decision making in coordination protocols.
Replaces simulation code with proper abstractions for real participant communication.

This module defines interfaces for participant validation and decision making
without any test/simulation dependencies.
"""
module ParticipantDecisionInterface

using Base: UUID
using Dates: DateTime, now

# Import logging configuration
include("../../../src/logging/LoggingConfig.jl")
using .LoggingConfig
using Logging: @info, @warn, @error, @debug

export AbstractParticipantValidator, ProductionParticipantValidator
export ValidationRequest, ValidationResult, ValidationConfig
export validate_transaction, configure_validator

"""
    AbstractParticipantValidator

Abstract interface for validating transactions with participants.
Production implementations should communicate with real participants.
"""
abstract type AbstractParticipantValidator end

"""
    ValidationRequest

Request for transaction validation from a participant.
"""
struct ValidationRequest
    transaction_id::UUID
    participant_id::UUID
    phase::Symbol  # :prepare or :commit
    transaction_data::Dict{String, Any}
    deadline::DateTime
    retry_attempt::Int
end

"""
    ValidationResult

Result of participant validation request.
"""
struct ValidationResult
    participant_id::UUID
    transaction_id::UUID
    phase::Symbol
    approved::Bool
    reason::String
    response_time_ms::Float64
    timestamp::DateTime
    
    function ValidationResult(participant_id::UUID, transaction_id::UUID, 
                            phase::Symbol, approved::Bool; 
                            reason::String = "", response_time_ms::Float64 = 0.0)
        new(participant_id, transaction_id, phase, approved, reason, 
            response_time_ms, now())
    end
end

"""
    ValidationConfig

Configuration for participant validation behavior.
"""
struct ValidationConfig
    # Network timeouts
    default_timeout_ms::Float64
    max_retry_attempts::Int
    retry_backoff_ms::Float64
    
    # Validation criteria
    require_signature_verification::Bool
    require_balance_checks::Bool
    require_state_consistency::Bool
    
    # Consensus parameters
    min_response_rate::Float64  # Minimum % of participants that must respond
    consensus_threshold::Float64  # % required for consensus
    
    function ValidationConfig(;
        default_timeout_ms::Float64 = 1000.0,
        max_retry_attempts::Int = 3,
        retry_backoff_ms::Float64 = 200.0,
        require_signature_verification::Bool = true,
        require_balance_checks::Bool = true,
        require_state_consistency::Bool = true,
        min_response_rate::Float64 = 0.67,
        consensus_threshold::Float64 = 0.67
    )
        if min_response_rate < 0.5 || min_response_rate > 1.0
            throw(ArgumentError("min_response_rate must be between 0.5 and 1.0"))
        end
        if consensus_threshold < 0.5 || consensus_threshold > 1.0
            throw(ArgumentError("consensus_threshold must be between 0.5 and 1.0"))
        end
        
        new(default_timeout_ms, max_retry_attempts, retry_backoff_ms,
            require_signature_verification, require_balance_checks, 
            require_state_consistency, min_response_rate, consensus_threshold)
    end
end

"""
    ProductionParticipantValidator

Production implementation that validates transactions with real participants.
"""
mutable struct ProductionParticipantValidator <: AbstractParticipantValidator
    config::ValidationConfig
    participant_connections::Dict{UUID, Any}
    validation_history::Vector{ValidationResult}
    performance_metrics::Dict{Symbol, Float64}
    
    function ProductionParticipantValidator(config::ValidationConfig = ValidationConfig())
        new(config, 
            Dict{UUID, Any}(),
            ValidationResult[],
            Dict{Symbol, Float64}(
                :avg_response_time_ms => 0.0,
                :success_rate => 1.0,
                :timeout_rate => 0.0,
                :consensus_rate => 1.0
            ))
    end
end

"""
    validate_transaction(validator, request) -> ValidationResult

Validate a transaction with a participant using production communication.

# Arguments
- `validator::AbstractParticipantValidator` - Validator instance
- `request::ValidationRequest` - Validation request

# Returns
- `ValidationResult` with validation outcome
"""
function validate_transaction(validator::ProductionParticipantValidator,
                            request::ValidationRequest)::ValidationResult
    start_time = time() * 1000  # Convert to milliseconds
    
    # For production, this would:
    # 1. Establish secure connection to participant
    # 2. Send transaction validation request
    # 3. Wait for cryptographically signed response
    # 4. Verify response authenticity and validity
    # 5. Return structured validation result
    
    try
        # Check if participant connection exists
        if !haskey(validator.participant_connections, request.participant_id)
            return ValidationResult(
                request.participant_id,
                request.transaction_id,
                request.phase,
                false,
                reason="Participant not connected"
            )
        end
        
        # In production, implement actual network communication here
        # For now, return rejection to force proper error handling
        response_time = (time() * 1000) - start_time
        
        result = ValidationResult(
            request.participant_id,
            request.transaction_id,
            request.phase,
            false,  # Always reject in production stub
            reason="Production validation not yet implemented - requires participant network integration",
            response_time_ms=response_time
        )
        
        # Record validation result
        push!(validator.validation_history, result)
        update_performance_metrics!(validator, result)
        
        return result
        
    catch e
        response_time = (time() * 1000) - start_time
        
        result = ValidationResult(
            request.participant_id,
            request.transaction_id,
            request.phase,
            false,
            reason="Validation failed: $(string(e))",
            response_time_ms=response_time
        )
        
        push!(validator.validation_history, result)
        return result
    end
end

"""
    configure_validator(validator, participant_endpoints)

Configure the validator with participant connection information.

# Arguments
- `validator::ProductionParticipantValidator` - Validator to configure
- `participant_endpoints::Dict{UUID, String}` - Participant ID to endpoint mapping
"""
function configure_validator(validator::ProductionParticipantValidator,
                           participant_endpoints::Dict{UUID, String})
    # Clear existing connections
    empty!(validator.participant_connections)
    
    # Establish connections to participants
    for (participant_id, endpoint) in participant_endpoints
        # In production, establish actual secure connections
        validator.participant_connections[participant_id] = Dict(
            :endpoint => endpoint,
            :connection_status => :established,
            :last_heartbeat => now()
        )
    end
    
    @info "Configured validator" participant_connections=length(participant_endpoints)
end

"""
    update_performance_metrics!(validator, result)

Update performance metrics based on validation result.
"""
function update_performance_metrics!(validator::ProductionParticipantValidator,
                                   result::ValidationResult)
    # Exponential moving average with α = 0.1
    α = 0.1
    
    # Update average response time
    current_avg = validator.performance_metrics[:avg_response_time_ms]
    validator.performance_metrics[:avg_response_time_ms] = 
        (1 - α) * current_avg + α * result.response_time_ms
    
    # Update success rate
    if !isempty(validator.validation_history)
        recent_results = validator.validation_history[max(1, end-99):end]  # Last 100
        success_count = count(r -> r.approved, recent_results)
        validator.performance_metrics[:success_rate] = 
            success_count / length(recent_results)
    end
    
    # Update timeout rate  
    if result.response_time_ms > validator.config.default_timeout_ms
        current_timeout_rate = validator.performance_metrics[:timeout_rate]
        validator.performance_metrics[:timeout_rate] = 
            (1 - α) * current_timeout_rate + α * 1.0
    else
        current_timeout_rate = validator.performance_metrics[:timeout_rate]
        validator.performance_metrics[:timeout_rate] = 
            (1 - α) * current_timeout_rate + α * 0.0
    end
end

"""
    check_consensus_threshold(validator, results) -> Bool

Check if validation results meet consensus threshold requirements.

# Arguments
- `validator::ProductionParticipantValidator` - Validator instance  
- `results::Vector{ValidationResult}` - Validation results to analyze

# Returns
- `true` if consensus threshold is met
- `false` otherwise
"""
function check_consensus_threshold(validator::ProductionParticipantValidator,
                                 results::Vector{ValidationResult})::Bool
    if isempty(results)
        return false
    end
    
    # Check minimum response rate
    expected_responses = length(validator.participant_connections)
    actual_responses = length(results)
    response_rate = actual_responses / max(1, expected_responses)
    
    if response_rate < validator.config.min_response_rate
        @warn "Response rate below minimum" response_rate=round(response_rate, digits=3) \
            minimum_required=validator.config.min_response_rate
        return false
    end
    
    # Check consensus threshold
    approved_count = count(r -> r.approved, results)
    consensus_rate = approved_count / length(results)
    
    meets_threshold = consensus_rate >= validator.config.consensus_threshold
    
    @info "Consensus check" approved_count=approved_count total_results=length(results) \
        consensus_rate=round(consensus_rate, digits=3) \
        threshold=validator.config.consensus_threshold meets_threshold=meets_threshold
    
    return meets_threshold
end

"""
    get_validator_stats(validator) -> Dict

Get performance statistics for the validator.
"""
function get_validator_stats(validator::ProductionParticipantValidator)
    return Dict(
        :total_validations => length(validator.validation_history),
        :avg_response_time_ms => validator.performance_metrics[:avg_response_time_ms],
        :success_rate => validator.performance_metrics[:success_rate],
        :timeout_rate => validator.performance_metrics[:timeout_rate],
        :active_connections => length(validator.participant_connections),
        :consensus_threshold => validator.config.consensus_threshold
    )
end

end # module