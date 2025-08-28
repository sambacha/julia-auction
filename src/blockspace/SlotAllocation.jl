module SlotAllocationModule

using Dates
using UUIDs
using Statistics

export SlotAllocation, AllocationStrategy, SlotSchedule, AllocationResult,
       allocate_slots, create_slot_schedule, get_slot_allocation,
       update_allocation_status, calculate_allocation_metrics,
       fair_allocation, weighted_allocation, priority_allocation

# Slot allocation structure
struct SlotAllocation
    allocation_id::UUID
    slot_number::Int64
    epoch::Int64
    validator_pubkey::String
    builder_id::String
    block_value::Float64
    mev_value::Float64
    gas_limit::Int64
    gas_used::Int64
    allocation_time::DateTime
    execution_time::Union{Nothing, DateTime}
    status::Symbol  # :pending, :allocated, :executed, :missed, :reorged
    metadata::Dict{String, Any}
end

# Allocation strategy configuration
struct AllocationStrategy
    strategy_type::Symbol  # :fair, :weighted, :priority, :auction_based
    lookahead_slots::Int64
    reallocation_enabled::Bool
    min_validator_stake::Float64
    priority_threshold::Float64
    mev_smoothing_enabled::Bool
    smoothing_pool_ratio::Float64
end

# Slot schedule for multiple epochs
mutable struct SlotSchedule
    schedule_id::UUID
    start_epoch::Int64
    end_epoch::Int64
    slots_per_epoch::Int64
    allocations::Dict{Int64, SlotAllocation}  # slot_number => allocation
    pending_slots::Set{Int64}
    executed_slots::Set{Int64}
    missed_slots::Set{Int64}
    creation_time::DateTime
    last_updated::DateTime
end

# Result of allocation process
struct AllocationResult
    success::Bool
    allocated_slots::Int64
    failed_slots::Int64
    total_value::Float64
    average_mev::Float64
    allocation_duration_ms::Float64
    errors::Vector{String}
end

# Create a new slot schedule
function create_slot_schedule(
    start_epoch::Int64,
    end_epoch::Int64;
    slots_per_epoch::Int64=32
)::SlotSchedule
    
    schedule_id = uuid4()
    total_slots = (end_epoch - start_epoch + 1) * slots_per_epoch
    
    # Initialize pending slots
    pending_slots = Set{Int64}()
    for epoch in start_epoch:end_epoch
        for slot in 0:(slots_per_epoch-1)
            push!(pending_slots, epoch * slots_per_epoch + slot)
        end
    end
    
    return SlotSchedule(
        schedule_id,
        start_epoch,
        end_epoch,
        slots_per_epoch,
        Dict{Int64, SlotAllocation}(),
        pending_slots,
        Set{Int64}(),
        Set{Int64}(),
        now(),
        now()
    )
end

