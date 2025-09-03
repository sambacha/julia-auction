module ValidatorRegistryModule

using Dates
using UUIDs
using SHA

export Validator,
    ValidatorRegistry,
    SlashEvent,
    register_validator,
    update_validator,
    get_validator,
    is_validator_active,
    slash_validator,
    update_reputation,
    get_validators_for_epoch,
    rotate_proposer_duties

# Slashing event structure
struct SlashEvent
    event_id::UUID
    validator_pubkey::String
    slash_type::Symbol  # :double_sign, :surround_vote, :inactivity, :mev_theft
    slash_amount::Float64
    slot_number::Int64
    timestamp::DateTime
    evidence_hash::Vector{UInt8}
end

# Validator information structure
mutable struct Validator
    pubkey::String
    validator_index::Int64
    stake_amount::Float64
    effective_balance::Float64
    activation_epoch::Int64
    exit_epoch::Union{Nothing,Int64}
    withdrawable_epoch::Union{Nothing,Int64}
    reputation_score::Float64
    mev_preference::Symbol  # :maximize, :fair, :censor_resistant, :smoothing
    builder_preferences::Vector{String}  # Preferred builders
    slash_history::Vector{SlashEvent}
    total_slots_proposed::Int64
    successful_proposals::Int64
    missed_proposals::Int64
    average_block_value::Float64
    last_proposal_slot::Union{Nothing,Int64}
    registration_timestamp::DateTime
    last_updated::DateTime
    metadata::Dict{String,Any}
end

# Validator registry for managing validators
mutable struct ValidatorRegistry
    validators::Dict{String,Validator}
    active_validators::Set{String}
    exited_validators::Set{String}
    slashed_validators::Set{String}
    proposer_schedule::Dict{Int64,String}  # slot => validator_pubkey
    reputation_threshold::Float64
    min_stake::Float64
    max_validators::Int64
    current_epoch::Int64
    registry_lock::ReentrantLock
end

# Create a new validator registry
function ValidatorRegistry(;
    reputation_threshold::Float64 = 0.5,
    min_stake::Float64 = 32.0,
    max_validators::Int64 = 1_000_000,
)::ValidatorRegistry
    return ValidatorRegistry(
        Dict{String,Validator}(),
        Set{String}(),
        Set{String}(),
        Set{String}(),
        Dict{Int64,String}(),
        reputation_threshold,
        min_stake,
        max_validators,
        0,
        ReentrantLock(),
    )
end

# Register a new validator
function register_validator(
    registry::ValidatorRegistry,
    pubkey::String,
    stake_amount::Float64;
    validator_index::Int64 = -1,
    activation_epoch::Int64 = -1,
    mev_preference::Symbol = :fair,
    builder_preferences::Vector{String} = String[],
)::Bool
    lock(registry.registry_lock) do
        # Check if validator already exists
        if haskey(registry.validators, pubkey)
            @warn "Validator already registered" pubkey=pubkey
            return false
        end

        # Check minimum stake requirement
        if stake_amount < registry.min_stake
            @warn "Insufficient stake" stake=stake_amount min_stake=registry.min_stake
            return false
        end

        # Check max validators limit
        if length(registry.validators) >= registry.max_validators
            @warn "Max validators reached" current=length(registry.validators) max=registry.max_validators
            return false
        end

        # Create new validator
        validator = Validator(
            pubkey,
            validator_index == -1 ? length(registry.validators) + 1 : validator_index,
            stake_amount,
            stake_amount,  # Initially, effective balance equals stake
            activation_epoch == -1 ? registry.current_epoch + 1 : activation_epoch,
            nothing,  # exit_epoch
            nothing,  # withdrawable_epoch
            1.0,      # Initial reputation score
            mev_preference,
            builder_preferences,
            SlashEvent[],
            0,        # total_slots_proposed
            0,        # successful_proposals
            0,        # missed_proposals
            0.0,      # average_block_value
            nothing,  # last_proposal_slot
            now(),
            now(),
            Dict{String,Any}(),
        )

        # Add to registry
        registry.validators[pubkey] = validator
        push!(registry.active_validators, pubkey)

        @info "Validator registered" pubkey=pubkey stake=stake_amount index=validator.validator_index

        return true
    end
