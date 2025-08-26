# English auction implementation
# Following A/HC/LC naming pattern

"""
    EnglishAuction{T}

Ascending price open outcry auction where bidders progressively raise their bids.
"""
mutable struct EnglishAuction{T} <: OpenOutcryAuction{T}
    starting_price::T
    current_price::T
    increment::T
    current_leader::Union{Nothing, UUID}
    bid_history::Vector{Tuple{UUID, T, DateTime}}
    inactive_duration::Float64  # Seconds without new bids before closing
    last_bid_time::DateTime
    
    function EnglishAuction(;
        starting_price::T = zero(T),
        increment::T = one(T),
        inactive_duration::Float64 = 300.0  # 5 minutes default
    ) where T
        starting_price >= 0 || throw(ArgumentError("Starting price must be non-negative"))
        increment > 0 || throw(ArgumentError("Increment must be positive"))
        inactive_duration > 0 || throw(ArgumentError("Inactive duration must be positive"))
        
        new{T}(
            starting_price,
            starting_price,
            increment,
            nothing,
            Vector{Tuple{UUID, T, DateTime}}(),
            inactive_duration,
            now()
        )
    end
end

# A/HC/LC: validate + New + Bid
function validateNewBid(mechanism::EnglishAuction{T}, bid::Bid{T}) where T
    # Bid must be at least current price plus increment
    min_valid_bid = mechanism.current_price + mechanism.increment
    
    if bid.amount < min_valid_bid
        return false, "Bid must be at least $(min_valid_bid)"
    end
    
    # Check if auction should close due to inactivity
    elapsed_seconds = (now() - mechanism.last_bid_time).value / 1000.0
    if elapsed_seconds > mechanism.inactive_duration && !isnothing(mechanism.current_leader)
        return false, "Auction has closed due to inactivity"
    end
    
    return true, ""
end

# A/HC/LC: accept + English + Bid
function acceptEnglishBid(mechanism::EnglishAuction{T}, bid::Bid{T}) where T
    valid, msg = validateNewBid(mechanism, bid)
    if !valid
        return false, msg
    end
    
    # Update auction state
    mechanism.current_price = bid.amount
    mechanism.current_leader = bid.bidder_id
    mechanism.last_bid_time = now()
    
    # Record bid in history
    push!(mechanism.bid_history, (bid.bidder_id, bid.amount, bid.timestamp))
    
    return true, "Bid accepted as new leader"
end

# A/HC/LC: should + Close + English
function shouldCloseEnglish(mechanism::EnglishAuction{T}) where T
    if isnothing(mechanism.current_leader)
        return false
    end
    
    elapsed_seconds = (now() - mechanism.last_bid_time).value / 1000.0
    return elapsed_seconds > mechanism.inactive_duration
end

# A/HC/LC: determine + Clearing + Price
function determineClearingPrice(mechanism::EnglishAuction{T}, bids::Vector{Bid{T}}) where T
    # In English auction, clearing price is the final highest bid
    if isnothing(mechanism.current_leader)
        return mechanism.starting_price
    end
    return mechanism.current_price
end

# A/HC/LC: allocate + Winners
function allocateWinners(
    mechanism::EnglishAuction{T}, 
    bids::Vector{Bid{T}}, 
    clearing_price::T
) where T
    if isnothing(mechanism.current_leader)
        return UUID[], Dict{UUID, T}()
    end
    
    winners = [mechanism.current_leader]
    allocations = Dict{UUID, T}(mechanism.current_leader => one(T))
    
    return winners, allocations
end

# A/HC/LC: calculate + Payments
function calculatePayments(
    mechanism::EnglishAuction{T},
    winners::Vector{UUID},
    allocations::Dict{UUID, T},
    clearing_price::T
) where T
    payments = Dict{UUID, T}()
    
    # In English auction, winner pays the final bid price
    for winner_id in winners
        quantity = get(allocations, winner_id, one(T))
        payments[winner_id] = clearing_price * quantity
    end
    
    return payments
end

# A/HC/LC: finalize + English + Auction
function finalizeEnglishAuction(state::AuctionState{T}) where T
    mechanism = EnglishAuction(
        starting_price = state.reserve_price,
        increment = state.increment
    )
    
    # Process all bids sequentially (they should have been processed in real-time)
    sorted_bids = sort(state.current_bids, by=b -> b.timestamp)
    
    for bid in sorted_bids
        acceptEnglishBid(mechanism, bid)
    end
    
    clearing_price = determineClearingPrice(mechanism, state.current_bids)
    winners, allocations = allocateWinners(mechanism, state.current_bids, clearing_price)
    payments = calculatePayments(mechanism, winners, allocations, clearing_price)
    
    return AuctionResult{T}(
        state.auction_id,
        clearing_price,
        winners,
        allocations,
        payments,
        now(),
        Dict{Symbol, Any}(
            :auction_type => :english,
            :total_bids => length(state.current_bids),
            :bid_history_length => length(mechanism.bid_history),
            :final_leader => mechanism.current_leader
        )
    )
end