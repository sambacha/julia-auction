# Unified auction interface
# Following A/HC/LC naming pattern

using UUIDs
using Dates
using Statistics: mean, var

"""
    UnifiedAuctionConfig

Configuration for unified auction interface supporting all auction types.
"""
struct UnifiedAuctionConfig{T}
    auction_type::Symbol
    reserve_price::T
    max_quantity::Int
    tie_breaking::Symbol
    metadata::Dict{Symbol, Any}
    
    function UnifiedAuctionConfig(;
        auction_type::Symbol = :first_price,
        reserve_price::T = zero(T),
        max_quantity::Int = 1,
        tie_breaking::Symbol = :random,
        metadata::Dict{Symbol, Any} = Dict{Symbol, Any}()
    ) where T
        supported_types = [
            :first_price, :second_price, :dutch, :english,
            :combinatorial, :double, :all_pay, :japanese,
            :candle, :penny, :augmented_uniform
        ]
        
        auction_type in supported_types ||
            throw(ArgumentError("Unsupported auction type: $auction_type"))
        
        reserve_price >= 0 || throw(ArgumentError("Reserve price must be non-negative"))
        max_quantity >= 1 || throw(ArgumentError("Max quantity must be at least 1"))
        
        new{T}(auction_type, reserve_price, max_quantity, tie_breaking, metadata)
    end
end

"""
    StandardizedResult{T}

Standardized result structure for all auction types.
"""
struct StandardizedResult{T}
    auction_type::Symbol
    winners::Vector{UUID}
    clearing_price::T
    allocations::Dict{UUID, T}
    payments::Dict{UUID, T}
    revenue::T
    efficiency::Float64
    metadata::Dict{Symbol, Any}
    timestamp::DateTime
    
    function StandardizedResult(result::AuctionResult{T}, auction_type::Symbol) where T
        revenue = sum(values(result.payments))
        efficiency = get(result.metadata, :efficiency, 1.0)
        
        new{T}(
            auction_type,
            result.winners,
            result.clearing_price,
            result.allocations,
            result.payments,
            revenue,
            efficiency,
            result.metadata,
            result.timestamp
        )
    end
end

"""
    AuctionFactory{T}

Factory for creating auction mechanisms based on configuration.
"""
struct AuctionFactory{T}
    function create(config::UnifiedAuctionConfig{T}) where T
        if config.auction_type == :first_price
            return FirstPriceAuction{T}(
                config.reserve_price,
                config.max_quantity,
                config.tie_breaking
            )
        elseif config.auction_type == :second_price
            return VickreyAuction{T}(
                config.reserve_price,
                config.max_quantity,
                config.tie_breaking
            )
        elseif config.auction_type == :dutch
            return DutchAuction(
                starting_price = config.reserve_price * T(2),
                decrement = get(config.metadata, :decrement, T(1)),
                floor_price = config.reserve_price,
                max_quantity = config.max_quantity
            )
        elseif config.auction_type == :english
            return EnglishAuction(
                starting_price = config.reserve_price,
                increment = get(config.metadata, :increment, T(1))
            )
        elseif config.auction_type == :combinatorial
            return CombinatorialAuction(
                items = get(config.metadata, :items, Symbol[:item1]),
                reserve_prices = get(config.metadata, :reserve_prices, Dict{Symbol, T}())
            )
        elseif config.auction_type == :double
            return SealedBidDoubleAuction(
                max_quantity = config.max_quantity,
                price_rule = get(config.metadata, :price_rule, :uniform)
            )
        elseif config.auction_type == :all_pay
            return AllPayAuction(
                reserve_price = config.reserve_price,
                prize_structure = get(config.metadata, :prize_structure, :winner_takes_all)
            )
        elseif config.auction_type == :japanese
            return JapaneseAuction(
                starting_price = config.reserve_price,
                increment = get(config.metadata, :increment, T(1))
            )
        elseif config.auction_type == :candle
            return CandleAuction(
                starting_price = config.reserve_price
            )
        elseif config.auction_type == :penny
            return PennyAuction(
                starting_price = config.reserve_price,
                bid_increment = get(config.metadata, :bid_increment, T(0.01))
            )
        else
            throw(ArgumentError("Unknown auction type: $(config.auction_type)"))
        end
    end
end

