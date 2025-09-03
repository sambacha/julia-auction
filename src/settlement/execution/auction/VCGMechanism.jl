"""
    VCGMechanism

Implements the Vickrey-Clarke-Groves (VCG) mechanism for truthful auctions.
The VCG mechanism ensures truthful bidding is a dominant strategy by making
each winner pay their externality - the value they deny to others.

This implementation focuses on single-item auctions with extensions for
multi-unit scenarios in phantom auctions.
"""
module VCGMechanism

using LinearAlgebra
using Statistics
export VCGAuction, VCGBid, VCGAllocation, VCGResult
export run_vcg_auction, calculate_payments, verify_truthfulness
export social_welfare, individual_rationality_check

# Type alias for flexible numeric types
const NumericValue = Union{Float64,Float32,Int64}

"""
    VCGBid{T<:NumericValue}

Represents a bid in a VCG auction.

# Fields
- `bidder_id::String`: Unique identifier for the bidder
- `valuation::T`: Bidder's true valuation (or bid amount)
- `quantity::T`: Quantity desired (for multi-unit auctions)
- `is_phantom::Bool`: Whether this is a phantom bidder
- `metadata::Dict{Symbol, Any}`: Additional bid metadata
"""
struct VCGBid{T<:NumericValue}
    bidder_id::String
    valuation::T
    quantity::T
    is_phantom::Bool
    metadata::Dict{Symbol,Any}

    function VCGBid(
        bidder_id::String,
        valuation::T,
        quantity::T = one(T);
        is_phantom::Bool = false,
        metadata::Dict{Symbol,Any} = Dict{Symbol,Any}(),
    ) where {T<:NumericValue}
        new{T}(bidder_id, valuation, quantity, is_phantom, metadata)
    end
end

"""
    VCGAllocation{T}

Represents an allocation in the VCG mechanism.

# Fields
- `bidder_id::String`: Winner's identifier
- `quantity::T`: Quantity allocated
- `payment::T`: VCG payment (externality imposed)
- `utility::T`: Bidder's utility (valuation - payment)
"""
struct VCGAllocation{T<:NumericValue}
    bidder_id::String
    quantity::T
    payment::T
    utility::T
end

"""
    VCGResult{T}

Complete result of a VCG auction.

# Fields
- `allocations::Vector{VCGAllocation{T}}`: All winning allocations
- `social_welfare::T`: Total social welfare achieved
- `total_revenue::T`: Total payments collected
- `efficiency::Float64`: Efficiency ratio (actual/optimal welfare)
- `phantom_participation_rate::Float64`: Percentage of phantom bidders
"""
struct VCGResult{T<:NumericValue}
    allocations::Vector{VCGAllocation{T}}
    social_welfare::T
    total_revenue::T
    efficiency::Float64
    phantom_participation_rate::Float64
end

"""
    VCGAuction{T}

Configuration and state for a VCG auction.

# Fields
- `supply::T`: Total supply available
- `reserve_price::T`: Minimum acceptable price
- `bids::Vector{VCGBid{T}}`: All submitted bids
- `enable_multi_unit::Bool`: Allow multiple units per bidder
"""
mutable struct VCGAuction{T<:NumericValue}
    supply::T
    reserve_price::T
    bids::Vector{VCGBid{T}}
    enable_multi_unit::Bool

    function VCGAuction(supply::T, reserve_price::T = zero(T); enable_multi_unit::Bool = false) where {T<:NumericValue}
        new{T}(supply, reserve_price, VCGBid{T}[], enable_multi_unit)
    end
end

