# Double auction implementation
# Following A/HC/LC naming pattern

"""
    SealedBidDoubleAuction{T}

Double auction where buyers and sellers submit sealed bids.
Matches buyers and sellers to maximize total surplus.
"""
struct SealedBidDoubleAuction{T} <: SealedBidAuction{T}
    max_quantity::Int
    price_rule::Symbol  # :uniform, :discriminatory, :vickrey, :mcafee
    tie_breaking::Symbol
    min_spread::T  # Minimum spread between bid and ask
    
    function SealedBidDoubleAuction(;
        max_quantity::Int = typemax(Int),
        price_rule::Symbol = :uniform,
        tie_breaking::Symbol = :random,
        min_spread::T = zero(T)
    ) where T
        max_quantity >= 1 || throw(ArgumentError("Max quantity must be at least 1"))
        price_rule in [:uniform, :discriminatory, :vickrey, :mcafee] ||
            throw(ArgumentError("Invalid price rule"))
        tie_breaking in [:random, :first_come, :proportional] ||
            throw(ArgumentError("Invalid tie-breaking rule"))
        min_spread >= 0 || throw(ArgumentError("Minimum spread must be non-negative"))
        
        new{T}(max_quantity, price_rule, tie_breaking, min_spread)
    end
end

"""
    Order{T}

Represents a buy or sell order in a double auction.
"""
struct Order{T}
    bid::Bid{T}
    is_buy::Bool  # true for buy order, false for sell order
    
    function Order(bid::Bid{T}, is_buy::Bool) where T
        new{T}(bid, is_buy)
    end
end

function match_orders(
    buy_orders::Vector{Order{T}},
    sell_orders::Vector{Order{T}},
    mechanism::SealedBidDoubleAuction{T}
) where T
    if isempty(buy_orders) || isempty(sell_orders)
        return Tuple{UUID, UUID, T, Int}[]
    end
    
    # Sort buy orders descending by price, sell orders ascending by price
    sorted_buys = sort(buy_orders, by=o -> o.bid.amount, rev=true)
    sorted_sells = sort(sell_orders, by=o -> o.bid.amount)
    
    matches = Tuple{UUID, UUID, T, Int}[]  # (buyer_id, seller_id, price, quantity)
    remaining_quantity = mechanism.max_quantity
    
    buy_idx = 1
    sell_idx = 1
    
    while buy_idx <= length(sorted_buys) && 
          sell_idx <= length(sorted_sells) && 
          remaining_quantity > 0
        
        buy_order = sorted_buys[buy_idx]
        sell_order = sorted_sells[sell_idx]
        
        # Check if trade is feasible (bid >= ask + min_spread)
        if buy_order.bid.amount >= sell_order.bid.amount + mechanism.min_spread
            # Determine trade quantity
            buy_qty = buy_order.bid.quantity
            sell_qty = sell_order.bid.quantity
            trade_qty = min(buy_qty, sell_qty, remaining_quantity)
            
            # Determine trade price based on price rule
            trade_price = determineTradePrice(
                buy_order.bid.amount,
                sell_order.bid.amount,
                mechanism.price_rule
            )
            
            # Record match
            push!(matches, (
                buy_order.bid.bidder_id,
                sell_order.bid.bidder_id,
                trade_price,
                trade_qty
            ))
            
            remaining_quantity -= trade_qty
            
            # Update quantities and move to next order if exhausted
            if buy_qty == trade_qty
                buy_idx += 1
            else
                # Partially filled - create modified order
                sorted_buys[buy_idx] = Order(
                    Bid(buy_order.bid.bidder_id, buy_order.bid.amount, buy_qty - trade_qty),
                    true
                )
            end
            
            if sell_qty == trade_qty
                sell_idx += 1
            else
                # Partially filled - create modified order
                sorted_sells[sell_idx] = Order(
                    Bid(sell_order.bid.bidder_id, sell_order.bid.amount, sell_qty - trade_qty),
                    false
                )
            end
        else
            # No more feasible trades
            break
        end
    end
    
    return matches
end

function determineTradePrice(buy_price::T, sell_price::T, price_rule::Symbol) where T
    if price_rule == :uniform
        # Uniform price: average of bid and ask
        return (buy_price + sell_price) / 2
    elseif price_rule == :discriminatory
        # Discriminatory: each pays/receives their bid/ask
        return buy_price  # Buyer pays bid, seller receives ask
    elseif price_rule == :vickrey
        # Vickrey: second-price logic
        return sell_price  # Trade at seller's ask (truthful for buyer)
    elseif price_rule == :mcafee
        # McAfee: trade at price that maximizes efficiency
        return (buy_price + sell_price) / 2  # Simplified version
    else
        return (buy_price + sell_price) / 2
    end
