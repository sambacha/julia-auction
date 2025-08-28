"""
    AugmentedUniformPriceAuction

Implementation of augmented uniform price auctions with elastic supply schedules
and advanced tie-breaking mechanisms to mitigate bid shading.

Based on Wilson (1979) and subsequent auction theory research.
"""
module AugmentedUniformPriceAuction

using Base.Threads: Atomic, @spawn
using LinearAlgebra
using Statistics
export ElasticSupplySchedule, SupplyPoint, ElasticityType
export AuctionConfig, Bid, AuctionResult, BidAllocation
export TieBreakingStrategy, StandardTieBreaking, AugmentedTieBreaking
export run_auction, find_clearing_price, calculate_supply_at_price
export analyze_bid_shading, calculate_efficiency
export create_elastic_schedule

# Elasticity types for supply curves
@enum ElasticityType begin
    EXPONENTIAL
    LINEAR
    LOGARITHMIC
end

# Supply point in elastic schedule
struct SupplyPoint
    price::Float64
    quantity::Float64
    elasticity::Float64  # Local elasticity at this point
end

# Elastic supply schedule
struct ElasticSupplySchedule
    points::Vector{SupplyPoint}
    base_quantity::Float64
    price_floor::Float64
    price_ceiling::Float64
    elasticity_type::ElasticityType
    
    function ElasticSupplySchedule(points::Vector{SupplyPoint}, 
                                  base_quantity::Float64,
                                  price_floor::Float64,
                                  price_ceiling::Float64,
                                  elasticity_type::ElasticityType = LINEAR)
        # Validate and sort points by price
        sorted_points = sort(points, by=p->p.price)
        
        # Ensure monotonicity
        for i in 2:length(sorted_points)
            if sorted_points[i].quantity < sorted_points[i-1].quantity
                throw(ArgumentError("Supply schedule must be monotonically increasing"))
            end
        end
        
        new(sorted_points, base_quantity, price_floor, price_ceiling, elasticity_type)
    end
end

# Tie-breaking strategy
abstract type TieBreakingStrategy end

struct StandardTieBreaking <: TieBreakingStrategy
    # Highest bids first (traditional approach)
end

struct AugmentedTieBreaking <: TieBreakingStrategy
    quantity_weight::Float64  # Weight for quantity margin pressure
    time_weight::Float64      # Weight for time priority
    
    function AugmentedTieBreaking(quantity_weight::Float64 = 0.7, 
                                 time_weight::Float64 = 0.3)
        if quantity_weight + time_weight > 1.0
            throw(ArgumentError("Weights must sum to at most 1.0"))
        end
        new(quantity_weight, time_weight)
    end
end

# Bid structure
struct Bid
    bidder_id::String
    quantity::Float64
    price::Float64
    timestamp::Float64  # Unix timestamp
    is_marginal::Bool   # Flag for marginal bid analysis
    
    function Bid(bidder_id::String, quantity::Float64, price::Float64;
                timestamp::Float64 = time(), is_marginal::Bool = false)
        if quantity <= 0
            throw(ArgumentError("Bid quantity must be positive"))
        end
        if price < 0
            throw(ArgumentError("Bid price cannot be negative"))
        end
        new(bidder_id, quantity, price, timestamp, is_marginal)
    end
end

# Bid allocation result
struct BidAllocation
    bid::Bid
    allocated_quantity::Float64
    payment::Float64
end

# Auction configuration
struct AuctionConfig
    supply_schedule::ElasticSupplySchedule
    tie_breaking::TieBreakingStrategy
    reserve_price::Float64
    max_bids_per_bidder::Int
    min_bid_increment::Float64
    allow_partial_fills::Bool
    
    function AuctionConfig(;
        supply_schedule::ElasticSupplySchedule,
        tie_breaking::TieBreakingStrategy = StandardTieBreaking(),
        reserve_price::Float64 = 0.0,
        max_bids_per_bidder::Int = 100,
        min_bid_increment::Float64 = 0.01,
        allow_partial_fills::Bool = true
    )
        new(supply_schedule, tie_breaking, reserve_price, 
            max_bids_per_bidder, min_bid_increment, allow_partial_fills)
    end
end

