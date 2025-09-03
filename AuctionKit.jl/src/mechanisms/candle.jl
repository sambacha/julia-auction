# Candle auction implementation
# Following A/HC/LC naming pattern

"""
    CandleAuction{T}

Auction with a random ending time to prevent last-minute bidding.
Historically used a burning candle; modern versions use random termination.
"""
mutable struct CandleAuction{T} <: OpenOutcryAuction{T}
    starting_price::T
    current_price::T
    current_leader::Union{Nothing, UUID}
    bid_history::Vector{Tuple{UUID, T, DateTime}}
    start_time::DateTime
    min_duration::Float64  # Minimum auction duration in seconds
    max_duration::Float64  # Maximum auction duration in seconds
    termination_probability::Float64  # Probability of ending per time unit
    is_terminated::Bool
    termination_time::Union{Nothing, DateTime}
    random_seed::UInt64
    
    function CandleAuction(;
        starting_price::T = zero(T),
        min_duration::Float64 = 60.0,  # 1 minute minimum
        max_duration::Float64 = 600.0,  # 10 minutes maximum
        termination_probability::Float64 = 0.01,  # 1% per second after min_duration
        random_seed::UInt64 = rand(UInt64)
    ) where T
        starting_price >= 0 || throw(ArgumentError("Starting price must be non-negative"))
        min_duration > 0 || throw(ArgumentError("Minimum duration must be positive"))
        max_duration > min_duration || throw(ArgumentError("Maximum duration must exceed minimum"))
        0 < termination_probability < 1 || throw(ArgumentError("Termination probability must be between 0 and 1"))
        
        new{T}(
            starting_price,
            starting_price,
            nothing,
            Vector{Tuple{UUID, T, DateTime}}(),
            now(),
            min_duration,
            max_duration,
            termination_probability,
            false,
            nothing,
            random_seed
        )
    end
end

function check_random_termination(mechanism::CandleAuction{T}) where T
    if mechanism.is_terminated
        return true
    end
    
    current_time = now()
    elapsed_seconds = (current_time - mechanism.start_time).value / 1000.0
    
    # Cannot terminate before minimum duration
    if elapsed_seconds < mechanism.min_duration
        return false
    end
    
    # Must terminate at maximum duration
    if elapsed_seconds >= mechanism.max_duration
        mechanism.is_terminated = true
        mechanism.termination_time = current_time
        return true
    end
    
    # Random termination check (using deterministic pseudo-random for reproducibility)
    Random.seed!(mechanism.random_seed + round(UInt64, elapsed_seconds))
    if rand() < mechanism.termination_probability
        mechanism.is_terminated = true
        mechanism.termination_time = current_time
        return true
    end
    
    return false
end

function acceptCandleBid(mechanism::CandleAuction{T}, bid::Bid{T}) where T
    # Check if auction has terminated
    if check_random_termination(mechanism)
        return false, "Auction has terminated"
    end
    
    # Bid must exceed current price
    if bid.amount <= mechanism.current_price
        return false, "Bid must exceed current price of $(mechanism.current_price)"
    end
    
    # Update auction state
    mechanism.current_price = bid.amount
    mechanism.current_leader = bid.bidder_id
    push!(mechanism.bid_history, (bid.bidder_id, bid.amount, now()))
    
    return true, "Bid accepted as new leader"
end

function getValidBidsAtTermination(mechanism::CandleAuction{T}) where T
    if isnothing(mechanism.termination_time)
        # Auction hasn't terminated yet
        return mechanism.bid_history
    end
    
    # Only consider bids made before termination
    valid_bids = filter(
        h -> h[3] <= mechanism.termination_time,
        mechanism.bid_history
    )
    
    return valid_bids
end

function determine_clearing_price(mechanism::CandleAuction{T}, bids::Vector{Bid{T}}) where T
    valid_history = getValidBidsAtTermination(mechanism)
    
    if isempty(valid_history)
        return mechanism.starting_price
    end
    
    # Highest valid bid at termination wins
    highest_bid = maximum(h -> h[2], valid_history)
    return highest_bid