# Main slot allocation function
function allocate_slots(
    schedule::SlotSchedule,
    validators::Vector{Tuple{String, Float64}},  # (pubkey, stake)
    builders::Vector{Tuple{String, Float64}},    # (builder_id, reputation)
    strategy::AllocationStrategy;
    auction_results::Union{Nothing, Vector{Any}}=nothing
)::AllocationResult
    
    start_time = now()
    allocated_count = 0
    failed_count = 0
    total_value = 0.0
    mev_values = Float64[]
    errors = String[]
    
    # Get slots to allocate
    slots_to_allocate = collect(schedule.pending_slots)
    sort!(slots_to_allocate)
    
    if isempty(validators)
        push!(errors, "No validators available for allocation")
        return AllocationResult(false, 0, length(slots_to_allocate), 0.0, 0.0, 0.0, errors)
    end
    
    if isempty(builders)
        push!(errors, "No builders available for allocation")
        return AllocationResult(false, 0, length(slots_to_allocate), 0.0, 0.0, 0.0, errors)
    end
    
    # Apply allocation strategy
    allocations = if strategy.strategy_type == :fair
        fair_allocation(slots_to_allocate, validators, builders, strategy)
    elseif strategy.strategy_type == :weighted
        weighted_allocation(slots_to_allocate, validators, builders, strategy)
    elseif strategy.strategy_type == :priority
        priority_allocation(slots_to_allocate, validators, builders, strategy)
    elseif strategy.strategy_type == :auction_based && auction_results !== nothing
        auction_based_allocation(slots_to_allocate, validators, builders, auction_results, strategy)
    else
        push!(errors, "Unknown allocation strategy: $(strategy.strategy_type)")
        return AllocationResult(false, 0, length(slots_to_allocate), 0.0, 0.0, 0.0, errors)
    end
    
    # Process allocations
    for (slot_number, validator_pubkey, builder_id, block_value, mev_value) in allocations
        epoch = slot_number ÷ schedule.slots_per_epoch
        
        allocation = SlotAllocation(
            uuid4(),
            slot_number,
            epoch,
            validator_pubkey,
            builder_id,
            block_value,
            mev_value,
            30_000_000,  # Default gas limit
            0,           # Gas used (unknown until execution)
            now(),
            nothing,     # Not executed yet
            :allocated,
            Dict{String, Any}()
        )
        
        # Add to schedule
        schedule.allocations[slot_number] = allocation
        delete!(schedule.pending_slots, slot_number)
        
        allocated_count += 1
        total_value += block_value
        push!(mev_values, mev_value)
        
        @info "Slot allocated" slot=slot_number validator=validator_pubkey builder=builder_id value=block_value
    end
    
    # Update failed slots
    failed_count = length(slots_to_allocate) - allocated_count
    
    # Calculate metrics
    average_mev = isempty(mev_values) ? 0.0 : mean(mev_values)
    duration_ms = Float64((now() - start_time).value)
    
    schedule.last_updated = now()
    
    return AllocationResult(
        allocated_count > 0,
        allocated_count,
        failed_count,
        total_value,
        average_mev,
        duration_ms,
        errors
    )
end

# Fair allocation strategy - round-robin distribution
function fair_allocation(
    slots::Vector{Int64},
    validators::Vector{Tuple{String, Float64}},
    builders::Vector{Tuple{String, Float64}},
    strategy::AllocationStrategy
)::Vector{Tuple{Int64, String, String, Float64, Float64}}
    
    allocations = Tuple{Int64, String, String, Float64, Float64}[]
    
    # Filter validators by minimum stake
    eligible_validators = filter(v -> v[2] >= strategy.min_validator_stake, validators)
    
    if isempty(eligible_validators)
        return allocations
    end
    
    validator_index = 1
    builder_index = 1
    
    for slot in slots
        # Round-robin selection
        validator = eligible_validators[validator_index]
        builder = builders[builder_index]
        
        # Estimate block value (simplified)
        base_value = 0.1  # Base reward in ETH
        mev_value = rand() * 0.5  # Random MEV between 0 and 0.5 ETH
        block_value = base_value + mev_value
        
        push!(allocations, (slot, validator[1], builder[1], block_value, mev_value))
        
        # Update indices
        validator_index = validator_index % length(eligible_validators) + 1
        builder_index = builder_index % length(builders) + 1
    end
    
    return allocations
end

# Weighted allocation strategy - based on stake and reputation
function weighted_allocation(
    slots::Vector{Int64},
    validators::Vector{Tuple{String, Float64}},
    builders::Vector{Tuple{String, Float64}},
    strategy::AllocationStrategy
)::Vector{Tuple{Int64, String, String, Float64, Float64}}
    
    allocations = Tuple{Int64, String, String, Float64, Float64}[]
    
    # Filter and sort validators by stake
    eligible_validators = filter(v -> v[2] >= strategy.min_validator_stake, validators)
    sort!(eligible_validators, by=v->v[2], rev=true)
    
    # Sort builders by reputation
    sorted_builders = sort(builders, by=b->b[2], rev=true)
    
    if isempty(eligible_validators) || isempty(sorted_builders)
        return allocations
    end
    
    # Calculate weights
    total_stake = sum(v[2] for v in eligible_validators)
    validator_weights = [v[2] / total_stake for v in eligible_validators]
    
    total_reputation = sum(b[2] for b in sorted_builders)
    builder_weights = [b[2] / total_reputation for b in sorted_builders]
    
    for slot in slots
        # Weighted random selection
        validator_idx = weighted_random_select(validator_weights)
        builder_idx = weighted_random_select(builder_weights)
        
        validator = eligible_validators[validator_idx]
        builder = sorted_builders[builder_idx]
        
        # Value proportional to stake and reputation
        base_value = 0.1 * (validator[2] / 32.0)  # Normalized by 32 ETH
        mev_value = rand() * 0.5 * builder[2]      # MEV scaled by reputation
        block_value = base_value + mev_value
        
        push!(allocations, (slot, validator[1], builder[1], block_value, mev_value))
    end
    
    return allocations