"""
    run_unified_auction(config, bids)

Run any auction type with unified interface.
"""
function run_unified_auction(
    config::UnifiedAuctionConfig{T},
    bids::Vector{Bid{T}}
) where T
    # Create auction state based on actual AuctionState structure
    state = AuctionState{T}(
        uuid4(),  # auction_id
        config.auction_type,  # auction_type
        :active,  # status
        bids,  # current_bids
        Dict{UUID, Bidder{T}}(),  # participants
        now(),  # start_time
        now() + Hour(1),  # end_time
        ReentrantLock(),  # mutex
        config.reserve_price,  # reserve_price
        get(config.metadata, :increment, T(1)),  # increment
        config.auction_type,  # clearing_rule
        config.tie_breaking,  # tie_breaking
        config.max_quantity,  # max_quantity
        nothing  # result
    )
    
    # Route to appropriate finalizer based on type
    result = if config.auction_type == :first_price
        finalizeFirstPriceAuction(state)
    elseif config.auction_type == :second_price
        finalizeVickreyAuction(state)
    elseif config.auction_type == :dutch
        finalizeDutchAuction(state)
    elseif config.auction_type == :english
        finalizeEnglishAuction(state)
    elseif config.auction_type == :combinatorial
        finalizeCombinatorialAuction(state)
    elseif config.auction_type == :double
        finalizeDoubleAuction(state)
    elseif config.auction_type == :all_pay
        finalizeAllPayAuction(state)
    elseif config.auction_type == :japanese
        finalizeJapaneseAuction(state)
    elseif config.auction_type == :candle
        finalizeCandleAuction(state)
    elseif config.auction_type == :penny
        finalizePennyAuction(state)
    else
        throw(ArgumentError("Unsupported auction type: $(config.auction_type)"))
    end
    
    return StandardizedResult(result, config.auction_type)
end

"""
    compare_auction_types(bids, auction_types)

Compare performance of different auction types on same bid set.
"""
function compare_auction_types(
    bids::Vector{Bid{T}},
    auction_types::Vector{Symbol} = [:first_price, :second_price, :dutch, :english];
    reserve_price::T = zero(T)
) where T
    results = Dict{Symbol, StandardizedResult{T}}()
    
    for auction_type in auction_types
        config = UnifiedAuctionConfig(
            auction_type = auction_type,
            reserve_price = reserve_price
        )
        
        try
            result = run_unified_auction(config, bids)
            results[auction_type] = result
        catch e
            @warn "Failed to run $auction_type auction: $e"
        end
    end
    
    return results
end

"""
    analyze_auction_performance(result)

Analyze performance metrics for auction result.
"""
function analyze_auction_performance(result::StandardizedResult{T}) where T
    metrics = Dict{Symbol, Any}()
    
    # Revenue metrics
    metrics[:total_revenue] = result.revenue
    metrics[:clearing_price] = result.clearing_price
    metrics[:num_winners] = length(result.winners)
    
    # Allocation metrics
    metrics[:total_allocated] = sum(abs.(values(result.allocations)))
    metrics[:allocation_concentration] = if !isempty(result.allocations)
        max_alloc = maximum(abs.(values(result.allocations)))
        total_alloc = sum(abs.(values(result.allocations)))
        max_alloc / total_alloc
    else
        0.0
    end
    
    # Payment metrics
    metrics[:avg_payment] = if !isempty(result.payments)
        mean(abs.(values(result.payments)))
    else
        zero(T)
    end
    
    metrics[:payment_variance] = if length(result.payments) > 1
        var(abs.(values(result.payments)))
    else
        zero(T)
    end
    
    # Efficiency
    metrics[:efficiency] = result.efficiency
    
    return metrics
end

"""
    recommend_auction_type(bid_characteristics)

Recommend optimal auction type based on bid characteristics.
"""
function recommend_auction_type(
    bid_characteristics::Dict{Symbol, Any}
) ::Symbol
    num_bidders = get(bid_characteristics, :num_bidders, 0)
    bid_variance = get(bid_characteristics, :bid_variance, 0.0)
    time_sensitive = get(bid_characteristics, :time_sensitive, false)
    multi_unit = get(bid_characteristics, :multi_unit, false)
    bundle_bids = get(bid_characteristics, :bundle_bids, false)
    two_sided = get(bid_characteristics, :two_sided, false)
    
    # Decision tree for auction type selection
    if two_sided
        return :double
    elseif bundle_bids
        return :combinatorial
    elseif time_sensitive && num_bidders > 10
        return :candle
    elseif multi_unit && bid_variance > 0.5
        return :augmented_uniform
    elseif num_bidders < 5
        return :english
    elseif bid_variance < 0.2
        return :second_price
    else
        return :first_price
    end
end

# Export all auction types and utilities
export UnifiedAuctionConfig, StandardizedResult, AuctionFactory
export run_unified_auction, compare_auction_types
export analyze_auction_performance, recommend_auction_type