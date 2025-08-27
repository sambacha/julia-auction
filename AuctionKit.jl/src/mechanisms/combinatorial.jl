# Combinatorial auction implementation
# Following A/HC/LC naming pattern

using Combinatorics
using JuMP
using HiGHS

"""
    CombinatorialAuction{T}

Auction where bidders can bid on bundles of items.
Solves the winner determination problem to maximize revenue.
"""
struct CombinatorialAuction{T} <: SealedBidAuction{T}
    items::Vector{Symbol}
    reserve_prices::Dict{Symbol, T}
    max_bundle_size::Int
    allow_partial_allocation::Bool
    solver_time_limit::Float64
    
    function CombinatorialAuction(;
        items::Vector{Symbol},
        reserve_prices::Dict{Symbol, T} = Dict{Symbol, T}(),
        max_bundle_size::Int = length(items),
        allow_partial_allocation::Bool = false,
        solver_time_limit::Float64 = 60.0
    ) where T
        isempty(items) && throw(ArgumentError("Items list cannot be empty"))
        max_bundle_size >= 1 || throw(ArgumentError("Max bundle size must be at least 1"))
        max_bundle_size <= length(items) || throw(ArgumentError("Max bundle size cannot exceed number of items"))
        solver_time_limit > 0 || throw(ArgumentError("Solver time limit must be positive"))
        
        # Initialize reserve prices for missing items
        for item in items
            if !haskey(reserve_prices, item)
                reserve_prices[item] = zero(T)
            end
        end
        
        new{T}(items, reserve_prices, max_bundle_size, allow_partial_allocation, solver_time_limit)
    end
end

"""
    BundleBid{T}

Represents a bid on a bundle of items in a combinatorial auction.
"""
struct BundleBid{T}
    bid::Bid{T}
    bundle::Set{Symbol}
    
    function BundleBid(bid::Bid{T}, bundle::Set{Symbol}) where T
        isempty(bundle) && throw(ArgumentError("Bundle cannot be empty"))
        new{T}(bid, bundle)
    end
end

function solve_winner_determination_problem(
    mechanism::CombinatorialAuction{T},
    bundle_bids::Vector{BundleBid{T}}
) where T
    if isempty(bundle_bids)
        return UUID[], Dict{UUID, Set{Symbol}}(), Dict{UUID, T}()
    end
    
    # Create optimization model
    model = Model(HiGHS.Optimizer)
    set_optimizer_attribute(model, "time_limit", mechanism.solver_time_limit)
    set_optimizer_attribute(model, "output_flag", false)
    
    n_bids = length(bundle_bids)
    
    # Decision variables: x[i] = 1 if bid i is accepted
    @variable(model, x[1:n_bids], Bin)
    
    # Objective: maximize revenue
    bid_values = [Float64(bb.bid.amount) for bb in bundle_bids]
    @objective(model, Max, sum(bid_values[i] * x[i] for i in 1:n_bids))
    
    # Constraint: each item allocated at most once
    for item in mechanism.items
        relevant_bids = findall(bb -> item in bb.bundle, bundle_bids)
        if !isempty(relevant_bids)
            @constraint(model, sum(x[i] for i in relevant_bids) <= 1)
        end
    end
    
    # Constraint: respect reserve prices
    for i in 1:n_bids
        bundle = bundle_bids[i].bundle
        min_price = sum(get(mechanism.reserve_prices, item, zero(T)) for item in bundle)
        if bundle_bids[i].bid.amount < min_price
            @constraint(model, x[i] == 0)
        end
    end
    
    # Solve the problem
    optimize!(model)
    
    if termination_status(model) ∉ [MOI.OPTIMAL, MOI.TIME_LIMIT]
        return UUID[], Dict{UUID, Set{Symbol}}(), Dict{UUID, T}()
    end
    
    # Extract solution
    winners = UUID[]
    allocations = Dict{UUID, Set{Symbol}}()
    payments = Dict{UUID, T}()
    
    for i in 1:n_bids
        if value(x[i]) > 0.5  # Binary variable threshold
            bidder_id = bundle_bids[i].bid.bidder_id
            push!(winners, bidder_id)
            allocations[bidder_id] = bundle_bids[i].bundle
            payments[bidder_id] = bundle_bids[i].bid.amount
        end
    end
    
    return winners, allocations, payments