"""
    run_vcg_auction(auction::VCGAuction{T}) -> VCGResult{T}

Execute a VCG auction to determine allocations and payments.

The mechanism:
1. Finds allocation maximizing social welfare
2. Calculates each winner's payment as their externality
3. Ensures truthfulness and individual rationality

# Arguments
- `auction::VCGAuction{T}`: Configured auction with bids

# Returns
- `VCGResult{T}`: Complete auction results with allocations and metrics
"""
function run_vcg_auction(auction::VCGAuction{T}) where {T<:NumericValue}
    # Filter bids above reserve price
    eligible_bids = filter(b -> b.valuation >= auction.reserve_price, auction.bids)

    if isempty(eligible_bids)
        return VCGResult{T}(VCGAllocation{T}[], zero(T), zero(T), 0.0, calculate_phantom_rate(auction.bids))
    end

    # Sort bids by valuation (descending)
    sorted_bids = sort(eligible_bids, by = b->b.valuation, rev = true)

    # Find optimal allocation
    allocation_map = find_optimal_allocation(sorted_bids, auction.supply, auction.enable_multi_unit)

    # Calculate VCG payments
    payments = calculate_payments(sorted_bids, allocation_map, auction.supply)

    # Create allocations with utilities
    allocations = VCGAllocation{T}[]
    total_welfare = zero(T)
    total_revenue = zero(T)

    for (bidder_id, quantity) in allocation_map
        bid = findfirst(b -> b.bidder_id == bidder_id, sorted_bids)
        if bid !== nothing
            valuation = sorted_bids[bid].valuation
            payment = get(payments, bidder_id, zero(T))
            utility = valuation * quantity - payment

            push!(allocations, VCGAllocation{T}(bidder_id, quantity, payment, utility))

            total_welfare += valuation * quantity
            total_revenue += payment
        end
    end

    # Calculate efficiency (ratio to first-best)
    optimal_welfare = calculate_optimal_welfare(sorted_bids, auction.supply)
    efficiency = optimal_welfare > zero(T) ? total_welfare / optimal_welfare : 1.0

    return VCGResult{T}(allocations, total_welfare, total_revenue, efficiency, calculate_phantom_rate(auction.bids))
end

"""
    find_optimal_allocation(bids, supply, multi_unit) -> Dict{String, T}

Find the allocation that maximizes social welfare.

For single-unit: Allocate to highest bidder
For multi-unit: Allocate greedily by valuation until supply exhausted
"""
function find_optimal_allocation(bids::Vector{VCGBid{T}}, supply::T, multi_unit::Bool) where {T<:NumericValue}
    allocation = Dict{String,T}()
    remaining_supply = supply

    for bid in bids
        if remaining_supply <= zero(T)
            break
        end

        if multi_unit
            # Allocate min(requested, available)
            allocated = min(bid.quantity, remaining_supply)
        else
            # Single unit per bidder
            allocated = min(one(T), remaining_supply)
        end

        if allocated > zero(T)
            allocation[bid.bidder_id] = allocated
            remaining_supply -= allocated
        end
    end

    return allocation
end

"""
    calculate_payments(bids, allocation, supply) -> Dict{String, T}

Calculate VCG payments for each winner.

Payment = Welfare without bidder - Welfare of others with bidder
"""
function calculate_payments(bids::Vector{VCGBid{T}}, allocation::Dict{String,T}, supply::T) where {T<:NumericValue}
    payments = Dict{String,T}()

    # Calculate welfare with all bidders
    total_welfare = calculate_welfare(bids, allocation)

    for (winner_id, winner_quantity) in allocation
        # Calculate optimal allocation without this bidder
        bids_without = filter(b -> b.bidder_id != winner_id, bids)
        allocation_without = find_optimal_allocation(bids_without, supply, true)
        welfare_without = calculate_welfare(bids_without, allocation_without)

        # Calculate welfare of others in current allocation
        others_welfare = zero(T)
        for (bidder_id, quantity) in allocation
            if bidder_id != winner_id
                bid_idx = findfirst(b -> b.bidder_id == bidder_id, bids)
                if bid_idx !== nothing
                    others_welfare += bids[bid_idx].valuation * quantity
                end
            end
        end

        # VCG payment is the externality imposed
        payment = max(zero(T), welfare_without - others_welfare)
        payments[winner_id] = payment
    end

    return payments
end

"""
    calculate_welfare(bids, allocation) -> T

Calculate total social welfare for given allocation.
"""
function calculate_welfare(bids::Vector{VCGBid{T}}, allocation::Dict{String,T}) where {T<:NumericValue}
    welfare = zero(T)

    for (bidder_id, quantity) in allocation
        bid_idx = findfirst(b -> b.bidder_id == bidder_id, bids)
        if bid_idx !== nothing
            welfare += bids[bid_idx].valuation * quantity
        end
    end

    return welfare
end