# Auction result
struct AuctionResult
    clearing_price::Float64
    allocations::Vector{BidAllocation}
    total_quantity::Float64
    total_revenue::Float64
    supply_utilized::Float64
    bid_shading_estimate::Float64
    efficiency_score::Float64
    num_tie_breaks::Int
    execution_time_ms::Float64
end

# Calculate supply at given price using elastic schedule
@inline function calculate_supply_at_price(schedule::ElasticSupplySchedule, price::Float64)::Float64
    if price < schedule.price_floor
        return 0.0
    end
    
    if price >= schedule.price_ceiling
        return schedule.points[end].quantity
    end
    
    # Interpolate between points
    for i in 2:length(schedule.points)
        if price <= schedule.points[i].price
            prev = schedule.points[i-1]
            curr = schedule.points[i]
            
            # Linear interpolation with elasticity adjustment
            t = (price - prev.price) / (curr.price - prev.price)
            
            if schedule.elasticity_type == EXPONENTIAL
                # Exponential growth between points
                α = log(curr.quantity / prev.quantity) / (curr.price - prev.price)
                return prev.quantity * exp(α * (price - prev.price))
                
            elseif schedule.elasticity_type == LOGARITHMIC
                # Logarithmic growth (slower)
                return prev.quantity + (curr.quantity - prev.quantity) * log(1 + t) / log(2)
                
            else  # LINEAR
                return prev.quantity + t * (curr.quantity - prev.quantity)
            end
        end
    end
    
    return schedule.points[end].quantity
end

# Find clearing price where demand meets supply
@inline function find_clearing_price(bids::Vector{Bid}, config::AuctionConfig)::Float64
    if isempty(bids)
        return config.reserve_price
    end
    
    # Sort bids by price descending
    sorted_bids = sort(bids, by=b->b.price, rev=true)
    
    # Binary search for clearing price
    min_price = max(config.reserve_price, config.supply_schedule.price_floor)
    max_price = min(sorted_bids[1].price, config.supply_schedule.price_ceiling)
    
    # Check if there's any feasible price
    total_demand = sum(b.quantity for b in sorted_bids)
    max_supply = calculate_supply_at_price(config.supply_schedule, max_price)
    
    if total_demand <= 0 || max_supply <= 0
        return config.reserve_price
    end
    
    # Binary search with Newton-Raphson refinement
    clearing_price = min_price
    tolerance = config.min_bid_increment / 10
    max_iterations = 100
    
    for iter in 1:max_iterations
        mid_price = (min_price + max_price) / 2
        
        # Calculate demand at mid_price
        demand = sum(b.quantity for b in sorted_bids if b.price >= mid_price)
        
        # Calculate supply at mid_price
        supply = calculate_supply_at_price(config.supply_schedule, mid_price)
        
        excess = demand - supply
        
        if abs(excess) < tolerance
            clearing_price = mid_price
            break
        elseif excess > 0
            # Demand exceeds supply, increase price
            min_price = mid_price
        else
            # Supply exceeds demand, decrease price
            max_price = mid_price
        end
        
        clearing_price = mid_price
    end
    
    return clearing_price
end

# Resolve tie-breaking at clearing price
function resolve_ties(bids_at_clearing::Vector{Bid}, 
                     available_quantity::Float64,
                     strategy::StandardTieBreaking)::Vector{Bid}
    # Standard: highest timestamp first (earliest bids)
    sorted = sort(bids_at_clearing, by=b->b.timestamp)
    
    allocated = Bid[]
    remaining = available_quantity
    
    for bid in sorted
        if remaining >= bid.quantity
            push!(allocated, bid)
            remaining -= bid.quantity
        elseif remaining > 0
            # Partial fill
            partial_bid = Bid(bid.bidder_id, remaining, bid.price, 
                            timestamp=bid.timestamp, is_marginal=bid.is_marginal)
            push!(allocated, partial_bid)
            break
        else
            break
        end
    end
    
    return allocated
end