end

# Update validator information
function update_validator(
    registry::ValidatorRegistry,
    pubkey::String;
    stake_amount::Union{Nothing,Float64} = nothing,
    mev_preference::Union{Nothing,Symbol} = nothing,
    builder_preferences::Union{Nothing,Vector{String}} = nothing,
    metadata::Union{Nothing,Dict{String,Any}} = nothing,
)::Bool
    lock(registry.registry_lock) do
        if !haskey(registry.validators, pubkey)
            @warn "Validator not found" pubkey=pubkey
            return false
        end

        validator = registry.validators[pubkey]

        if stake_amount !== nothing
            validator.stake_amount = stake_amount
            validator.effective_balance = min(stake_amount, 32.0)  # Cap at 32 ETH
        end

        if mev_preference !== nothing
            validator.mev_preference = mev_preference
        end

        if builder_preferences !== nothing
            validator.builder_preferences = builder_preferences
        end

        if metadata !== nothing
            merge!(validator.metadata, metadata)
        end

        validator.last_updated = now()

        @info "Validator updated" pubkey=pubkey

        return true
    end
end

# Get validator information
function get_validator(registry::ValidatorRegistry, pubkey::String)::Union{Nothing,Validator}
    lock(registry.registry_lock) do
        return get(registry.validators, pubkey, nothing)
    end
end

# Check if validator is active
function is_validator_active(registry::ValidatorRegistry, pubkey::String)::Bool
    lock(registry.registry_lock) do
        return pubkey in registry.active_validators
    end
end

# Slash a validator for misbehavior
function slash_validator(
    registry::ValidatorRegistry,
    pubkey::String,
    slash_type::Symbol,
    slash_amount::Float64,
    slot_number::Int64;
    evidence_hash::Vector{UInt8} = UInt8[],
)::Bool
    lock(registry.registry_lock) do
        if !haskey(registry.validators, pubkey)
            @warn "Validator not found for slashing" pubkey=pubkey
            return false
        end

        validator = registry.validators[pubkey]

        # Create slash event
        slash_event = SlashEvent(uuid4(), pubkey, slash_type, slash_amount, slot_number, now(), evidence_hash)

        # Apply slashing
        push!(validator.slash_history, slash_event)
        validator.effective_balance = max(0.0, validator.effective_balance - slash_amount)

        # Update reputation
        reputation_penalty =
            slash_type == :double_sign ? 0.5 : slash_type == :mev_theft ? 0.3 : slash_type == :surround_vote ? 0.4 : 0.1

        validator.reputation_score = max(0.0, validator.reputation_score - reputation_penalty)

        # Mark as slashed if severe
        if slash_type in [:double_sign, :surround_vote, :mev_theft]
            delete!(registry.active_validators, pubkey)
            push!(registry.slashed_validators, pubkey)
            validator.exit_epoch = registry.current_epoch + 1
            validator.withdrawable_epoch = registry.current_epoch + 256
        end

        @warn "Validator slashed" pubkey=pubkey slash_type=slash_type amount=slash_amount

        return true
    end
end

