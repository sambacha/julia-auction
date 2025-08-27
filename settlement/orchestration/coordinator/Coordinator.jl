"""
    Coordinator

Multi-party coordination module implementing two-phase commit protocol for
atomic settlement execution across multiple participants.

Provides production-ready coordination for complex settlement scenarios involving
multiple counterparties, cross-chain operations, and distributed consensus.

# Key Features
- Two-phase commit protocol with timeout handling
- Participant health monitoring with heartbeat tracking  
- Consensus mechanism with configurable thresholds
- Thread-safe operations using Julia's atomic primitives
- Graceful degradation for failed participants
- Comprehensive audit logging for all decisions

# Core Components
- `Participant` - Individual participant representation
- `Vote` - Voting record for consensus phases
- `ConsensusProtocol` - Consensus configuration and logic
- `CoordinationContext` - Runtime coordination state
"""
module Coordinator

using Base.Threads: Atomic, atomic_cas!, atomic_add!, ReentrantLock
using Base: UUID
using Dates: DateTime, now, value
using UUIDs: uuid4
# Import configuration manager
include("../../../src/config/ConfigManager.jl")
using .ConfigManager: load_config, get_config, AuctionConfig
# Import logging configuration  
include("../../../src/logging/LoggingConfig.jl")
using .LoggingConfig: configure_logging!, set_correlation_id!, get_correlation_id
using Logging: @info, @warn, @error, @debug
# Import production participant validation interface
include("ParticipantDecisionInterface.jl")
using .ParticipantDecisionInterface: AbstractParticipantValidator,
                                        ProductionParticipantValidator
using .ParticipantDecisionInterface: ValidationRequest, ValidationResult, ValidationConfig
using .ParticipantDecisionInterface: validate_transaction, configure_validator
export Participant, Vote, ConsensusProtocol, CoordinationContext
export coordinate_settlement, collect_votes, check_consensus
export monitor_health, handle_failure, atomic_state_update
export register_participant, unregister_participant
export configure_coordination_validator

"""
    Vote

Records a participant's vote during consensus phases.
Provides audit trail for all settlement decisions.

# Fields
- `participant_id::UUID` - Voting participant identifier  
- `phase::Symbol` - Voting phase (:prepare, :commit)
- `decision::Bool` - Vote outcome (true = approve, false = reject)
- `timestamp::Float64` - When vote was cast
- `reason::Union{String, Nothing}` - Optional reason for vote
"""
struct Vote
    participant_id::UUID
    phase::Symbol
    decision::Bool
    timestamp::Float64
    reason::Union{String, Nothing}
    
    function Vote(participant_id::UUID, phase::Symbol, decision::Bool; reason=nothing)
        new(participant_id, phase, decision, time(), reason)
    end
end

"""
    Participant

Represents a participant in the multi-party settlement process.
Tracks participant status, connectivity, and voting history.

# Fields  
- `id::UUID` - Unique participant identifier
- `address::String` - Network address or endpoint
- `status::Symbol` - Current status (:active, :inactive, :failed)
- `last_heartbeat::Float64` - Timestamp of last heartbeat
- `vote_history::Vector{Vote}` - Historical voting record
- `connection_count::Atomic{Int}` - Thread-safe connection counter
"""
mutable struct Participant
    id::UUID
    address::String
    status::Symbol
    last_heartbeat::Float64
    vote_history::Vector{Vote}
    connection_count::Atomic{Int}
    
    function Participant(id::UUID, address::String)
        new(
            id,
            address,
            :active,
            time(),
            Vote[],
            Atomic{Int}(0)
        )
    end
end

"""
    ConsensusProtocol

Configuration for consensus mechanism and timing parameters.

# Fields
- `threshold::Float64` - Percentage required for consensus (0.0-1.0)
- `timeout::Float64` - Seconds to wait for votes
- `retry_count::Int` - Number of retry attempts
- `heartbeat_interval::Float64` - Seconds between heartbeats
"""
mutable struct ConsensusProtocol
    threshold::Float64
    timeout::Float64
    retry_count::Int
    heartbeat_interval::Float64
    
    function ConsensusProtocol(;
        threshold::Float64 = nothing,
        timeout::Float64 = nothing,
        retry_count::Int = nothing,
        heartbeat_interval::Float64 = nothing,
        config::AuctionConfig = load_config()
    )
        # Use provided values or load from config
        final_threshold = threshold !== nothing ? threshold :
            get_config(config, "coordinator.consensus_threshold", Float64)
        final_timeout = timeout !== nothing ? timeout :
            get_config(config, "coordinator.timeout_seconds", Float64)
        final_retry_count = retry_count !== nothing ? retry_count :
            get_config(config, "coordinator.retry_count", Int)
        final_heartbeat_interval = heartbeat_interval !== nothing ?
            heartbeat_interval :
            get_config(config, "coordinator.heartbeat_interval_seconds", Float64)
        
        if final_threshold < 0.5 || final_threshold > 1.0
            throw(ArgumentError("Consensus threshold must be between 0.5 and 1.0"))
        end
        new(final_threshold, final_timeout, final_retry_count, final_heartbeat_interval)
    end