end

function allocate_winners(
    mechanism::CandleAuction{T},
    bids::Vector{Bid{T}},
    clearing_price::T
) where T
    valid_history = getValidBidsAtTermination(mechanism)
    
    if isempty(valid_history)
        return UUID[], Dict{UUID, T}()
    end
    
    # Find winner with highest bid at termination
    highest_amount = maximum(h -> h[2], valid_history)
    winning_entries = filter(h -> h[2] == highest_amount, valid_history)
    
    if isempty(winning_entries)
        return UUID[], Dict{UUID, T}()
    end
    
    # If multiple bids at same price, earliest wins
    winner_entry = winning_entries[argmin([h[3] for h in winning_entries])]
    winner_id = winner_entry[1]
    
    winners = [winner_id]
    allocations = Dict{UUID, T}(winner_id => one(T))
    
    return winners, allocations
end

function calculate_payments(
    mechanism::CandleAuction{T},
    winners::Vector{UUID},
    allocations::Dict{UUID, T},
    clearing_price::T
) where T
    payments = Dict{UUID, T}()
    
    # Winner pays their bid price at termination
    for winner_id in winners
        quantity = get(allocations, winner_id, one(T))
        payments[winner_id] = clearing_price * quantity
    end
    
    return payments
end

function simulateCandleProcess(
    mechanism::CandleAuction{T},
    bids::Vector{Bid{T}}
) where T
    # Sort bids by timestamp to process in order
    sorted_bids = sort(bids, by=b -> b.timestamp)
    
    for bid in sorted_bids
        # Check termination before each bid
        if check_random_termination(mechanism)
            break
        end
        
        # Process bid if valid
        if bid.amount > mechanism.current_price
            mechanism.current_price = bid.amount
            mechanism.current_leader = bid.bidder_id
            push!(mechanism.bid_history, (bid.bidder_id, bid.amount, bid.timestamp))
        end
    end
    
    # Ensure termination is checked at end
    if !mechanism.is_terminated
        check_random_termination(mechanism)
    end
end

function calculateTerminationStatistics(mechanism::CandleAuction{T}) where T
    if isnothing(mechanism.termination_time)
        return Dict{Symbol, Any}()
    end
    
    duration = (mechanism.termination_time - mechanism.start_time).value / 1000.0
    valid_bids = getValidBidsAtTermination(mechanism)
    invalid_bids = length(mechanism.bid_history) - length(valid_bids)
    
    return Dict{Symbol, Any}(
        :actual_duration => duration,
        :duration_ratio => duration / mechanism.max_duration,
        :valid_bid_count => length(valid_bids),
        :invalid_bid_count => invalid_bids,
        :terminated_early => duration < mechanism.max_duration
    )
end

function finalizeCandleAuction(state::AuctionState{T}) where T
    mechanism = CandleAuction(
        starting_price = state.reserve_price,
        min_duration = get(state.metadata, :min_duration, 60.0),
        max_duration = get(state.metadata, :max_duration, 600.0),
        termination_probability = get(state.metadata, :termination_probability, 0.01)
    )
    
    # Simulate the candle auction process
    simulateCandleProcess(mechanism, state.current_bids)
    
    clearing_price = determine_clearing_price(mechanism, state.current_bids)
    winners, allocations = allocate_winners(mechanism, state.current_bids, clearing_price)
    payments = calculate_payments(mechanism, winners, allocations, clearing_price)
    
    # Calculate statistics
    stats = calculateTerminationStatistics(mechanism)
    
    return AuctionResult{T}(
        state.auction_id,
        clearing_price,
        winners,
        allocations,
        payments,
        now(),
        merge(
            Dict{Symbol, Any}(
                :auction_type => :candle,
                :total_bids => length(state.current_bids),
                :bid_history_length => length(mechanism.bid_history),
                :is_terminated => mechanism.is_terminated
            ),
            stats
        )
    )
end