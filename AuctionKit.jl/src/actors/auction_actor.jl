# Auction actor implementation with Task-based concurrency
# Following A/HC/LC naming pattern

"""
    AuctionActor{T}

An actor that manages a single auction instance.
"""
mutable struct AuctionActor{T} <: AbstractActor{T}
    id::UUID
    state::AuctionState{T}
    mailbox::Channel{ActorMessage}
    event_log::Union{Nothing, CentralizedEventLog}
    task::Task
    running::Atomic{Bool}
    
    function AuctionActor{T}(
        state::AuctionState{T},
        event_log::Union{Nothing, CentralizedEventLog}=nothing
    ) where T
        actor = new{T}(
            state.auction_id,
            state,
            Channel{ActorMessage}(1000),
            event_log,
            Task(() -> nothing),
            Atomic{Bool}(true)
        )
        
        # Start actor task
        actor.task = @spawn run_actor_loop(actor)
        return actor
    end
end

# A/HC: create + AuctionActor
function create_auction_actor(
    auction_type::Symbol,
    params::Dict{Symbol, Any};
    event_log::Union{Nothing, CentralizedEventLog}=nothing
)::AuctionActor
    T = get(params, :numeric_type, Float64)
    
    state = AuctionState{T}(
        uuid4(),
        auction_type,
        :pending,
        Vector{Bid{T}}(),
        Dict{UUID, Bidder{T}}(),
        get(params, :start_time, now()),
        get(params, :end_time, now() + Dates.Hour(1)),
        ReentrantLock(),
        get(params, :reserve_price, zero(T)),
        get(params, :increment, one(T)),
        get(params, :clearing_rule, :first_price),
        get(params, :tie_breaking, :random),
        get(params, :max_quantity, typemax(Int)),
        nothing
    )
    
    actor = AuctionActor{T}(state, event_log)
    
    # Log auction creation
    if !isnothing(event_log)
        event = AuctionStartedEvent(
            uuid4(),
            state.auction_id,
            auction_type,
            state.start_time,
            state.end_time,
            params
        )
        append_event_to_log(event_log, state.auction_id, event)
    end
    
    return actor
end

# A/HC/LC: run + Actor + Loop
function run_actor_loop(actor::AuctionActor)
    while actor.running[]
        try
            msg = take!(actor.mailbox)  # Blocking receive
            process_actor_message(actor, msg)
        catch e
            if !(e isa Base.InvalidStateException)
                @error "Actor error" exception=e actor_id=actor.id
                handle_actor_error(actor, e)
            end
        end
    end
end

# A/HC/LC: process + Actor + Message
function process_actor_message(actor::AuctionActor, msg::ActorMessage)
    lock(actor.state.mutex) do
        if msg isa BidMessage
            handle_bid_submission(actor, msg)
        elseif msg isa FinalizeMessage
            handle_auction_finalization(actor, msg)
        elseif msg isa QueryMessage
            handle_state_query(actor, msg)
        elseif msg isa UpdateConfigMessage
            handle_config_update(actor, msg)
        elseif msg isa StateSnapshotMessage
            handle_snapshot_request(actor, msg)
        end
    end
end

