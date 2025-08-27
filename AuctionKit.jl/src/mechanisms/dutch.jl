# Dutch auction implementation
# Following A/HC/LC naming pattern

"""
    DutchAuction{T}

Descending price auction where price starts high and decreases until demand meets supply.
"""
mutable struct DutchAuction{T} <: OpenOutcryAuction{T}
    starting_price::T
    current_price::T
    decrement::T
    floor_price::T
    tick_duration::Float64  # Seconds between price decrements
    last_tick::DateTime
    max_quantity::Int
    
    function DutchAuction(;
        starting_price::T,
        decrement::T,
        floor_price::T = zero(T),
        tick_duration::Float64 = 60.0,
        max_quantity::Int = 1
    ) where T
        starting_price > floor_price || 
            throw(ArgumentError("Starting price must be greater than floor price"))
        decrement > 0 || throw(ArgumentError("Decrement must be positive"))
        tick_duration > 0 || throw(ArgumentError("Tick duration must be positive"))
        max_quantity >= 1 || throw(ArgumentError("Max quantity must be at least 1"))
        
        new{T}(
            starting_price,
            starting_price,  # Current price starts at starting price
            decrement,
            floor_price,
            tick_duration,
            now(),
            max_quantity
        )
    end
end

function updateCurrentPrice(mechanism::DutchAuction{T}) where T
    current_time = now()
    elapsed_seconds = (current_time - mechanism.last_tick).value / 1000.0
    
    if elapsed_seconds >= mechanism.tick_duration
        ticks_passed = floor(Int, elapsed_seconds / mechanism.tick_duration)
        price_decrease = mechanism.decrement * ticks_passed
        
        mechanism.current_price = max(
            mechanism.floor_price,
            mechanism.current_price - price_decrease
        )
        mechanism.last_tick = current_time
    end
    
    return mechanism.current_price
end

function determine_clearing_price(mechanism::DutchAuction{T}, bids::Vector{Bid{T}}) where T
    # Update price based on time
    current_price = updateCurrentPrice(mechanism)
    
    # In Dutch auction, clearing price is the current price when demand meets supply
    valid_bids = filter(b -> b.amount >= current_price, bids)
    total_quantity = sum(b.quantity for b in valid_bids)
    
    if total_quantity >= mechanism.max_quantity
        return current_price
    else
        # Not enough demand at current price
        return mechanism.floor_price
    end
end

function allocate_winners(
    mechanism::DutchAuction{T}, 
    bids::Vector{Bid{T}}, 
    clearing_price::T
) where T
    # Get bids willing to pay at least the clearing price
    valid_bids = filter(b -> b.amount >= clearing_price, bids)
    
    if isempty(valid_bids)
        return UUID[], Dict{UUID, T}()
    end
    
    # Sort by bid amount (highest first) then by timestamp (earliest first)
    sorted_bids = sort(valid_bids, by=b -> (-b.amount, b.timestamp))
    
    winners = UUID[]
    allocations = Dict{UUID, T}()
    remaining_quantity = mechanism.max_quantity
    
    for bid in sorted_bids
        if remaining_quantity <= 0
            break
        end
        
        allocated = min(bid.quantity, remaining_quantity)
        if allocated > 0
            push!(winners, bid.bidder_id)
            allocations[bid.bidder_id] = T(allocated)
            remaining_quantity -= allocated
        end
    end
    
    return winners, allocations
end

function calculate_payments(
    mechanism::DutchAuction{T},
    winners::Vector{UUID},
    allocations::Dict{UUID, T},
    clearing_price::T
) where T
    payments = Dict{UUID, T}()
    
    # In Dutch auction, all winners pay the clearing price
    for winner_id in winners
        quantity = get(allocations, winner_id, zero(T))
        payments[winner_id] = clearing_price * quantity
    end
    
    return payments
end

function finalizeDutchAuction(state::AuctionState{T}) where T
    mechanism = DutchAuction(
        starting_price = state.reserve_price * T(2),  # Start at 2x reserve
        decrement = state.increment,
        floor_price = state.reserve_price,
        max_quantity = state.max_quantity
    )
    
    clearing_price = determine_clearing_price(mechanism, state.current_bids)
    winners, allocations = allocate_winners(mechanism, state.current_bids, clearing_price)
    payments = calculate_payments(mechanism, winners, allocations, clearing_price)
    
    return AuctionResult{T}(
        state.auction_id,
        clearing_price,
        winners,
        allocations,
        payments,
        now(),
        Dict{Symbol, Any}(
            :auction_type => :dutch,
            :total_bids => length(state.current_bids),
            :final_price => clearing_price,
            :price_ticks => floor(Int, (mechanism.starting_price - clearing_price) / mechanism.decrement)
        )
    )
end