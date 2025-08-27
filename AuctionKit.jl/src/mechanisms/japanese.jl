# Japanese auction implementation
# Following A/HC/LC naming pattern

"""
    JapaneseAuction{T}

Ascending price auction where bidders must actively remain in the auction.
Once a bidder drops out, they cannot re-enter.
"""
mutable struct JapaneseAuction{T} <: OpenOutcryAuction{T}
    starting_price::T
    current_price::T
    increment::T
    tick_duration::Float64  # Seconds between price increments
    last_tick::DateTime
    active_bidders::Set{UUID}
    dropout_history::Vector{Tuple{UUID, T, DateTime}}
    auto_increment::Bool  # Automatically increment price
    min_active_bidders::Int  # Minimum bidders to continue
    
    function JapaneseAuction(;
        starting_price::T = zero(T),
        increment::T = one(T),
        tick_duration::Float64 = 10.0,
        auto_increment::Bool = true,
        min_active_bidders::Int = 2
    ) where T
        starting_price >= 0 || throw(ArgumentError("Starting price must be non-negative"))
        increment > 0 || throw(ArgumentError("Increment must be positive"))
        tick_duration > 0 || throw(ArgumentError("Tick duration must be positive"))
        min_active_bidders >= 1 || throw(ArgumentError("Minimum active bidders must be at least 1"))
        
        new{T}(
            starting_price,
            starting_price,
            increment,
            tick_duration,
            now(),
            Set{UUID}(),
            Vector{Tuple{UUID, T, DateTime}}(),
            auto_increment,
            min_active_bidders
        )
    end
end

function register_active_bidder(mechanism::JapaneseAuction{T}, bidder_id::UUID) where T
    # Bidder can only register at the start or if price hasn't increased
    if mechanism.current_price > mechanism.starting_price
        return false, "Cannot join after auction has started"
    end
    
    push!(mechanism.active_bidders, bidder_id)
    return true, "Bidder registered successfully"
end

function processBidderDropout(mechanism::JapaneseAuction{T}, bidder_id::UUID) where T
    if bidder_id ∉ mechanism.active_bidders
        return false, "Bidder not active in auction"
    end
    
    # Record dropout
    delete!(mechanism.active_bidders, bidder_id)
    push!(mechanism.dropout_history, (bidder_id, mechanism.current_price, now()))
    
    return true, "Bidder dropped out at price $(mechanism.current_price)"
end

function incrementAuctionPrice(mechanism::JapaneseAuction{T}) where T
    if !mechanism.auto_increment
        return mechanism.current_price
    end
    
    current_time = now()
    elapsed_seconds = (current_time - mechanism.last_tick).value / 1000.0
    
    if elapsed_seconds >= mechanism.tick_duration
        # Check if we have enough active bidders to continue
        if length(mechanism.active_bidders) >= mechanism.min_active_bidders
            mechanism.current_price += mechanism.increment
            mechanism.last_tick = current_time
            
            # Notify active bidders of price increase (in real system)
            # This would trigger dropout decisions
        end
    end
    
    return mechanism.current_price
end

function shouldCloseJapanese(mechanism::JapaneseAuction{T}) where T
    # Close when fewer than minimum bidders remain active
    return length(mechanism.active_bidders) < mechanism.min_active_bidders
end

function determine_clearing_price(mechanism::JapaneseAuction{T},
    bids::Vector{Bid{T}}) where T
    # In Japanese auction, clearing price is where last bidder(s) remain
    if length(mechanism.active_bidders) == 1
        # Single winner at current price
        return mechanism.current_price
    elseif length(mechanism.active_bidders) == 0
        # All dropped out - use last dropout price
        if !isempty(mechanism.dropout_history)
            return mechanism.dropout_history[end][2]
        else
            return mechanism.starting_price
        end
    else
        # Multiple active bidders remain - auction continues
        return mechanism.current_price
    end
end

function allocate_winners(
    mechanism::JapaneseAuction{T},
    bids::Vector{Bid{T}},
    clearing_price::T
) where T
    winners = collect(mechanism.active_bidders)
    allocations = Dict{UUID, T}()
    
    if length(winners) == 1
        # Single winner gets full allocation
        allocations[winners[1]] = one(T)
    elseif length(winners) > 1
        # Multiple winners share equally (or could use tie-breaking)
        share = one(T) / T(length(winners))
        for winner_id in winners
            allocations[winner_id] = share
        end
    end
    
    return winners, allocations
end

function calculate_payments(
    mechanism::JapaneseAuction{T},
    winners::Vector{UUID},
    allocations::Dict{UUID, T},
    clearing_price::T
) where T
    payments = Dict{UUID, T}()
    
    # Winners pay the price at which they won
    for winner_id in winners
        quantity = get(allocations, winner_id, one(T))
        payments[winner_id] = clearing_price * quantity
    end
    
    return payments
end

function simulateJapaneseProcess(
    mechanism::JapaneseAuction{T},
    bids::Vector{Bid{T}}
) where T
    # Register all bidders initially
    for bid in bids
        register_active_bidder(mechanism, bid.bidder_id)
    end
    
    # Sort bids by amount to simulate dropout behavior
    sorted_bids = sortBidsByPrice(bids, rev=false)  # Ascending order
    
    # Simulate price increments and dropouts
    bid_index = 1
    while !shouldCloseJapanese(mechanism) && bid_index <= length(sorted_bids)
        # Increment price
        new_price = mechanism.current_price + mechanism.increment
        
        # Process dropouts at this price level
        while bid_index <= length(sorted_bids) && sorted_bids[bid_index].amount < new_price
            processBidderDropout(mechanism, sorted_bids[bid_index].bidder_id)
            bid_index += 1
        end
        
        mechanism.current_price = new_price
        mechanism.last_tick = now()
        
        # Safety check to prevent infinite loop
        if mechanism.current_price > T(10000)
            break
        end
    end
end

function finalizeJapaneseAuction(state::AuctionState{T}) where T
    mechanism = JapaneseAuction(
        starting_price = state.reserve_price,
        increment = state.increment,
        min_active_bidders = get(state.metadata, :min_active_bidders, 2)
    )
    
    # Simulate the Japanese auction process
    simulateJapaneseProcess(mechanism, state.current_bids)
    
    clearing_price = determine_clearing_price(mechanism, state.current_bids)
    winners, allocations = allocate_winners(mechanism, state.current_bids, clearing_price)
    payments = calculate_payments(mechanism, winners, allocations, clearing_price)
    
    # Calculate metrics
    total_dropouts = length(mechanism.dropout_history)
    avg_dropout_price = if !isempty(mechanism.dropout_history)
        sum(d[2] for d in mechanism.dropout_history) / length(mechanism.dropout_history)
    else
        zero(T)
    end
    
    return AuctionResult{T}(
        state.auction_id,
        clearing_price,
        winners,
        allocations,
        payments,
        now(),
        Dict{Symbol, Any}(
            :auction_type => :japanese,
            :total_bids => length(state.current_bids),
            :final_active_bidders => length(mechanism.active_bidders),
            :total_dropouts => total_dropouts,
            :avg_dropout_price => avg_dropout_price,
            :price_levels => Int((clearing_price - mechanism.starting_price) / mechanism.increment)
        )
    )
end