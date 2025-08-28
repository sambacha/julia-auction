"""
AuctionSimulator.jl - Auction Mechanisms and Bidding Strategies

This module implements various auction mechanisms and bidding strategies for 
economic auction simulations. It includes first-price and second-price auctions
with support for reserve prices, multiple units, and tie-breaking rules.

Author: Julia Auction Team
"""

# Note: StatisticsValue types are already defined in AuctionSimulator.jl
# We don't need to redefine them here

#=============================================================================
    Auction Types
=============================================================================#

"""
    FirstPriceAuction

First-price sealed-bid auction where the winner pays their bid amount.
"""
struct FirstPriceAuction <: AbstractAuction
    reserve_price::Float64
    num_units::Int
    tie_breaking::Symbol  # :random, :first_come, :highest_id
    
    function FirstPriceAuction(reserve_price::Float64=0.0, num_units::Int=1, tie_breaking::Symbol=:random)
        reserve_price >= 0 || throw(ArgumentError("Reserve price must be non-negative"))
        num_units >= 1 || throw(ArgumentError("Number of units must be positive"))
        tie_breaking in [:random, :first_come, :highest_id] || throw(ArgumentError("Invalid tie-breaking rule"))
        new(reserve_price, num_units, tie_breaking)
    end
end

"""
    SecondPriceAuction

Second-price sealed-bid auction where the winner pays the second-highest bid.
"""
struct SecondPriceAuction <: AbstractAuction
    reserve_price::Float64
    num_units::Int
    tie_breaking::Symbol  # :random, :first_come, :highest_id
    
    function SecondPriceAuction(reserve_price::Float64=0.0, num_units::Int=1, tie_breaking::Symbol=:random)
        reserve_price >= 0 || throw(ArgumentError("Reserve price must be non-negative"))
        num_units >= 1 || throw(ArgumentError("Number of units must be positive"))
        tie_breaking in [:random, :first_come, :highest_id] || throw(ArgumentError("Invalid tie-breaking rule"))
        new(reserve_price, num_units, tie_breaking)
    end
end

#=============================================================================
    Bidding Strategies
=============================================================================#

"""
    TruthfulBidder

Bidder that always bids their true valuation.
"""
struct TruthfulBidder <: AbstractBiddingStrategy
    valuation::Float64
    
    function TruthfulBidder(valuation::Float64)
        valuation >= 0 || throw(ArgumentError("Valuation must be non-negative"))
        new(valuation)
    end
end

"""
    ShadedBidder

Bidder that bids below their true valuation by a shading factor.
"""
struct ShadedBidder <: AbstractBiddingStrategy
    valuation::Float64
    shading_factor::Float64
    
    function ShadedBidder(valuation::Float64, shading_factor::Float64)
        valuation >= 0 || throw(ArgumentError("Valuation must be non-negative"))
        0 <= shading_factor <= 1 || throw(ArgumentError("Shading factor must be between 0 and 1"))
        new(valuation, shading_factor)
    end
end

"""
    RandomBidder

Bidder that adds random noise to their base bid.
"""
struct RandomBidder <: AbstractBiddingStrategy
    base_strategy::AbstractBiddingStrategy
    noise_level::Float64
    
    function RandomBidder(base_strategy::AbstractBiddingStrategy, noise_level::Float64)
        noise_level >= 0 || throw(ArgumentError("Noise level must be non-negative"))
        new(base_strategy, noise_level)
    end
end

"""
    StrategicBidder

Bidder that uses game-theoretic optimal strategies.
"""
struct StrategicBidder <: AbstractBiddingStrategy
    valuation::Float64
    expected_bidders::Int
    valuation_distribution::Symbol  # :uniform, :normal
    risk_aversion::Float64
    
    function StrategicBidder(valuation::Float64, expected_bidders::Int, 
                           valuation_distribution::Symbol=:uniform, risk_aversion::Float64=0.0)
        valuation >= 0 || throw(ArgumentError("Valuation must be non-negative"))
        expected_bidders >= 1 || throw(ArgumentError("Expected bidders must be positive"))
        valuation_distribution in [:uniform, :normal] || throw(ArgumentError("Invalid valuation distribution"))
        risk_aversion >= 0 || throw(ArgumentError("Risk aversion must be non-negative"))
        new(valuation, expected_bidders, valuation_distribution, risk_aversion)
    end
end

#=============================================================================
    Bidding Functions
=============================================================================#

"""
    generate_bid(strategy::AbstractBiddingStrategy, auction::AbstractAuction)

Generate a bid based on the bidding strategy and auction type.
"""
function generate_bid(strategy::TruthfulBidder, auction::AbstractAuction)
    return strategy.valuation
end

function generate_bid(strategy::ShadedBidder, auction::AbstractAuction)
    return strategy.valuation * (1 - strategy.shading_factor)
end

function generate_bid(strategy::RandomBidder, auction::AbstractAuction)
    base_bid = generate_bid(strategy.base_strategy, auction)
    noise = randn() * strategy.noise_level
    return max(0.0, base_bid + noise)
end