function resolve_ties(bids_at_clearing::Vector{Bid}, 
                     available_quantity::Float64,
                     strategy::AugmentedTieBreaking)::Vector{Bid}
    # Augmented: Create composite score for tie-breaking
    scores = Float64[]
    
    for bid in bids_at_clearing
        # Price component (primary - but all are equal at clearing)
        price_score = bid.price
        
        # Quantity margin pressure (secondary)
        # Larger quantities get slight advantage to reduce shading
        quantity_score = log(1 + bid.quantity) * strategy.quantity_weight
        
        # Time priority (tertiary)
        time_score = (1.0 / (1.0 + bid.timestamp)) * strategy.time_weight
        
        # Composite score
        total_score = price_score + quantity_score * 0.01 + time_score * 0.001
        push!(scores, total_score)
    end
    
    # Sort by composite score
    sorted_indices = sortperm(scores, rev=true)
    sorted_bids = bids_at_clearing[sorted_indices]
    
    allocated = Bid[]
    remaining = available_quantity
    
    for bid in sorted_bids
        if remaining >= bid.quantity
            push!(allocated, bid)
            remaining -= bid.quantity
        elseif remaining > 0 && strategy isa AugmentedTieBreaking
            # Allow partial fills in augmented mode
            partial_bid = Bid(bid.bidder_id, remaining, bid.price,
                            timestamp=bid.timestamp, is_marginal=bid.is_marginal)
            push!(allocated, partial_bid)
            break
        else
            break
        end
    end
    
    return allocated
end

# Main auction execution
function run_auction(bids::Vector{Bid}, config::AuctionConfig)::AuctionResult
    start_time = time()
    
    # Validate bids
    validated_bids = validate_bids(bids, config)
    
    if isempty(validated_bids)
        return _create_empty_result(config.reserve_price, start_time)
    end
    
    # Find clearing price and available supply
    clearing_price = find_clearing_price(validated_bids, config)
    available_supply = calculate_supply_at_price(config.supply_schedule, clearing_price)
    
    # Perform allocation
    allocations, num_tie_breaks = _perform_allocation(
        validated_bids, 
        clearing_price, 
        available_supply, 
        config
    )
    
    # Calculate final metrics
    result_metrics = _calculate_auction_metrics(
        allocations, 
        validated_bids, 
        clearing_price, 
        available_supply
    )
    
    execution_time_ms = (time() - start_time) * 1000
    
    return AuctionResult(
        clearing_price,
        allocations,
        result_metrics.total_quantity,
        result_metrics.total_revenue,
        result_metrics.supply_utilized,
        result_metrics.bid_shading_estimate,
        result_metrics.efficiency_score,
        num_tie_breaks,
        execution_time_ms,
    )
end

"""
    _create_empty_result(reserve_price, start_time)

Create an empty auction result when no valid bids are available.

# Arguments
- `reserve_price::Float64`: The auction reserve price
- `start_time::Float64`: Auction start timestamp for calculating execution time

# Returns
- `AuctionResult`: Empty result with zero allocations and metrics
"""
function _create_empty_result(reserve_price::Float64, start_time::Float64)::AuctionResult
    execution_time_ms = (time() - start_time) * 1000
    return AuctionResult(
        reserve_price, BidAllocation[], 0.0, 0.0, 0.0, 
        0.0, 0.0, 0, execution_time_ms
    )
end

"""
    _perform_allocation(validated_bids, clearing_price, available_supply, config)

Perform bid allocation with tie-breaking for an auction.

# Arguments
- `validated_bids::Vector{Bid}`: Valid bids to process
- `clearing_price::Float64`: The auction clearing price
- `available_supply::Float64`: Total supply available for allocation  
- `config::AuctionConfig`: Auction configuration settings

# Returns
- `Tuple{Vector{BidAllocation}, Int}`: (allocations, number of tie-breaks)
"""
function _perform_allocation(
    validated_bids::Vector{Bid}, 
    clearing_price::Float64, 
    available_supply::Float64, 
    config::AuctionConfig
)::Tuple{Vector{BidAllocation}, Int}
    # Separate bids above, at, and below clearing
    bids_above = Bid[b for b in validated_bids if b.price > clearing_price]
    bids_at = Bid[b for b in validated_bids if b.price == clearing_price]
    
    allocations = BidAllocation[]
    remaining_supply = available_supply
    
    # Allocate to bids above clearing first
    remaining_supply = _allocate_above_clearing(
        allocations, 
        bids_above, 
        clearing_price, 
        remaining_supply, 
        config
    )
    
    # Handle tie-breaking for bids at clearing price
    num_tie_breaks = _handle_ties(
        allocations, 
        bids_at, 
        clearing_price, 
        remaining_supply, 
        config
    )
    
    return allocations, num_tie_breaks
