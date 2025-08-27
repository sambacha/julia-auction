# Augmented Uniform Price Auction mechanism for AuctionKit
# Integrates with existing auction infrastructure

export AugmentedUniformPriceAuction, finalize_augmented_uniform_auction

using ..AugmentedUniformPriceAuction: ElasticSupplySchedule, AugmentedTieBreaking
"""
    AugmentedUniformPriceAuction{T} <: SealedBidAuction{T}

Augmented uniform price auction with elastic supply and advanced tie-breaking.
"""
struct AugmentedUniformPriceAuction{T} <: SealedBidAuction{T}
    reserve_price::T
    supply_schedule::ElasticSupplySchedule
    tie_breaking::AugmentedTieBreaking
    max_winners::Int
    allow_partial_fills::Bool
end

function finalize_augmented_uniform_auction(
    auction::AugmentedUniformPriceAuction{T},
    bids::Vector{Bid}
) where T
    # Convert AuctionKit bids to augmented auction format
    augmented_bids = [
        AugmentedUniformPriceAuction.Bid(
            b.bidder.id,
            b.quantity,
            b.price,
            timestamp=time(),
            is_marginal=false
        ) for b in bids
    ]
    
    # Create config
    config = AugmentedUniformPriceAuction.AuctionConfig(
        supply_schedule=auction.supply_schedule,
        tie_breaking=auction.tie_breaking,
        reserve_price=auction.reserve_price,
        allow_partial_fills=auction.allow_partial_fills
    )
    
    # Run augmented auction
    result = AugmentedUniformPriceAuction.run_auction(augmented_bids, config)
    
    # Convert back to AuctionKit result format
    winners = Bidder[]
    for alloc in result.allocations
        winner = Bidder(alloc.bid.bidder_id, alloc.allocated_quantity)
        push!(winners, winner)
    end
    
    return AuctionResult(
        auction,
        winners,
        result.clearing_price,
        bids,
        Dict(
            "total_revenue" => result.total_revenue,
            "efficiency" => result.efficiency_score,
            "bid_shading" => result.bid_shading_estimate,
            "tie_breaks" => result.num_tie_breaks
        )
    )
end