end

"""
    CoordinationContext

Runtime context for multi-party coordination operations.
Maintains participant registry and coordination state.

# Fields
- `participants::Dict{UUID, Participant}` - Active participants
- `protocol::ConsensusProtocol` - Consensus configuration
- `transaction_id::UUID` - Current transaction being coordinated
- `phase::Symbol` - Current coordination phase
- `votes::Vector{Vote}` - Collected votes for current phase
- `state_lock::ReentrantLock` - Thread-safe state updates
- `active_channels::Dict{UUID, Channel}` - Communication channels
- `validator::AbstractParticipantValidator` - Production participant validator
"""
mutable struct CoordinationContext
    participants::Dict{UUID, Participant}
    protocol::ConsensusProtocol
    transaction_id::UUID
    phase::Symbol
    votes::Vector{Vote}
    state_lock::ReentrantLock
    active_channels::Dict{UUID, Channel}
    validator::AbstractParticipantValidator
    
    function CoordinationContext(protocol::ConsensusProtocol = ConsensusProtocol(),
                               validator::AbstractParticipantValidator =
                                   ProductionParticipantValidator(),
                               config::AuctionConfig = load_config())
        new(
            Dict{UUID, Participant}(),
            protocol,
            uuid4(),
            :idle,
            Vote[],
            ReentrantLock(),
            Dict{UUID, Channel}(),
            validator
        )
    end
end

"""
    coordinate_settlement(context, transaction)

Execute two-phase commit protocol for multi-party settlement.
Coordinates prepare and commit phases with timeout and retry handling.

# Arguments
- `context::CoordinationContext` - Coordination runtime context
- `transaction` - Transaction to coordinate settlement for

# Returns
- `true` if settlement coordinated successfully
- `false` if consensus failed or timeout occurred

# Protocol Phases
1. Prepare Phase: Collect prepare votes from all active participants
2. Commit Phase: If consensus reached, collect commit votes and finalize
3. Abort Phase: If consensus failed, abort and clean up
"""
function coordinate_settlement(context::CoordinationContext, transaction)
    if isempty(context.participants)
        @warn "No participants registered for coordination"
        return false
    end
    
    @info "Starting settlement coordination" transaction_id=context.transaction_id \
        participant_count=length(context.participants)
    
    try
        # Phase 1: Prepare
        atomic_state_update(context, :prepare)
        context.transaction_id = transaction.id
        
        prepare_success = collect_votes(context, :prepare, transaction)
        if !prepare_success
            @warn "Prepare phase failed"
            atomic_state_update(context, :aborted)
            return false
        end
        
        consensus_reached = check_consensus(context, context.votes)
        if !consensus_reached
            @warn "Prepare consensus not reached"
            atomic_state_update(context, :aborted)
            return false
        end
        
        @info "Prepare phase completed successfully"
        
        # Phase 2: Commit
        atomic_state_update(context, :commit)
        empty!(context.votes)  # Clear prepare votes
        
        commit_success = collect_votes(context, :commit, transaction)
        if !commit_success
            @error "Commit phase failed - initiating rollback"
            atomic_state_update(context, :rollback)
            return false
        end
        
        final_consensus = check_consensus(context, context.votes)
        if !final_consensus
            @error "Commit consensus not reached - initiating rollback"
            atomic_state_update(context, :rollback)
            return false
        end
        
        @info "Settlement coordination completed successfully"
        atomic_state_update(context, :completed)
        return true
        
    catch e
        @error "Settlement coordination failed" exception=e
        atomic_state_update(context, :error)
        return false
    finally
        # Clean up communication channels
        cleanup_channels(context)
    end
end

