# Vickrey (second-price) auction implementation
# Following A/HC/LC naming pattern

"""
    VickreyAuction{T}

Second-price sealed-bid auction where winners pay the second-highest bid.
Also known as Vickrey auction. Truthful bidding is a dominant strategy.
"""
struct VickreyAuction{T} <: SealedBidAuction{T}
    reserve_price::T
    tie_breaking::Symbol
    
    function VickreyAuction(;
        reserve_price::T = zero(T),
        tie_breaking::Symbol = :random
    ) where T
        reserve_price >= 0 || throw(ArgumentError("Reserve price must be non-negative"))
        tie_breaking in [:random, :first_come, :proportional, :highest_id] ||
            throw(ArgumentError("Invalid tie-breaking rule: $tie_breaking"))
        
        new{T}(reserve_price, tie_breaking)
    end
end

# A/HC/LC: determine + Clearing + Price
function determineClearingPrice(mechanism::VickreyAuction{T}, bids::Vector{Bid{T}}) where T
    valid_bids = filterValidBids(bids, mechanism.reserve_price)
    
    if isempty(valid_bids)
        return mechanism.reserve_price
    end
    
    sorted_bids = sortBidsByPrice(valid_bids, rev=true)
    
    # In Vickrey, the clearing price is the second-highest bid
    if length(sorted_bids) >= 2
        return sorted_bids[2].amount
    else
        # Only one valid bid, use reserve price
        return mechanism.reserve_price
    end
end

# A/HC/LC: allocate + Winners
function allocateWinners(
    mechanism::VickreyAuction{T}, 
    bids::Vector{Bid{T}}, 
    clearing_price::T
) where T
    valid_bids = filterValidBids(bids, mechanism.reserve_price)
    
    if isempty(valid_bids)
        return UUID[], Dict{UUID, T}()
    end
    
    sorted_bids = sortBidsByPrice(valid_bids, rev=true)
    
    winners = UUID[]
    allocations = Dict{UUID, T}()
    
    # Find all bids at the highest price (potential ties)
    highest_price = sorted_bids[1].amount
    tied_bids = filter(b -> b.amount == highest_price, sorted_bids)
    
    # Resolve ties
    winning_bids = resolveTiesWithRule(tied_bids, mechanism.tie_breaking)
    
    if !isempty(winning_bids)
        winner_bid = winning_bids[1]
        push!(winners, winner_bid.bidder_id)
        allocations[winner_bid.bidder_id] = T(winner_bid.quantity)
    end
    
    return winners, allocations
end

# A/HC/LC: calculate + Payments
function calculatePayments(
    mechanism::VickreyAuction{T},
    winners::Vector{UUID},
    allocations::Dict{UUID, T},
    clearing_price::T
) where T
    payments = Dict{UUID, T}()
    
    # In Vickrey, winners pay the second-highest bid (clearing price)
    for winner_id in winners
        quantity = get(allocations, winner_id, one(T))
        payments[winner_id] = clearing_price * quantity
    end
    
    return payments
end

# A/HC/LC: finalize + Vickrey + Auction
function finalizeVickreyAuction(state::AuctionState{T}) where T
    mechanism = VickreyAuction{T}(
        reserve_price = state.reserve_price,
        tie_breaking = state.tie_breaking
    )
    
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
            :auction_type => :vickrey,
            :total_bids => length(state.current_bids),
            :reserve_met => clearing_price >= state.reserve_price,
            :truthful => true  # Vickrey is incentive compatible
        )
    )
end