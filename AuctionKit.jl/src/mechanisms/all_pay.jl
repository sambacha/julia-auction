# All-pay auction implementation
# Following A/HC/LC naming pattern

"""
    AllPayAuction{T}

Auction where all bidders pay their bid amount regardless of winning.
Common in contests, lobbying, and R&D competitions.
"""
struct AllPayAuction{T} <: SealedBidAuction{T}
    reserve_price::T
    prize_structure::Symbol  # :winner_takes_all, :proportional, :top_k
    num_prizes::Int
    prize_distribution::Vector{T}  # Distribution of prizes for top_k
    refund_rate::T  # Partial refund rate for losers (0 = pure all-pay)
    
    function AllPayAuction(;
        reserve_price::T = zero(T),
        prize_structure::Symbol = :winner_takes_all,
        num_prizes::Int = 1,
        prize_distribution::Vector{T} = T[one(T)],
        refund_rate::T = zero(T)
    ) where T
        reserve_price >= 0 || throw(ArgumentError("Reserve price must be non-negative"))
        prize_structure in [:winner_takes_all, :proportional, :top_k] ||
            throw(ArgumentError("Invalid prize structure"))
        num_prizes >= 1 || throw(ArgumentError("Number of prizes must be at least 1"))
        0 <= refund_rate <= 1 || throw(ArgumentError("Refund rate must be between 0 and 1"))
        
        # Validate prize distribution
        if prize_structure == :top_k && length(prize_distribution) != num_prizes
            throw(ArgumentError("Prize distribution must match number of prizes"))
        end
        
        if !isempty(prize_distribution) && sum(prize_distribution) != one(T)
            # Normalize prize distribution
            prize_distribution = prize_distribution ./ sum(prize_distribution)
        end
        
        new{T}(reserve_price, prize_structure, num_prizes, prize_distribution, refund_rate)
    end
end

function determine_clearing_price(mechanism::AllPayAuction{T}, bids::Vector{Bid{T}}) where T
    # In all-pay auctions, there's no traditional clearing price
    # Return the highest bid as a reference price
    valid_bids = filterValidBids(bids, mechanism.reserve_price)
    
    if isempty(valid_bids)
        return mechanism.reserve_price
    end
    
    sorted_bids = sortBidsByPrice(valid_bids, rev=true)
    return sorted_bids[1].amount
end

function allocate_winners(
    mechanism::AllPayAuction{T},
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
    
    if mechanism.prize_structure == :winner_takes_all
        # Only top bidder wins
        winner_bid = sorted_bids[1]
        
        # Handle ties at the top
        top_amount = winner_bid.amount
        tied_bids = filter(b -> b.amount == top_amount, sorted_bids)
        
        if length(tied_bids) > 1
            tied_bids = resolveTiesWithRule(tied_bids, :random)
        end
        
        push!(winners, tied_bids[1].bidder_id)
        allocations[tied_bids[1].bidder_id] = one(T)
        
    elseif mechanism.prize_structure == :proportional
        # All bidders win proportionally to their bids
        total_bids = sum(b.amount for b in valid_bids)
        
        for bid in valid_bids
            push!(winners, bid.bidder_id)
            allocations[bid.bidder_id] = T(bid.amount / total_bids)
        end
        
    elseif mechanism.prize_structure == :top_k
        # Top k bidders win according to prize distribution
        num_winners = min(mechanism.num_prizes, length(sorted_bids))
        
        for i in 1:num_winners
            push!(winners, sorted_bids[i].bidder_id)
            prize_share = i <= length(mechanism.prize_distribution) ? 
                         mechanism.prize_distribution[i] : zero(T)
            allocations[sorted_bids[i].bidder_id] = prize_share
        end
    end
    
    return winners, allocations
end

function calculate_payments(
    mechanism::AllPayAuction{T},
    winners::Vector{UUID},
    allocations::Dict{UUID, T},
    clearing_price::T
) where T
    # In all-pay auction, everyone pays their bid
    # This requires access to original bids
    payments = Dict{UUID, T}()
    
    # Note: This is a simplified implementation
    # In practice, we'd need to track all bidders and their bids
    for (bidder_id, allocation) in allocations
        # Winners pay their full bid
        payments[bidder_id] = clearing_price * allocation
    end
    
    # Losers also pay (with potential refund)
    # This would require tracking all participants
    
    return payments
end

function calculateAllPayPayments(
    mechanism::AllPayAuction{T},
    bids::Vector{Bid{T}},
    winners::Vector{UUID}
) where T
    payments = Dict{UUID, T}()
    winner_set = Set(winners)
    
    for bid in bids
        if bid.bidder_id in winner_set
            # Winners pay full bid
            payments[bid.bidder_id] = bid.amount
        else
            # Losers pay with potential partial refund
            payment = bid.amount * (one(T) - mechanism.refund_rate)
            if payment > zero(T)
                payments[bid.bidder_id] = payment
            end
        end
    end
    
    return payments
end

function calculateExpectedRevenue(mechanism::AllPayAuction{T}, bids::Vector{Bid{T}}) where T
    # In all-pay auction, revenue is sum of all bids (minus refunds)
    total_revenue = zero(T)
    
    winners, allocations = allocate_winners(mechanism, bids, determine_clearing_price(mechanism, bids))
    winner_set = Set(winners)
    
    for bid in bids
        if bid.bidder_id in winner_set
            total_revenue += bid.amount
        else
            # Losers pay with refund consideration
            total_revenue += bid.amount * (one(T) - mechanism.refund_rate)
        end
    end
    
    return total_revenue
end

function finalizeAllPayAuction(state::AuctionState{T}) where T
    mechanism = AllPayAuction(
        reserve_price = state.reserve_price,
        prize_structure = get(state.metadata, :prize_structure, :winner_takes_all),
        num_prizes = get(state.metadata, :num_prizes, 1),
        refund_rate = get(state.metadata, :refund_rate, zero(T))
    )
    
    clearing_price = determine_clearing_price(mechanism, state.current_bids)
    winners, allocations = allocate_winners(mechanism, state.current_bids, clearing_price)
    
    # Calculate all-pay specific payments
    payments = calculateAllPayPayments(mechanism, state.current_bids, winners)
    
    # Calculate total revenue (everyone pays)
    total_revenue = sum(values(payments))
    
    # Calculate participation metrics
    num_participants = length(state.current_bids)
    num_winners = length(winners)
    win_rate = num_participants > 0 ? num_winners / num_participants : 0.0
    
    return AuctionResult{T}(
        state.auction_id,
        clearing_price,
        winners,
        allocations,
        payments,
        now(),
        Dict{Symbol, Any}(
            :auction_type => :all_pay,
            :total_bids => length(state.current_bids),
            :num_winners => num_winners,
            :total_revenue => total_revenue,
            :prize_structure => mechanism.prize_structure,
            :refund_rate => mechanism.refund_rate,
            :win_rate => win_rate
        )
    )
end