end

"""
    _allocate_above_clearing(allocations, bids_above, clearing_price, remaining_supply, config)

Allocate supply to bids above the clearing price.

# Arguments
- `allocations::Vector{BidAllocation}`: Allocation results to append to
- `bids_above::Vector{Bid}`: Bids with price above clearing price
- `clearing_price::Float64`: The auction clearing price
- `remaining_supply::Float64`: Supply remaining for allocation
- `config::AuctionConfig`: Auction configuration for partial fills

# Returns
- `Float64`: Supply remaining after allocation
"""
function _allocate_above_clearing(
    allocations::Vector{BidAllocation},
    bids_above::Vector{Bid},
    clearing_price::Float64,
    remaining_supply::Float64,
    config::AuctionConfig
)::Float64
    for bid in bids_above
        if remaining_supply >= bid.quantity
            allocation = BidAllocation(bid, bid.quantity, clearing_price * bid.quantity)
            push!(allocations, allocation)
            remaining_supply -= bid.quantity
        elseif remaining_supply > 0 && config.allow_partial_fills
            allocation = BidAllocation(bid, remaining_supply, clearing_price * remaining_supply)
            push!(allocations, allocation)
            remaining_supply = 0.0
            break
        end
    end
    return remaining_supply
end

function _handle_ties(
    allocations::Vector{BidAllocation},
    bids_at::Vector{Bid},
    clearing_price::Float64,
    remaining_supply::Float64,
    config::AuctionConfig
)::Int
    if remaining_supply <= 0 || isempty(bids_at)
        return 0
    end
    
    num_tie_breaks = length(bids_at)
    tied_winners = resolve_ties(bids_at, remaining_supply, config.tie_breaking)
    
    for bid in tied_winners
        allocation = BidAllocation(bid, bid.quantity, clearing_price * bid.quantity)
        push!(allocations, allocation)
    end
    
    return num_tie_breaks
end

function _calculate_auction_metrics(
    allocations::Vector{BidAllocation},
    validated_bids::Vector{Bid},
    clearing_price::Float64,
    available_supply::Float64
)::NamedTuple{(:total_quantity, :total_revenue, :supply_utilized, :bid_shading_estimate, :efficiency_score), Tuple{Float64, Float64, Float64, Float64, Float64}}
    total_quantity = sum(a.allocated_quantity for a in allocations)
    total_revenue = sum(a.payment for a in allocations)
    supply_utilized = total_quantity / available_supply
    bid_shading_estimate = analyze_bid_shading(validated_bids, clearing_price)
    efficiency_score = calculate_efficiency(allocations, validated_bids, clearing_price)
    
    return (
        total_quantity=total_quantity,
        total_revenue=total_revenue,
        supply_utilized=supply_utilized,
        bid_shading_estimate=bid_shading_estimate,
        efficiency_score=efficiency_score
    )
end

# Validate bids against auction rules
function validate_bids(bids::Vector{Bid}, config::AuctionConfig)::Vector{Bid}
    validated = Bid[]
    bidder_counts = Dict{String, Int}()
    
    for bid in bids
        # Check reserve price
        if bid.price < config.reserve_price
            continue
        end
        
        # Check bidder limits
        count = get(bidder_counts, bid.bidder_id, 0)
        if count >= config.max_bids_per_bidder
            continue
        end
        
        # Check minimum increment
        if !isempty(validated)
            last_price = validated[end].price
            if abs(bid.price - last_price) < config.min_bid_increment
                continue
            end
        end
        
        push!(validated, bid)
        bidder_counts[bid.bidder_id] = count + 1
    end
    
    return validated
end

# Analyze bid shading behavior
function analyze_bid_shading(bids::Vector{Bid}, clearing_price::Float64)::Float64
    if isempty(bids)
        return 0.0
    end
    
    # Estimate shading by comparing marginal vs non-marginal bids
    marginal_bids = [b for b in bids if b.is_marginal]
    regular_bids = [b for b in bids if !b.is_marginal]
    
    if isempty(marginal_bids) || isempty(regular_bids)
        # Fallback: estimate based on price distribution
        mean_price = mean(b.price for b in bids)
        std_price = std(b.price for b in bids)
        
        # Higher variance suggests more strategic bidding
        return min(100.0, (std_price / mean_price) * 100)
    end
    
    # Compare average prices
    avg_marginal = mean(b.price for b in marginal_bids)
    avg_regular = mean(b.price for b in regular_bids)
    
    # Shading percentage estimate
    shading_pct = ((avg_regular - avg_marginal) / avg_regular) * 100
    
    return max(0.0, min(100.0, shading_pct))