end

function determine_clearing_price(mechanism::SealedBidDoubleAuction{T},
    bids::Vector{Bid{T}}) where T
    buy_orders, sell_orders = separate_buy_and_sell_orders(bids)
    
    if isempty(buy_orders) || isempty(sell_orders)
        return zero(T)
    end
    
    matches = match_orders(buy_orders, sell_orders, mechanism)
    
    if isempty(matches)
        return zero(T)
    end
    
    # Return average trade price as clearing price
    return T(sum(m[3] for m in matches) / length(matches))
end

function allocate_winners(
    mechanism::SealedBidDoubleAuction{T},
    bids::Vector{Bid{T}},
    clearing_price::T
) where T
    buy_orders, sell_orders = separate_buy_and_sell_orders(bids)
    matches = match_orders(buy_orders, sell_orders, mechanism)
    
    winners = UUID[]
    allocations = Dict{UUID, T}()
    
    for (buyer_id, seller_id, _, quantity) in matches
        # Both buyer and seller are "winners"
        if buyer_id ∉ winners
            push!(winners, buyer_id)
            allocations[buyer_id] = zero(T)
        end
        if seller_id ∉ winners
            push!(winners, seller_id)
            allocations[seller_id] = zero(T)
        end
        
        # Positive for buyers, negative for sellers (to indicate direction)
        allocations[buyer_id] += T(quantity)
        allocations[seller_id] -= T(quantity)
    end
    
    return winners, allocations
end

function calculate_payments(
    mechanism::SealedBidDoubleAuction{T},
    winners::Vector{UUID},
    allocations::Dict{UUID, T},
    clearing_price::T
) where T
    # Need to recalculate based on actual matches
    # This is simplified - would need access to original bids
    payments = Dict{UUID, T}()
    
    for (bidder_id, allocation) in allocations
        if allocation > 0
            # Buyer pays
            payments[bidder_id] = clearing_price * allocation
        else
            # Seller receives (negative payment = receipt)
            payments[bidder_id] = clearing_price * allocation
        end
    end
    
    return payments
end

function separate_buy_and_sell_orders(bids::Vector{Bid{T}}) where T
    buy_orders = Order{T}[]
    sell_orders = Order{T}[]
    
    for bid in bids
        # Check metadata for order type
        is_buy = get(bid.metadata, :is_buy, true)
        
        if is_buy
            push!(buy_orders, Order(bid, true))
        else
            push!(sell_orders, Order(bid, false))
        end
    end
    
    return buy_orders, sell_orders
end

function finalizeDoubleAuction(state::AuctionState{T}) where T
    mechanism = SealedBidDoubleAuction(
        max_quantity = get(state.max_quantity, typemax(Int)),
        price_rule = get(state.metadata, :price_rule, :uniform)
    )
    
    buy_orders, sell_orders = separate_buy_and_sell_orders(state.current_bids)
    matches = match_orders(buy_orders, sell_orders, mechanism)
    
    winners = UUID[]
    allocations = Dict{UUID, T}()
    payments = Dict{UUID, T}()
    
    total_volume = zero(T)
    total_surplus = zero(T)
    
    for (buyer_id, seller_id, price, quantity) in matches
        # Record winners
        if buyer_id ∉ winners
            push!(winners, buyer_id)
        end
        if seller_id ∉ winners
            push!(winners, seller_id)
        end
        
        # Record allocations
        allocations[buyer_id] = get(allocations, buyer_id, zero(T)) + T(quantity)
        allocations[seller_id] = get(allocations, seller_id, zero(T)) + T(quantity)
        
        # Record payments
        payments[buyer_id] = get(payments, buyer_id, zero(T)) + price * T(quantity)
        payments[seller_id] = get(payments, seller_id, zero(T)) - price * T(quantity)
        
        total_volume += T(quantity)
        
        # Calculate surplus (for efficiency metrics)
        buy_bid = findfirst(o -> o.bid.bidder_id == buyer_id, buy_orders)
        sell_bid = findfirst(o -> o.bid.bidder_id == seller_id, sell_orders)
        if !isnothing(buy_bid) && !isnothing(sell_bid)
            total_surplus += (buy_orders[buy_bid].bid.amount - sell_orders[sell_bid].bid.amount) * T(quantity)
        end
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
            :auction_type => :double,
            :total_bids => length(state.current_bids),
            :buy_orders => length(buy_orders),
            :sell_orders => length(sell_orders),
            :matches => length(matches),
            :total_volume => total_volume,
            :total_surplus => total_surplus
        )
    )
end