"""
    collect_votes(context, phase, transaction)

Collect votes from all active participants with timeout handling.
Uses parallel communication channels for efficient vote collection.

# Arguments
- `context::CoordinationContext` - Coordination context
- `phase::Symbol` - Voting phase (:prepare or :commit)  
- `transaction` - Transaction being voted on

# Returns
- `true` if votes collected within timeout
- `false` if timeout occurred or critical failures
"""
function collect_votes(context::CoordinationContext, phase::Symbol, transaction)
    active_participants = filter(
        p -> p.status == :active,
        collect(values(context.participants))
    )
    
    if isempty(active_participants)
        @error "No active participants for voting"
        return false
    end
    
    @info "Collecting votes" phase=phase participant_count=length(active_participants) \
        timeout_seconds=context.protocol.timeout
    
    # Create communication channels
    vote_channel = Channel{Vote}(length(active_participants) * 2)
    
    # Spawn vote collection tasks for each participant
    tasks = []
    for participant in active_participants
        task = Threads.@spawn request_vote(
            participant, phase, transaction, vote_channel,
            context.protocol.timeout, context.validator
        )
        push!(tasks, task)
    end
    
    # Collect votes with timeout
    collected_votes = Vote[]
    start_time = time()
    
    while (time() - start_time < context.protocol.timeout &&
           length(collected_votes) < length(active_participants))
        try
            vote = take!(vote_channel)
            push!(collected_votes, vote)
            push!(context.votes, vote)
            
            # Update participant vote history
            participant = get(context.participants, vote.participant_id, nothing)
            if participant !== nothing
                push!(participant.vote_history, vote)
            end
            
        catch e
            if isa(e, InvalidStateException)
                break  # Channel closed
            end
        end
    end
    
    close(vote_channel)
    
    # Wait for all tasks to complete
    for task in tasks
        try
            wait(task)
        catch e
            @warn "Vote collection task failed" exception=e
        end
    end
    
    success_rate = length(collected_votes) / length(active_participants)
    @info "Vote collection completed" votes_collected=length(collected_votes) \
        total_participants=length(active_participants) \
        response_rate=round(success_rate, digits=3)
    
    # Get minimum response rate from config (need to pass config somehow)
    # For now, use default since we don't have config accessible here
    # TODO: Make this configurable by passing config to this function
    min_response_rate = 0.5
    return success_rate >= min_response_rate
end

"""
    request_vote(participant, phase, transaction, vote_channel, timeout, validator)

Request a vote from a specific participant with timeout handling.
Uses production participant validation interface.
"""
function request_vote(
    participant::Participant,
    phase::Symbol,
    transaction,
    vote_channel::Channel{Vote},
    timeout::Float64,
    validator::AbstractParticipantValidator
)
    try
        # Network communication handled by validator
        
        # Check if participant is still active
        if participant.status != :active
            return
        end
        
        # Update heartbeat
        participant.last_heartbeat = time()
        atomic_add!(participant.connection_count, 1)
        
        # Use production participant validation
        validation_request = ValidationRequest(
            get(transaction, :id, uuid4()),  # Transaction ID
            participant.id,
            phase,
            Dict("transaction" => transaction),  # Transaction data
            # Deadline
            Dates.now() + Dates.Millisecond(timeout * 1000),
            0  # Initial retry attempt
        )
        
        # Get validation result from production validator
        validation_result = validate_transaction(validator, validation_request)
        
        decision = validation_result.approved
        reason = validation_result.reason
        
        vote = Vote(participant.id, phase, decision; reason=reason)
        
        # Try to send vote within remaining timeout
        try
            put!(vote_channel, vote)
            @info "Vote received" participant_id=participant.id phase=phase decision=decision
        catch e
            @warn "Failed to submit vote" participant_id=participant.id exception=e
        end
        
    catch e
        @error "Vote request failed" participant_id=participant.id exception=e
        handle_failure(participant)
    end
end

# Participant decision making moved to ParticipantDecisionInterface module

"""
    check_consensus(context, votes)

Verify that sufficient consensus has been reached for the current phase.
Applies the configured threshold to determine consensus outcome.

# Arguments
- `context::CoordinationContext` - Coordination context
- `votes::Vector{Vote}` - Votes to analyze

# Returns
- `true` if consensus threshold met
- `false` if insufficient consensus
"""
function check_consensus(context::CoordinationContext, votes::Vector{Vote})
    if isempty(votes)
        return false
    end
    
    # Count active participants for threshold calculation
    active_count = count(
        p -> p.status == :active,
        collect(values(context.participants))
    )
    
    if active_count == 0
        return false
    end
    
    # Count positive votes
    positive_votes = count(v -> v.decision, votes)
    
    # Calculate consensus percentage
    consensus_percentage = positive_votes / active_count
    
    reached = consensus_percentage >= context.protocol.threshold
    
    @info "Consensus check" positive_votes=positive_votes total_participants=active_count \
        consensus_rate=round(consensus_percentage, digits=3) \
        threshold=context.protocol.threshold consensus_reached=reached
    
    return reached
end