end

# Priority allocation strategy - high-priority validators/builders get preference
function priority_allocation(
    slots::Vector{Int64},
    validators::Vector{Tuple{String, Float64}},
    builders::Vector{Tuple{String, Float64}},
    strategy::AllocationStrategy
)::Vector{Tuple{Int64, String, String, Float64, Float64}}
    
    allocations = Tuple{Int64, String, String, Float64, Float64}[]
    
    # Separate high-priority entities
    high_priority_validators = filter(v -> v[2] >= strategy.priority_threshold * 32.0, validators)
    normal_validators = filter(v -> v[2] < strategy.priority_threshold * 32.0 && v[2] >= strategy.min_validator_stake, validators)
    
    high_priority_builders = filter(b -> b[2] >= strategy.priority_threshold, builders)
    normal_builders = filter(b -> b[2] < strategy.priority_threshold, builders)
    
    # Allocate high-value slots to high-priority entities
    high_value_slot_count = length(slots) ÷ 3  # Top 1/3 slots
    
    for (i, slot) in enumerate(slots)
        if i <= high_value_slot_count && !isempty(high_priority_validators) && !isempty(high_priority_builders)
            # High-priority allocation
            validator = high_priority_validators[rand(1:length(high_priority_validators))]
            builder = high_priority_builders[rand(1:length(high_priority_builders))]
            
            base_value = 0.2  # Higher base for priority slots
            mev_value = 0.3 + rand() * 0.7  # Higher MEV range
        else
            # Normal allocation
            all_validators = vcat(high_priority_validators, normal_validators)
            all_builders = vcat(high_priority_builders, normal_builders)
            
            if isempty(all_validators) || isempty(all_builders)
                continue
            end
            
            validator = all_validators[rand(1:length(all_validators))]
            builder = all_builders[rand(1:length(all_builders))]
            
            base_value = 0.1
            mev_value = rand() * 0.5
        end
        
        block_value = base_value + mev_value
        push!(allocations, (slot, validator[1], builder[1], block_value, mev_value))
    end
    
    return allocations
end

# Auction-based allocation using auction results
function auction_based_allocation(
    slots::Vector{Int64},
    validators::Vector{Tuple{String, Float64}},
    builders::Vector{Tuple{String, Float64}},
    auction_results::Vector{Any},
    strategy::AllocationStrategy
)::Vector{Tuple{Int64, String, String, Float64, Float64}}
    
    allocations = Tuple{Int64, String, String, Float64, Float64}[]
    
    # Map auction results to slots
    for (i, slot) in enumerate(slots)
        if i <= length(auction_results)
            result = auction_results[i]
            
            # Extract from auction result (adapt based on actual structure)
            validator_pubkey = get(result, :validator, validators[1][1])
            builder_id = get(result, :builder, builders[1][1])
            block_value = get(result, :block_value, 0.1)
            mev_value = get(result, :mev_value, 0.0)
            
            push!(allocations, (slot, validator_pubkey, builder_id, block_value, mev_value))
        else
            # Fallback to fair allocation for remaining slots
            validator = validators[mod(i-1, length(validators)) + 1]
            builder = builders[mod(i-1, length(builders)) + 1]
            
            push!(allocations, (slot, validator[1], builder[1], 0.1, rand() * 0.5))
        end
    end
    
    return allocations
end

# Weighted random selection helper
function weighted_random_select(weights::Vector{Float64})::Int64
    r = rand()
    cumsum = 0.0
    
    for (i, w) in enumerate(weights)
        cumsum += w
        if r <= cumsum
            return i
        end
    end
    
    return length(weights)
end