# Update validator reputation based on performance
function update_reputation(
    registry::ValidatorRegistry,
    pubkey::String,
    slot_number::Int64,
    proposal_success::Bool,
    block_value::Float64,
)::Bool
    lock(registry.registry_lock) do
        if !haskey(registry.validators, pubkey)
            @warn "Validator not found" pubkey=pubkey
            return false
        end

        validator = registry.validators[pubkey]

        # Update proposal statistics
        validator.total_slots_proposed += 1
        if proposal_success
            validator.successful_proposals += 1

            # Update average block value
            if validator.average_block_value == 0.0
                validator.average_block_value = block_value
            else
                # Exponential moving average
                α = 0.1
                validator.average_block_value = α * block_value + (1 - α) * validator.average_block_value
            end
        else
            validator.missed_proposals += 1
        end

        validator.last_proposal_slot = slot_number

        # Calculate new reputation score
        success_rate = validator.successful_proposals / max(1, validator.total_slots_proposed)

        # Reputation factors:
        # - Success rate (40%)
        # - No recent slashing (30%)
        # - Consistent performance (30%)

        base_score = success_rate * 0.4

        # Check for recent slashing
        recent_slashes = count(s -> (now() - s.timestamp).value < 86400000 * 30, validator.slash_history)  # Last 30 days
        slash_penalty = min(1.0, recent_slashes * 0.1)
        slash_score = (1.0 - slash_penalty) * 0.3

        # Consistency score (low variance in performance)
        consistency_score =
            validator.missed_proposals == 0 ? 0.3 :
            max(0.0, 0.3 * (1.0 - validator.missed_proposals / validator.total_slots_proposed))

        validator.reputation_score = min(1.0, base_score + slash_score + consistency_score)

        @info "Reputation updated" pubkey=pubkey reputation=validator.reputation_score success=proposal_success

        return true
    end
end

# Get validators eligible for a specific epoch
function get_validators_for_epoch(registry::ValidatorRegistry, epoch::Int64)::Vector{Validator}
    lock(registry.registry_lock) do
        eligible = Validator[]

        for pubkey in registry.active_validators
            validator = registry.validators[pubkey]

            # Check if validator is active in this epoch
            if validator.activation_epoch <= epoch &&
               (validator.exit_epoch === nothing || validator.exit_epoch > epoch) &&
               validator.reputation_score >= registry.reputation_threshold
                push!(eligible, validator)
            end
        end

        # Sort by effective balance (higher stake gets priority)
        sort!(eligible, by = v->v.effective_balance, rev = true)

        return eligible
    end
end

# Rotate proposer duties for upcoming slots
function rotate_proposer_duties(
    registry::ValidatorRegistry,
    start_slot::Int64,
    end_slot::Int64;
    seed::Vector{UInt8} = rand(UInt8, 32),
)::Dict{Int64,String}
    lock(registry.registry_lock) do
        eligible_validators = get_validators_for_epoch(registry.current_epoch)

        if isempty(eligible_validators)
            @warn "No eligible validators for proposer rotation"
            return Dict{Int64,String}()
        end

        schedule = Dict{Int64,String}()

        for slot = start_slot:end_slot
            # Deterministic selection based on slot and seed
            slot_seed = sha256(vcat(seed, reinterpret(UInt8, [slot])))
            index = Int(reinterpret(UInt64, slot_seed[1:8])[1] % length(eligible_validators)) + 1

            selected_validator = eligible_validators[index]
            schedule[slot] = selected_validator.pubkey

            # Update registry schedule
            registry.proposer_schedule[slot] = selected_validator.pubkey
        end

        @info "Proposer duties rotated" start_slot=start_slot end_slot=end_slot validators=length(eligible_validators)

        return schedule
    end
end

# Get validator by slot assignment
function get_validator_for_slot(registry::ValidatorRegistry, slot::Int64)::Union{Nothing,Validator}
    lock(registry.registry_lock) do
        pubkey = get(registry.proposer_schedule, slot, nothing)
        if pubkey === nothing
            return nothing
        end
        return get(registry.validators, pubkey, nothing)
    end
end

# Export validator statistics
function export_validator_stats(registry::ValidatorRegistry)::Dict{String,Any}
    lock(registry.registry_lock) do
        stats = Dict{String,Any}(
            "total_validators" => length(registry.validators),
            "active_validators" => length(registry.active_validators),
            "slashed_validators" => length(registry.slashed_validators),
            "exited_validators" => length(registry.exited_validators),
            "current_epoch" => registry.current_epoch,
            "total_stake" => sum(v.stake_amount for v in values(registry.validators)),
            "average_reputation" => mean([
                v.reputation_score for v in values(registry.validators) if v.pubkey in registry.active_validators
            ]),
            "timestamp" => now(),
        )

        return stats
    end
end

# Helper function for mean calculation
function mean(values::Vector{Float64})::Float64
    isempty(values) ? 0.0 : sum(values) / length(values)
end

end # module
