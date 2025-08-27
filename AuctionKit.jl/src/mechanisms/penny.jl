# Penny auction implementation
# Following A/HC/LC naming pattern

"""
    PennyAuction{T}

Pay-per-bid auction where each bid costs a fee and increases price by a small increment.
Common in online auction sites; combines elements of auctions and lotteries.
"""
mutable struct PennyAuction{T} <: OpenOutcryAuction{T}
    starting_price::T
    current_price::T
    bid_increment::T  # Price increase per bid (e.g., $0.01)
    bid_cost::T  # Cost to place a bid
    timer_increment::Float64  # Seconds added to timer per bid
    max_timer::Float64  # Maximum countdown timer in seconds
    current_timer::Float64  # Current countdown in seconds
    last_bid_time::DateTime
    current_leader::Union{Nothing, UUID}
    bid_history::Vector{Tuple{UUID, T, DateTime, T}}  # (bidder, price, time, cost_paid)
    total_bid_costs::Dict{UUID, T}  # Track total costs per bidder
    auto_bidding::Dict{UUID, T}  # Auto-bid limits per bidder
    
    function PennyAuction(;
        starting_price::T = zero(T),
        bid_increment::T = T(0.01),
        bid_cost::T = T(0.60),
        timer_increment::Float64 = 10.0,
        max_timer::Float64 = 30.0
    ) where T
        starting_price >= 0 || throw(ArgumentError("Starting price must be non-negative"))
        bid_increment > 0 || throw(ArgumentError("Bid increment must be positive"))
        bid_cost > 0 || throw(ArgumentError("Bid cost must be positive"))
        timer_increment > 0 || throw(ArgumentError("Timer increment must be positive"))
        max_timer > 0 || throw(ArgumentError("Maximum timer must be positive"))
        
        new{T}(
            starting_price,
            starting_price,
            bid_increment,
            bid_cost,
            timer_increment,
            max_timer,
            max_timer,
            now(),
            nothing,
            Vector{Tuple{UUID, T, DateTime, T}}(),
            Dict{UUID, T}(),
            Dict{UUID, T}()
        )
    end
end

function update_countdown_timer(mechanism::PennyAuction{T}) where T
    current_time = now()
    elapsed_seconds = (current_time - mechanism.last_bid_time).value / 1000.0
    
    mechanism.current_timer = max(0.0, mechanism.current_timer - elapsed_seconds)
    mechanism.last_bid_time = current_time
    
    return mechanism.current_timer
end

function isAuctionActive(mechanism::PennyAuction{T}) where T
    update_countdown_timer(mechanism)
    return mechanism.current_timer > 0
end

function placePennyBid(mechanism::PennyAuction{T}, bidder_id::UUID) where T
    if !isAuctionActive(mechanism)
        return false, "Auction has ended", zero(T)
    end
    
    # Update timer
    update_countdown_timer(mechanism)
    
    # Charge bid cost
    total_cost = get(mechanism.total_bid_costs, bidder_id, zero(T)) + mechanism.bid_cost
    mechanism.total_bid_costs[bidder_id] = total_cost
    
    # Increase auction price
    mechanism.current_price += mechanism.bid_increment
    
    # Update leader
    mechanism.current_leader = bidder_id
    
    # Reset and extend timer
    mechanism.current_timer = min(
        mechanism.current_timer + mechanism.timer_increment,
        mechanism.max_timer
    )
    mechanism.last_bid_time = now()
    
    # Record bid
    push!(mechanism.bid_history, (
        bidder_id,
        mechanism.current_price,
        mechanism.last_bid_time,
        mechanism.bid_cost
    ))
    
    return true, "Bid placed successfully", mechanism.bid_cost
end

function setupAutoBidding(
    mechanism::PennyAuction{T},
    bidder_id::UUID,
    max_spend::T
) where T
    if max_spend <= zero(T)
        delete!(mechanism.auto_bidding, bidder_id)
        return false, "Auto-bidding disabled"
    end
    
    mechanism.auto_bidding[bidder_id] = max_spend
    return true, "Auto-bidding enabled with limit $(max_spend)"
end

function processAutoBids(mechanism::PennyAuction{T}) where T
    if !isAuctionActive(mechanism)
        return
    end
    
    # Find bidders with auto-bid enabled who aren't current leader
    for (bidder_id, limit) in mechanism.auto_bidding
        if bidder_id == mechanism.current_leader
            continue
        end
        
        spent = get(mechanism.total_bid_costs, bidder_id, zero(T))
        if spent + mechanism.bid_cost <= limit
            # Place auto-bid
            placePennyBid(mechanism, bidder_id)
            break  # Only one auto-bid per round
        end
    end