# Get allocation for a specific slot
function get_slot_allocation(
    schedule::SlotSchedule,
    slot_number::Int64
)::Union{Nothing, SlotAllocation}
    
    return get(schedule.allocations, slot_number, nothing)
end

# Update allocation status
function update_allocation_status(
    schedule::SlotSchedule,
    slot_number::Int64,
    new_status::Symbol;
    execution_time::Union{Nothing, DateTime}=nothing,
    gas_used::Union{Nothing, Int64}=nothing,
    metadata::Union{Nothing, Dict{String, Any}}=nothing
)::Bool
    
    allocation = get(schedule.allocations, slot_number, nothing)
    
    if allocation === nothing
        @warn "Allocation not found" slot=slot_number
        return false
    end
    
    # Create updated allocation
    updated = SlotAllocation(
        allocation.allocation_id,
        allocation.slot_number,
        allocation.epoch,
        allocation.validator_pubkey,
        allocation.builder_id,
        allocation.block_value,
        allocation.mev_value,
        allocation.gas_limit,
        gas_used !== nothing ? gas_used : allocation.gas_used,
        allocation.allocation_time,
        execution_time !== nothing ? execution_time : allocation.execution_time,
        new_status,
        metadata !== nothing ? merge(allocation.metadata, metadata) : allocation.metadata
    )
    
    schedule.allocations[slot_number] = updated
    
    # Update slot sets
    if new_status == :executed
        delete!(schedule.pending_slots, slot_number)
        push!(schedule.executed_slots, slot_number)
    elseif new_status == :missed
        delete!(schedule.pending_slots, slot_number)
        push!(schedule.missed_slots, slot_number)
    end
    
    schedule.last_updated = now()
    
    @info "Allocation status updated" slot=slot_number status=new_status
    
    return true
end

# Calculate allocation metrics
function calculate_allocation_metrics(
    schedule::SlotSchedule
)::Dict{String, Any}
    
    total_slots = length(schedule.allocations)
    executed = length(schedule.executed_slots)
    missed = length(schedule.missed_slots)
    pending = length(schedule.pending_slots)
    
    # Calculate value metrics
    total_value = sum(a.block_value for a in values(schedule.allocations))
    total_mev = sum(a.mev_value for a in values(schedule.allocations))
    
    executed_allocations = [a for a in values(schedule.allocations) if a.status == :executed]
    avg_gas_used = isempty(executed_allocations) ? 0.0 : 
                   mean([a.gas_used for a in executed_allocations])
    
    # Calculate timing metrics
    execution_times = DateTime[]
    for allocation in executed_allocations
        if allocation.execution_time !== nothing
            push!(execution_times, allocation.execution_time)
        end
    end
    
    metrics = Dict{String, Any}(
        "schedule_id" => schedule.schedule_id,
        "total_slots" => total_slots,
        "executed_slots" => executed,
        "missed_slots" => missed,
        "pending_slots" => pending,
        "execution_rate" => total_slots > 0 ? executed / total_slots : 0.0,
        "miss_rate" => total_slots > 0 ? missed / total_slots : 0.0,
        "total_value" => total_value,
        "total_mev" => total_mev,
        "average_block_value" => total_slots > 0 ? total_value / total_slots : 0.0,
        "average_mev" => total_slots > 0 ? total_mev / total_slots : 0.0,
        "average_gas_used" => avg_gas_used,
        "start_epoch" => schedule.start_epoch,
        "end_epoch" => schedule.end_epoch,
        "created" => schedule.creation_time,
        "last_updated" => schedule.last_updated
    )
    
    return metrics
end

# Reallocate missed or failed slots
function reallocate_missed_slots(
    schedule::SlotSchedule,
    validators::Vector{Tuple{String, Float64}},
    builders::Vector{Tuple{String, Float64}},
    strategy::AllocationStrategy
)::AllocationResult
    
    missed_slots = collect(schedule.missed_slots)
    
    if isempty(missed_slots)
        return AllocationResult(true, 0, 0, 0.0, 0.0, 0.0, String[])
    end
    
    # Move missed slots back to pending
    for slot in missed_slots
        push!(schedule.pending_slots, slot)
        delete!(schedule.missed_slots, slot)
    end
    
    # Reallocate
    return allocate_slots(schedule, validators, builders, strategy)
end

end # module