"""
    monitor_health(context)

Monitor participant health through heartbeat tracking.
Automatically marks participants as inactive if heartbeats are missed.

# Arguments
- `context::CoordinationContext` - Coordination context

# Returns
- Number of active participants after health check
"""
function monitor_health(context::CoordinationContext; config::AuctionConfig = load_config())
    current_time = time()
    # Get heartbeat timeout multiplier from config
    heartbeat_multiplier = get_config(
        config, "coordinator.heartbeat_timeout_multiplier", Float64, 3.0
    )
    heartbeat_timeout = context.protocol.heartbeat_interval * heartbeat_multiplier
    
    inactive_count = 0
    
    lock(context.state_lock) do
        for (id, participant) in context.participants
            if participant.status == :active
                time_since_heartbeat = current_time - participant.last_heartbeat
                
                if time_since_heartbeat > heartbeat_timeout
                    @warn "Participant heartbeat timeout" participant_id=id \
                        timeout_seconds=round(time_since_heartbeat, digits=1)
                    participant.status = :inactive
                    inactive_count += 1
                end
            end
        end
    end
    
    active_count = count(
        p -> p.status == :active,
        collect(values(context.participants))
    )
    
    if inactive_count > 0
        @info "Health monitoring completed" inactive_count=inactive_count \
            active_count=active_count
    end
    
    return active_count
end

"""
    handle_failure(participant)

Handle participant failure with graceful degradation.
Marks participant as failed and cleans up associated resources.

# Arguments
- `participant::Participant` - Failed participant
"""
function handle_failure(participant::Participant)
    @warn "Handling participant failure" participant_id=participant.id \
        address=participant.address
    
    participant.status = :failed
    participant.last_heartbeat = 0.0
    
    # Log failure for audit trail
    failure_vote = Vote(
        participant.id, :failure, false;
        reason="Participant failure detected"
    )
    push!(participant.vote_history, failure_vote)
end

"""
    atomic_state_update(context, new_phase)

Thread-safe update of coordination context phase.
Uses locks to ensure consistency across concurrent operations.

# Arguments
- `context::CoordinationContext` - Context to update
- `new_phase::Symbol` - New phase to transition to
"""
function atomic_state_update(context::CoordinationContext, new_phase::Symbol)
    lock(context.state_lock) do
        old_phase = context.phase
        context.phase = new_phase
        @info "Phase transition" old_phase=old_phase new_phase=new_phase \
            transaction_id=context.transaction_id
    end
end

"""
    register_participant(context, address)

Register a new participant in the coordination context.

# Arguments
- `context::CoordinationContext` - Context to register with
- `address::String` - Participant network address

# Returns
- `UUID` of registered participant
"""
function register_participant(context::CoordinationContext, address::String)
    participant_id = uuid4()
    participant = Participant(participant_id, address)
    
    lock(context.state_lock) do
        context.participants[participant_id] = participant
    end
    
    @info "Participant registered" participant_id=participant_id address=address
    return participant_id
end

"""
    unregister_participant(context, participant_id)

Unregister a participant from the coordination context.

# Arguments  
- `context::CoordinationContext` - Context to unregister from
- `participant_id::UUID` - ID of participant to remove

# Returns
- `true` if participant was found and removed
- `false` if participant was not found
"""
function unregister_participant(context::CoordinationContext, participant_id::UUID)
    removed = false
    
    lock(context.state_lock) do
        if haskey(context.participants, participant_id)
            delete!(context.participants, participant_id)
            removed = true
        end
    end
    
    if removed
        @info "Participant unregistered" participant_id=participant_id
    else
        @warn "Attempted to unregister unknown participant" participant_id=participant_id
    end
    
    return removed
end

"""
    cleanup_channels(context)

Clean up communication channels and release resources.
"""
function cleanup_channels(context::CoordinationContext)
    for (id, channel) in context.active_channels
        try
            close(channel)
        catch e
            @warn "Error closing channel" participant_id=id exception=e
        end
    end
    empty!(context.active_channels)
end

"""
    configure_coordination_validator(context, participant_endpoints)

Configure the coordination context with a production participant validator.

# Arguments
- `context::CoordinationContext` - Context to configure
- `participant_endpoints::Dict{UUID, String}` - Participant ID to endpoint mapping
"""
function configure_coordination_validator(context::CoordinationContext,
                                        participant_endpoints::Dict{UUID, String})
    if isa(context.validator, ProductionParticipantValidator)
        configure_validator(context.validator, participant_endpoints)
    else
        @warn "Context is not using ProductionParticipantValidator - " *
              "configuration ignored"
    end
end

end # module Coordinator