# A/HC/LC: handle + Bid + Submission
function handle_bid_submission(actor::AuctionActor, msg::BidMessage)
    state = actor.state
    
    # Validate auction status
    if state.status != :active
        if !isnothing(actor.event_log)
            event = BidRejectedEvent(
                uuid4(),
                state.auction_id,
                msg.bidder_id,
                "Auction not active (status: $(state.status))",
                now()
            )
            append_event_to_log(actor.event_log, state.auction_id, event)
        end
        return BidResponse(false, uuid4(), "Auction not active", now())
    end
    
    # Check time constraints
    current_time = now()
    if current_time > state.end_time
        state.status = :finalizing
        if !isnothing(actor.event_log)
            event = BidRejectedEvent(
                uuid4(),
                state.auction_id,
                msg.bidder_id,
                "Auction has ended",
                now()
            )
            append_event_to_log(actor.event_log, state.auction_id, event)
        end
        return BidResponse(false, uuid4(), "Auction has ended", now())
    end
    
    # Validate bid amount
    if msg.amount < state.reserve_price
        if !isnothing(actor.event_log)
            event = BidRejectedEvent(
                uuid4(),
                state.auction_id,
                msg.bidder_id,
                "Bid below reserve price",
                now()
            )
            append_event_to_log(actor.event_log, state.auction_id, event)
        end
        return BidResponse(false, uuid4(), "Bid below reserve price", now())
    end
    
    # Create and store bid
    bid = Bid(msg.bidder_id, msg.amount, msg.quantity; metadata=msg.metadata)
    push!(state.current_bids, bid)
    
    # Log bid submission
    if !isnothing(actor.event_log)
        event = BidSubmittedEvent(
            uuid4(),
            state.auction_id,
            msg.bidder_id,
            msg.amount,
            msg.quantity,
            msg.timestamp,
            msg.metadata
        )
        append_event_to_log(actor.event_log, state.auction_id, event)
    end
    
    # Check if immediate clearing needed (e.g., Dutch auction)
    if should_clear_immediately(state)
        trigger_auction_clearing(actor)
    end
    
    return BidResponse(true, bid.id, "Bid accepted", now())
end

# A/HC/LC: handle + Auction + Finalization
function handle_auction_finalization(actor::AuctionActor, msg::FinalizeMessage)
    state = actor.state
    
    if state.status == :completed
        return  # Already finalized
    end
    
    state.status = :finalizing
    
    # Finalize based on auction type
    result = finalize_auction_by_type(state)
    state.result = result
    state.status = :completed
    
    # Log finalization
    if !isnothing(actor.event_log)
        event = AuctionFinalizedEvent(
            uuid4(),
            state.auction_id,
            result.clearing_price,
            result.winners,
            result.allocations,
            result.payments,
            now()
        )
        append_event_to_log(actor.event_log, state.auction_id, event)
    end
    
    return result
end

# A/HC/LC: should + Clear + Immediately
function should_clear_immediately(state::AuctionState)::Bool
    # Dutch auction clears when sufficient demand at current price
    if state.auction_type == :dutch
        total_quantity = sum(bid.quantity for bid in state.current_bids)
        return total_quantity >= state.max_quantity
    end
    return false
end

# A/HC/LC: trigger + Auction + Clearing
function trigger_auction_clearing(actor::AuctionActor)
    msg = FinalizeMessage(false, now())
    put!(actor.mailbox, msg)
end

# A/HC/LC: finalize + Auction + ByType
function finalize_auction_by_type(state::AuctionState{T}) where T
    if state.auction_type == :first_price
        return finalizeFirstPriceAuction(state)
    elseif state.auction_type == :second_price || state.auction_type == :vickrey
        return finalizeVickreyAuction(state)
    elseif state.auction_type == :dutch
        return finalizeDutchAuction(state)
    elseif state.auction_type == :english
        return finalizeEnglishAuction(state)
    else
        throw(ArgumentError("Unknown auction type: $(state.auction_type)"))
    end
end

# A/HC/LC: send + Message + ToActor
function send_message_to_actor(actor::AuctionActor, msg::ActorMessage)
    put!(actor.mailbox, msg)
end

# A/HC/LC: stop + Actor + Gracefully
function stop_actor_gracefully(actor::AuctionActor)
    actor.running[] = false
    close(actor.mailbox)
    wait(actor.task)
end

# A/HC/LC: handle + Actor + Error
function handle_actor_error(actor::AuctionActor, error::Exception)
    @error "Actor error occurred" actor_id=actor.id error=error
    
    # Log error event if possible
    if !isnothing(actor.event_log)
        try
            event = AuctionCancelledEvent(
                uuid4(),
                actor.state.auction_id,
                "Error: $(error)",
                now()
            )
            append_event_to_log(actor.event_log, actor.state.auction_id, event)
        catch
            # Ignore logging errors
        end
    end
    
    # Update state
    actor.state.status = :cancelled
end