end

function determine_clearing_price(mechanism::PennyAuction{T}, bids::Vector{Bid{T}}) where T
    # In penny auction, clearing price is final auction price
    if !isAuctionActive(mechanism)
        return mechanism.current_price
    else
        # Auction still active
        return mechanism.current_price
    end
end

function allocate_winners(
    mechanism::PennyAuction{T},
    bids::Vector{Bid{T}},
    clearing_price::T
) where T
    if isnothing(mechanism.current_leader) || isAuctionActive(mechanism)
        return UUID[], Dict{UUID, T}()
    end
    
    winners = [mechanism.current_leader]
    allocations = Dict{UUID, T}(mechanism.current_leader => one(T))
    
    return winners, allocations
end

function calculate_payments(
    mechanism::PennyAuction{T},
    winners::Vector{UUID},
    allocations::Dict{UUID, T},
    clearing_price::T
) where T
    payments = Dict{UUID, T}()
    
    # Winner pays final price plus all their bid costs
    for winner_id in winners
        bid_costs = get(mechanism.total_bid_costs, winner_id, zero(T))
        payments[winner_id] = clearing_price + bid_costs
    end
    
    # Losers pay only their bid costs (non-refundable)
    for (bidder_id, cost) in mechanism.total_bid_costs
        if bidder_id ∉ winners && cost > zero(T)
            payments[bidder_id] = cost
        end
    end
    
    return payments
end

function calculateRevenueStatistics(mechanism::PennyAuction{T}) where T
    total_bid_costs = sum(values(mechanism.total_bid_costs))
    num_bidders = length(mechanism.total_bid_costs)
    num_bids = length(mechanism.bid_history)
    
    avg_cost_per_bidder = num_bidders > 0 ? total_bid_costs / num_bidders : zero(T)
    revenue_from_bids = num_bids * mechanism.bid_cost
    
    return Dict{Symbol, Any}(
        :total_bid_costs => total_bid_costs,
        :revenue_from_bids => revenue_from_bids,
        :final_price => mechanism.current_price,
        :total_revenue => revenue_from_bids + mechanism.current_price,
        :num_bids => num_bids,
        :num_bidders => num_bidders,
        :avg_cost_per_bidder => avg_cost_per_bidder,
        :price_increase_ratio => mechanism.starting_price > 0 ? 
            mechanism.current_price / mechanism.starting_price : Inf
    )
end

function simulatePennyProcess(
    mechanism::PennyAuction{T},
    bids::Vector{Bid{T}}
) where T
    # Sort bids by timestamp
    sorted_bids = sort(bids, by=b -> b.timestamp)
    
    for bid in sorted_bids
        # Check if auction is still active
        if !isAuctionActive(mechanism)
            break
        end
        
        # Place bid (each bid in input represents intent to bid)
        placePennyBid(mechanism, bid.bidder_id)
        
        # Process any auto-bids
        processAutoBids(mechanism)
    end
    
    # Run timer down to completion
    while isAuctionActive(mechanism) && mechanism.current_timer > 0
        update_countdown_timer(mechanism)
        
        # In real system, this would wait for actual time to pass
        # For simulation, we just end when no more bids
        break
    end
end

function finalizePennyAuction(state::AuctionState{T}) where T
    mechanism = PennyAuction(
        starting_price = state.reserve_price,
        bid_increment = get(state.metadata, :bid_increment, T(0.01)),
        bid_cost = get(state.metadata, :bid_cost, T(0.60)),
        timer_increment = get(state.metadata, :timer_increment, 10.0),
        max_timer = get(state.metadata, :max_timer, 30.0)
    )
    
    # Simulate the penny auction process
    simulatePennyProcess(mechanism, state.current_bids)
    
    clearing_price = determine_clearing_price(mechanism, state.current_bids)
    winners, allocations = allocate_winners(mechanism, state.current_bids, clearing_price)
    payments = calculate_payments(mechanism, winners, allocations, clearing_price)
    
    # Calculate revenue statistics
    stats = calculateRevenueStatistics(mechanism)
    
    return AuctionResult{T}(
        state.auction_id,
        clearing_price,
        winners,
        allocations,
        payments,
        now(),
        merge(
            Dict{Symbol, Any}(
                :auction_type => :penny,
                :is_active => isAuctionActive(mechanism)
            ),
            stats
        )
    )
end