end

function determine_clearing_price(mechanism::CombinatorialAuction{T},
    bids::Vector{Bid{T}}) where T
    # In combinatorial auctions, there's no single clearing price
    # Return the average winning bid price per item
    bundle_bids = convert_to_bundle_bids(mechanism, bids)
    winners, allocations, payments = solve_winner_determination_problem(mechanism, bundle_bids)
    
    if isempty(winners)
        return zero(T)
    end
    
    total_payment = sum(values(payments))
    total_items = sum(length(bundle) for bundle in values(allocations))
    
    return total_items > 0 ? T(total_payment / total_items) : zero(T)
end

function allocate_winners(
    mechanism::CombinatorialAuction{T},
    bids::Vector{Bid{T}},
    clearing_price::T
) where T
    bundle_bids = convert_to_bundle_bids(mechanism, bids)
    winners, allocations, _ = solve_winner_determination_problem(mechanism, bundle_bids)
    
    # Convert Set{Symbol} allocations to quantities (1 per item)
    quantity_allocations = Dict{UUID, T}()
    for (bidder_id, bundle) in allocations
        quantity_allocations[bidder_id] = T(length(bundle))
    end
    
    return winners, quantity_allocations
end

function calculate_payments(
    mechanism::CombinatorialAuction{T},
    winners::Vector{UUID},
    allocations::Dict{UUID, T},
    clearing_price::T
) where T
    # Re-solve to get actual payments
    bundle_bids = convert_to_bundle_bids(mechanism, Bid{T}[])  # This would need actual bids
    _, _, payments = solve_winner_determination_problem(mechanism, bundle_bids)
    return payments
end

function convert_to_bundle_bids(mechanism::CombinatorialAuction{T},
    bids::Vector{Bid{T}}) where T
    bundle_bids = BundleBid{T}[]
    
    for bid in bids
        # Extract bundle from bid metadata
        if haskey(bid.metadata, :bundle)
            bundle_items = bid.metadata[:bundle]
            if bundle_items isa Vector{Symbol}
                bundle = Set(bundle_items)
                if !isempty(bundle) && length(bundle) <= mechanism.max_bundle_size
                    push!(bundle_bids, BundleBid(bid, bundle))
                end
            end
        else
            # If no bundle specified, treat as single-item bid
            # Assume first item if quantity is 1
            if bid.quantity == 1 && !isempty(mechanism.items)
                bundle = Set([mechanism.items[1]])
                push!(bundle_bids, BundleBid(bid, bundle))
            end
        end
    end
    
    return bundle_bids
end

function finalizeCombinatorialAuction(state::AuctionState{T}) where T
    mechanism = CombinatorialAuction(
        items = get(state.metadata, :items, Symbol[:item1, :item2]),
        reserve_prices = get(state.metadata, :reserve_prices, Dict{Symbol, T}())
    )
    
    bundle_bids = convert_to_bundle_bids(mechanism, state.current_bids)
    winners, allocations_dict, payments = solve_winner_determination_problem(mechanism, bundle_bids)
    
    # Convert allocations to standard format
    allocations = Dict{UUID, T}()
    for (bidder_id, bundle) in allocations_dict
        allocations[bidder_id] = T(length(bundle))
    end
    
    clearing_price = determine_clearing_price(mechanism, state.current_bids)
    
    return AuctionResult{T}(
        state.auction_id,
        clearing_price,
        winners,
        allocations,
        payments,
        now(),
        Dict{Symbol, Any}(
            :auction_type => :combinatorial,
            :total_bids => length(state.current_bids),
            :total_bundles => length(bundle_bids),
            :items_allocated => sum(length(bundle) for bundle in values(allocations_dict)),
            :solver_status => :optimal
        )
    )
end