function generate_bid(strategy::StrategicBidder, auction::AbstractAuction)
    # Simplified strategic bidding
    if isa(auction, FirstPriceAuction)
        # First-price auction: shade bid based on expected competition
        n = strategy.expected_bidders
        shading_factor = (n - 1) / n  # Simplified optimal shading
        return strategy.valuation * shading_factor
    elseif isa(auction, SecondPriceAuction)
        # Second-price auction: truthful bidding is optimal
        return strategy.valuation
    else
        return strategy.valuation
    end
end

#=============================================================================
    Auction Functions
=============================================================================#

"""
    conduct_auction(auction::AbstractAuction, bidders::Vector{<:AbstractBidder})

Conduct an auction with the given bidders and return the result.
"""
function conduct_auction(auction::AbstractAuction, bidders::Vector{<:AbstractBidder})
    # Generate bids
    bids = Bid[]
    for bidder in bidders
        bid_amount = generate_bid(get_strategy(bidder), auction)
        push!(bids, Bid(get_id(bidder), bid_amount))
    end
    
    # Validate bids
    validate_bids(bids, auction) || throw(ArgumentError("Invalid bids"))
    
    # Determine winner(s)
    winner_info = determine_winner(bids, auction)
    
    # Calculate payment(s)
    payment = calculate_payment(winner_info, bids, auction)
    
    # Create result
    statistics = StatisticsDict(
        "num_bidders" => NumericStat(length(bidders)),
        "num_valid_bids" => NumericStat(length(bids)),
        "highest_bid" => NumericStat(isempty(bids) ? 0.0 : maximum(b.value for b in bids)),
        "revenue" => NumericStat(payment),
        "efficiency" => NumericStat(calculate_efficiency(winner_info, bidders, auction))
    )
    
    return AuctionResult(
        auction,
        winner_info.winner_id,
        payment,
        bids,
        statistics
    )
end

"""
    determine_winner(bids::Vector{Bid}, auction::AbstractAuction)

Determine the winner of an auction based on the bids and auction rules.
"""
function determine_winner(bids::Vector{Bid}, auction::AbstractAuction)
    # Filter bids that meet reserve price
    valid_bids = filter(b -> b.value >= auction.reserve_price, bids)
    
    if isempty(valid_bids)
        return (winner_id=nothing, winning_bid=nothing)
    end
    
    # Sort bids by value (descending)
    sorted_bids = sort(valid_bids, by=b -> b.value, rev=true)
    
    # Handle ties
    highest_value = sorted_bids[1].value
    tied_bids = filter(b -> b.value == highest_value, sorted_bids)
    
    if length(tied_bids) == 1
        winner_bid = tied_bids[1]
    else
        # Apply tie-breaking rule
        if auction.tie_breaking == :random
            winner_bid = rand(tied_bids)
        elseif auction.tie_breaking == :first_come
            winner_bid = tied_bids[argmin([b.timestamp for b in tied_bids])]
        elseif auction.tie_breaking == :highest_id
            winner_bid = tied_bids[argmax([b.bidder_id for b in tied_bids])]
        else
            winner_bid = tied_bids[1]  # Default
        end
    end
    
    return (winner_id=winner_bid.bidder_id, winning_bid=winner_bid)
end

"""
    calculate_payment(winner_info, bids::Vector{Bid}, auction::AbstractAuction)

Calculate the payment for the winner based on the auction type.
"""
function calculate_payment(winner_info, bids::Vector{Bid}, auction::AbstractAuction)
    if winner_info.winner_id === nothing
        return 0.0
    end
    
    if isa(auction, FirstPriceAuction)
        # Winner pays their bid
        return winner_info.winning_bid.value
    elseif isa(auction, SecondPriceAuction)
        # Winner pays second-highest bid
        valid_bids = filter(b -> b.value >= auction.reserve_price, bids)
        sorted_bids = sort(valid_bids, by=b -> b.value, rev=true)
        
        if length(sorted_bids) >= 2
            return sorted_bids[2].value
        else
            return auction.reserve_price
        end
    else
        throw(ArgumentError("Unknown auction type"))
    end
end

"""
    validate_bids(bids::Vector{Bid}, auction::AbstractAuction)

Validate that all bids are valid for the given auction.
"""
function validate_bids(bids::Vector{Bid}, auction::AbstractAuction)
    for bid in bids
        if bid.value < 0
            return false
        end
        if bid.bidder_id <= 0
            return false
        end
    end
    return true
end

"""
    calculate_efficiency(winner_info, bidders::Vector{<:AbstractBidder}, auction::AbstractAuction)

Calculate the efficiency of the auction outcome.
"""
function calculate_efficiency(winner_info, bidders::Vector{<:AbstractBidder}, auction::AbstractAuction)
    if winner_info.winner_id === nothing
        return 0.0
    end
    
    # Find the winner's valuation
    winner_valuation = 0.0
    for bidder in bidders
        if get_id(bidder) == winner_info.winner_id
            winner_valuation = get_valuation(bidder)
            break
        end
    end
    
    # Calculate optimal allocation (highest valuation)
    optimal_valuation = maximum(get_valuation(b) for b in bidders)
    
    return optimal_valuation > 0 ? winner_valuation / optimal_valuation : 1.0
end