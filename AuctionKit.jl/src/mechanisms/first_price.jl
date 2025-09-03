# First-price sealed-bid auction implementation
# Following A/HC/LC naming pattern

"""
    FirstPriceAuction{T}

First-price sealed-bid auction where winners pay their bid amount.
"""
struct FirstPriceAuction{T} <: SealedBidAuction{T}
    reserve_price::T
    tie_breaking::Symbol
    max_winners::Int
    
    function FirstPriceAuction(;
        reserve_price::T = zero(T),
        tie_breaking::Symbol = :random,
        max_winners::Int = 1
    ) where T
        reserve_price >= 0 || throw(ArgumentError("Reserve price must be non-negative"))
        max_winners >= 1 || throw(ArgumentError("Must have at least one winner"))
        tie_breaking in [:random, :first_come, :proportional, :highest_id] ||
            throw(ArgumentError("Invalid tie-breaking rule: $tie_breaking"))
        
        new{T}(reserve_price, tie_breaking, max_winners)
    end
end

# A/HC/LC: determine + Clearing + Price
function determineClearingPrice(mechanism::FirstPriceAuction{T}, bids::Vector{Bid{T}}) where T
    valid_bids = filterValidBids(bids, mechanism.reserve_price)
    
    if isempty(valid_bids)
        return mechanism.reserve_price
    end
    
    sorted_bids = sortBidsByPrice(valid_bids, rev=true)
    
    # In first-price, the clearing price is the highest bid
    return sorted_bids[1].amount
end

# A/HC/LC: allocate + Winners
function allocateWinners(
    mechanism::FirstPriceAuction{T}, 
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
    
    # Handle single winner case
    if mechanism.max_winners == 1
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
    else
        # Multiple winners case
        allocated_count = 0
        current_price_level = sorted_bids[1].amount
        current_price_bids = Bid{T}[]
        
        for bid in sorted_bids
            if allocated_count >= mechanism.max_winners
                break
            end
            
            if bid.amount < current_price_level
                # Process accumulated bids at current price level
                if !isempty(current_price_bids)
                    remaining_slots = mechanism.max_winners - allocated_count
                    if length(current_price_bids) <= remaining_slots
                        # All can win
                        for b in current_price_bids
                            push!(winners, b.bidder_id)
                            allocations[b.bidder_id] = T(b.quantity)
                            allocated_count += 1
                        end
                    else
                        # Need tie-breaking
                        resolved_bids = resolveTiesWithRule(
                            current_price_bids, 
                            mechanism.tie_breaking
                        )
                        for b in resolved_bids[1:min(remaining_slots, length(resolved_bids))]
                            push!(winners, b.bidder_id)
                            allocations[b.bidder_id] = T(b.quantity)
                            allocated_count += 1
                        end
                        break
                    end
                end
                
                # Reset for new price level
                current_price_level = bid.amount
                current_price_bids = [bid]
            else
                push!(current_price_bids, bid)
            end
        end
        
        # Process final price level
        if allocated_count < mechanism.max_winners && !isempty(current_price_bids)
            remaining_slots = mechanism.max_winners - allocated_count
            if length(current_price_bids) <= remaining_slots
                for b in current_price_bids
                    push!(winners, b.bidder_id)
                    allocations[b.bidder_id] = T(b.quantity)
                end
            else
                resolved_bids = resolveTiesWithRule(
                    current_price_bids, 
                    mechanism.tie_breaking
                )
                for b in resolved_bids[1:min(remaining_slots, length(resolved_bids))]
                    push!(winners, b.bidder_id)
                    allocations[b.bidder_id] = T(b.quantity)
                end
            end
        end
    end
    
    return winners, allocations
end

# A/HC/LC: calculate + Payments
function calculatePayments(
    mechanism::FirstPriceAuction{T},
    winners::Vector{UUID},
    allocations::Dict{UUID, T},
    bids::Vector{Bid{T}}
) where T
    payments = Dict{UUID, T}()
    
    # Create bid lookup
    bid_lookup = Dict{UUID, Bid{T}}()
    for bid in bids
        bid_lookup[bid.bidder_id] = bid
    end
    
    # In first-price, winners pay their bid
    for winner_id in winners
        if haskey(bid_lookup, winner_id)
            bid = bid_lookup[winner_id]
            quantity = get(allocations, winner_id, one(T))
            payments[winner_id] = bid.amount * quantity
        end
    end
    
    return payments
end

# A/HC/LC: finalize + FirstPrice + Auction
function finalizeFirstPriceAuction(state::AuctionState{T}) where T
    mechanism = FirstPriceAuction{T}(
        reserve_price = state.reserve_price,
        tie_breaking = state.tie_breaking,
        max_winners = 1
    )
    
    clearing_price = determineClearingPrice(mechanism, state.current_bids)
    winners, allocations = allocateWinners(mechanism, state.current_bids, clearing_price)
    payments = calculatePayments(mechanism, winners, allocations, state.current_bids)
    
    return AuctionResult{T}(
        state.auction_id,
        clearing_price,
        winners,
        allocations,
        payments,
        now(),
        Dict{Symbol, Any}(
            :auction_type => :first_price,
            :total_bids => length(state.current_bids),
            :reserve_met => clearing_price >= state.reserve_price
        )
    )
end