"""
    calculate_optimal_welfare(bids, supply) -> T

Calculate the first-best (optimal) social welfare.
"""
function calculate_optimal_welfare(bids::Vector{VCGBid{T}}, supply::T) where {T<:NumericValue}
    optimal_allocation = find_optimal_allocation(bids, supply, true)
    return calculate_welfare(bids, optimal_allocation)
end

"""
    social_welfare(result::VCGResult{T}) -> T

Get the total social welfare achieved in the auction.
"""
social_welfare(result::VCGResult{T}) where {T} = result.social_welfare

"""
    verify_truthfulness(auction::VCGAuction{T}, bidder_id::String, true_value::T) -> Bool

Verify that truthful bidding is optimal for a specific bidder.

Tests whether bidding true value yields higher utility than any deviation.
"""
function verify_truthfulness(auction::VCGAuction{T}, bidder_id::String, true_value::T) where {T<:NumericValue}
    # Utility from truthful bidding
    truthful_auction = deepcopy(auction)
    update_bid!(truthful_auction, bidder_id, true_value)
    truthful_result = run_vcg_auction(truthful_auction)
    truthful_utility = get_utility(truthful_result, bidder_id)

    # Test various deviations
    test_values = [
        true_value * T(0.5),  # Underbid by 50%
        true_value * T(0.8),  # Underbid by 20%
        true_value * T(0.95), # Underbid by 5%
        true_value * T(1.05), # Overbid by 5%
        true_value * T(1.2),  # Overbid by 20%
        true_value * T(1.5),  # Overbid by 50%
    ]

    for test_value in test_values
        test_auction = deepcopy(auction)
        update_bid!(test_auction, bidder_id, test_value)
        test_result = run_vcg_auction(test_auction)
        test_utility = get_utility(test_result, bidder_id)

        if test_utility > truthful_utility
            return false  # Found profitable deviation
        end
    end

    return true  # Truthful bidding is optimal
end

"""
    individual_rationality_check(result::VCGResult{T}) -> Bool

Verify that all participants have non-negative utility.
"""
function individual_rationality_check(result::VCGResult{T}) where {T<:NumericValue}
    return all(a -> a.utility >= zero(T), result.allocations)
end

"""
    calculate_phantom_rate(bids::Vector{VCGBid{T}}) -> Float64

Calculate the percentage of phantom bidders in the auction.
"""
function calculate_phantom_rate(bids::Vector{VCGBid{T}}) where {T<:NumericValue}
    if isempty(bids)
        return 0.0
    end

    phantom_count = count(b -> b.is_phantom, bids)
    return phantom_count / length(bids)
end

"""
    update_bid!(auction::VCGAuction{T}, bidder_id::String, new_value::T)

Update or add a bid in the auction.
"""
function update_bid!(auction::VCGAuction{T}, bidder_id::String, new_value::T) where {T<:NumericValue}
    bid_idx = findfirst(b -> b.bidder_id == bidder_id, auction.bids)

    if bid_idx !== nothing
        # Update existing bid
        old_bid = auction.bids[bid_idx]
        auction.bids[bid_idx] =
            VCGBid(bidder_id, new_value, old_bid.quantity, is_phantom = old_bid.is_phantom, metadata = old_bid.metadata)
    else
        # Add new bid
        push!(auction.bids, VCGBid(bidder_id, new_value, one(T)))
    end
end

"""
    get_utility(result::VCGResult{T}, bidder_id::String) -> T

Get the utility achieved by a specific bidder.
"""
function get_utility(result::VCGResult{T}, bidder_id::String) where {T<:NumericValue}
    allocation = findfirst(a -> a.bidder_id == bidder_id, result.allocations)

    if allocation !== nothing
        return result.allocations[allocation].utility
    else
        return zero(T)  # No allocation means zero utility
    end
end

"""
    efficiency_loss(result::VCGResult{T}) -> Float64

Calculate the efficiency loss (1 - efficiency ratio).
"""
efficiency_loss(result::VCGResult{T}) where {T} = 1.0 - result.efficiency

"""
    revenue_efficiency(result::VCGResult{T}) -> Float64

Calculate revenue as percentage of social welfare.
"""
function revenue_efficiency(result::VCGResult{T}) where {T<:NumericValue}
    if result.social_welfare > zero(T)
        return Float64(result.total_revenue / result.social_welfare)
    else
        return 0.0
    end
end

end # module VCGMechanism
