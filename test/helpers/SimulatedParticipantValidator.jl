"""
    SimulatedParticipantValidator

Test helper for simulating participant decision making in coordination protocols.
This module contains test/simulation code that was removed from production modules.

**WARNING: FOR TESTING ONLY - DO NOT USE IN PRODUCTION**
"""
module SimulatedParticipantValidator

using Base: UUID
using Dates: DateTime, now
using Random
# Import the production interfaces
include("../../settlement/orchestration/coordinator/ParticipantDecisionInterface.jl")
using .ParticipantDecisionInterface: AbstractParticipantValidator, ValidationRequest, ValidationResult
export SimulatedValidator, simulate_participant_decision, configure_failure_rates!

"""
    SimulatedValidator

Test implementation that simulates participant validation responses.
"""
mutable struct SimulatedValidator <: AbstractParticipantValidator
    base_success_rate::Float64
    failure_escalation_rate::Float64  # How much success rate drops per failure
    participant_reliability::Dict{UUID, Float64}
    response_delay_range::Tuple{Float64, Float64}  # Min/max response time in ms
    
    function SimulatedValidator(;
        base_success_rate::Float64 = 0.9,  # 90% success by default
        failure_escalation_rate::Float64 = 0.05,  # 5% penalty per failure
        response_delay_range::Tuple{Float64, Float64} = (10.0, 100.0)  # 10-100ms delay
    )
        new(base_success_rate, failure_escalation_rate, 
            Dict{UUID, Float64}(), response_delay_range)
    end
end

"""
    simulate_participant_decision(participant_id, phase, transaction; failure_history=0)

Simulate a participant's decision for a validation request.
Uses configurable success rates and failure escalation.

**FOR TESTING ONLY**

# Arguments
- `participant_id::UUID` - ID of participant making decision
- `phase::Symbol` - Validation phase (:prepare, :commit)  
- `transaction` - Transaction being validated
- `failure_history::Int` - Number of previous failures (optional)

# Returns
- `Bool` - `true` for approve, `false` for reject
"""
function simulate_participant_decision(validator::SimulatedValidator,
                                     participant_id::UUID, 
                                     phase::Symbol, 
                                     transaction;
                                     failure_history::Int = 0)
    # Get or initialize participant reliability
    if !haskey(validator.participant_reliability, participant_id)
        validator.participant_reliability[participant_id] = validator.base_success_rate
    end
    
    # Calculate success rate with failure penalty
    current_reliability = validator.participant_reliability[participant_id]
    reliability_penalty = failure_history * validator.failure_escalation_rate
    success_rate = max(0.1, current_reliability - reliability_penalty)
    
    # Update participant reliability based on decision
    decision = rand() < success_rate
    
    if !decision
        # Slightly reduce future reliability for this participant
        validator.participant_reliability[participant_id] = 
            max(0.1, current_reliability - 0.01)
    else
        # Slightly improve reliability on success
        validator.participant_reliability[participant_id] = 
            min(1.0, current_reliability + 0.005)
    end
    
    return decision
end

"""
    ParticipantDecisionInterface.validate_transaction(validator::SimulatedValidator, request) 

Test implementation that simulates validation with realistic delays and failure patterns.
"""
function ParticipantDecisionInterface.validate_transaction(validator::SimulatedValidator,
                                                         request::ValidationRequest)::ValidationResult
    start_time = time() * 1000  # Convert to milliseconds
    
    # Simulate network delay
    delay_range = validator.response_delay_range
    delay_ms = delay_range[1] + rand() * (delay_range[2] - delay_range[1])
    sleep(delay_ms / 1000)  # Convert to seconds for sleep
    
    # Simulate participant decision
    decision = simulate_participant_decision(
        validator, request.participant_id, request.phase, 
        request.transaction_data, failure_history=request.retry_attempt
    )
    
    # Generate appropriate reason
    reason = if decision
        phase_action = request.phase == :prepare ? "preparation" : "commitment"
        "Transaction $phase_action validated successfully"
    else
        failure_reasons = [
            "Insufficient balance verification",
            "State consistency check failed", 
            "Signature validation failed",
            "Network timeout during validation",
            "Resource constraints prevent validation"
        ]
        rand(failure_reasons)
    end
    
    response_time = (time() * 1000) - start_time
    
    return ValidationResult(
        request.participant_id,
        request.transaction_id,
        request.phase,
        decision,
        reason=reason,
        response_time_ms=response_time
    )
end

"""
    configure_failure_rates!(validator, participant_rates)

Configure individual failure rates for specific participants.

# Arguments
- `validator::SimulatedValidator` - Validator to configure
- `participant_rates::Dict{UUID, Float64}` - Participant-specific success rates
"""
function configure_failure_rates!(validator::SimulatedValidator,
                                 participant_rates::Dict{UUID, Float64})
    for (participant_id, success_rate) in participant_rates
        if success_rate < 0.0 || success_rate > 1.0
            throw(ArgumentError("Success rate must be between 0.0 and 1.0"))
        end
        validator.participant_reliability[participant_id] = success_rate
    end
    
    println("INFO: Configured custom reliability for $(length(participant_rates)) participants")
end

"""
    simulate_network_partition!(validator, partitioned_participants)

Simulate network partition by setting certain participants to always fail.
"""
function simulate_network_partition!(validator::SimulatedValidator,
                                   partitioned_participants::Vector{UUID})
    for participant_id in partitioned_participants
        validator.participant_reliability[participant_id] = 0.0
    end
    
    println("WARNING: Simulated network partition for $(length(partitioned_participants)) participants")
end

"""
    reset_simulation_state!(validator)

Reset all simulation state to initial conditions.
"""
function reset_simulation_state!(validator::SimulatedValidator)
    empty!(validator.participant_reliability)
    println("INFO: Reset simulation state for all participants")
end

"""
    get_simulation_stats(validator) -> Dict

Get statistics about the simulation behavior.
"""
function get_simulation_stats(validator::SimulatedValidator)
    if isempty(validator.participant_reliability)
        return Dict(
            :tracked_participants => 0,
            :average_reliability => validator.base_success_rate
        )
    end
    
    avg_reliability = sum(values(validator.participant_reliability)) / 
                     length(validator.participant_reliability)
    
    return Dict(
        :tracked_participants => length(validator.participant_reliability),
        :average_reliability => avg_reliability,
        :min_reliability => minimum(values(validator.participant_reliability)),
        :max_reliability => maximum(values(validator.participant_reliability)),
        :base_success_rate => validator.base_success_rate,
        :failure_escalation_rate => validator.failure_escalation_rate
    )
end

end # module