end

# Calculate auction efficiency
function calculate_efficiency(allocations::Vector{BidAllocation}, 
                            all_bids::Vector{Bid},
                            clearing_price::Float64)::Float64
    if isempty(allocations)
        return 0.0
    end
    
    # Efficiency = allocated value / maximum possible value
    allocated_value = sum(a.bid.price * a.allocated_quantity for a in allocations)
    
    # Maximum value would be allocating to highest value bidders
    sorted_bids = sort(all_bids, by=b->b.price, rev=true)
    total_available = sum(a.allocated_quantity for a in allocations)
    
    max_value = 0.0
    remaining = total_available
    
    for bid in sorted_bids
        if remaining >= bid.quantity
            max_value += bid.price * bid.quantity
            remaining -= bid.quantity
        elseif remaining > 0
            max_value += bid.price * remaining
            break
        else
            break
        end
    end
    
    efficiency = max_value > 0 ? (allocated_value / max_value) * 100 : 0.0
    
    return min(100.0, efficiency)
end

# Helper function to create elastic supply schedule
function create_elastic_schedule(;
    base_quantity::Float64 = 1000.0,
    price_floor::Float64 = 10.0,
    price_ceiling::Float64 = 100.0,
    num_points::Int = 10,
    elasticity_type::ElasticityType = LINEAR,
    elasticity_factor::Float64 = 1.5
)::ElasticSupplySchedule
    
    points = SupplyPoint[]
    price_range = price_ceiling - price_floor
    
    for i in 1:num_points
        t = (i - 1) / (num_points - 1)
        price = price_floor + t * price_range
        
        # Calculate quantity based on elasticity type
        if elasticity_type == EXPONENTIAL
            quantity = base_quantity * exp(elasticity_factor * t)
        elseif elasticity_type == LOGARITHMIC
            quantity = base_quantity * (1 + log(1 + elasticity_factor * t))
        else  # LINEAR
            quantity = base_quantity * (1 + elasticity_factor * t)
        end
        
        # Local elasticity
        local_elasticity = if i > 1
            dQ = quantity - points[end].quantity
            dP = price - points[end].price
            (dQ / quantity) / (dP / price)
        else
            elasticity_factor
        end
        
        push!(points, SupplyPoint(price, quantity, local_elasticity))
    end
    
    return ElasticSupplySchedule(points, base_quantity, price_floor, price_ceiling, elasticity_type)
end

# Additional analysis functions
function analyze_market_concentration(allocations::Vector{BidAllocation})::Float64
    # Calculate Herfindahl index
    if isempty(allocations)
        return 0.0
    end
    
    bidder_quantities = Dict{String, Float64}()
    total = 0.0
    
    for alloc in allocations
        bidder_quantities[alloc.bid.bidder_id] = get(bidder_quantities, alloc.bid.bidder_id, 0.0) + alloc.allocated_quantity
        total += alloc.allocated_quantity
    end
    
    hhi = 0.0
    for (_, quantity) in bidder_quantities
        market_share = quantity / total
        hhi += market_share^2
    end
    
    return hhi * 10000  # Scale to 0-10000
end

function calculate_price_discovery_efficiency(bids::Vector{Bid}, clearing_price::Float64)::Float64
    # Measure how well the auction discovers true market price
    if isempty(bids)
        return 0.0
    end
    
    # Calculate quantity-weighted average price
    total_value = sum(b.price * b.quantity for b in bids)
    total_quantity = sum(b.quantity for b in bids)
    weighted_avg_price = total_value / total_quantity
    
    # Price discovery efficiency based on convergence
    price_diff = abs(clearing_price - weighted_avg_price)
    efficiency = max(0.0, 100 * (1 - price_diff / weighted_avg_price))
    
    return efficiency
end

end # module