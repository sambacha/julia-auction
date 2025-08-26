# Abstract types and interfaces for auction mechanisms
# Following A/HC/LC naming pattern

"""
    AuctionMechanism{T}

Abstract type for auction mechanisms.
"""
abstract type AuctionMechanism{T} end

"""
    SealedBidAuction{T}

Abstract type for sealed-bid auctions.
"""
abstract type SealedBidAuction{T} <: AuctionMechanism{T} end

"""
    OpenOutcryAuction{T}

Abstract type for open outcry auctions.
"""
abstract type OpenOutcryAuction{T} <: AuctionMechanism{T} end

# Required interface functions for auction mechanisms

"""
    determineClearingPrice(mechanism, bids)

Determines the clearing price for the auction.
"""
function determineClearingPrice end

"""
    allocateWinners(mechanism, bids, clearing_price)

Determines the winning bidders and their allocations.
"""
function allocateWinners end

"""
    calculatePayments(mechanism, winners, clearing_price)

Calculates the payment for each winner.
"""
function calculatePayments end

# Utility functions

# A/HC/LC: filter + Valid + Bids
function filterValidBids(bids::Vector{Bid{T}}, reserve_price::T) where T
    return filter(bid -> bid.amount >= reserve_price, bids)
end

# A/HC/LC: sort + Bids + ByPrice
function sortBidsByPrice(bids::Vector{Bid{T}}; rev::Bool=false) where T
    return sort(bids, by=b -> b.amount, rev=rev)
end

# A/HC/LC: sort + Bids + ByTimestamp
function sortBidsByTimestamp(bids::Vector{Bid{T}}; rev::Bool=false) where T
    return sort(bids, by=b -> b.timestamp, rev=rev)
end

# A/HC/LC: resolve + Ties + WithRule
function resolveTiesWithRule(tied_bids::Vector{Bid{T}}, rule::Symbol) where T
    if isempty(tied_bids)
        return tied_bids
    end
    
    if rule == :random
        return [tied_bids[rand(1:length(tied_bids))]]
    elseif rule == :first_come
        sorted = sortBidsByTimestamp(tied_bids)
        return [sorted[1]]
    elseif rule == :proportional
        # Return all tied bids for proportional allocation
        return tied_bids
    elseif rule == :highest_id
        sorted = sort(tied_bids, by=b -> b.bidder_id)
        return [sorted[end]]
    else
        # Default to random
        return [tied_bids[rand(1:length(tied_bids))]]
    end
end

# A/HC/LC: calculate + Total + Quantity
function calculateTotalQuantity(bids::Vector{Bid{T}}) where T
    return sum(bid.quantity for bid in bids)
end

# A/HC/LC: has + Multiple + Winners
function hasMultipleWinners(mechanism::AuctionMechanism)::Bool
    return false  # Default to single winner
end