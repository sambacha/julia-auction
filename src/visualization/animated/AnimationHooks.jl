"""
AnimationHooks.jl - Event-driven animation system for auction simulations

This module provides a zero-code-change integration system that automatically
captures auction events and generates Makie animations without modifying
existing simulation code.
"""
module AnimationHooks

using Makie, GLMakie
using Observables
using ..AuctionSimulator
import ..AuctionSimulator: conduct_auction, determine_winner, calculate_payment, generate_bid

export AnimationContext, enable_animations!, disable_animations!, with_animation
export @animated, get_animation_data, replay_animation

# Global animation state
mutable struct AnimationState
    enabled::Bool
    recording::Bool
    events::Vector{NamedTuple}
    observables::Dict{Symbol,Observable}
    figures::Dict{Symbol,Figure}
    config::Dict{Symbol,Any}
end

const ANIMATION_STATE =
    AnimationState(false, false, NamedTuple[], Dict{Symbol,Observable}(), Dict{Symbol,Figure}(), Dict{Symbol,Any}())

"""
    AnimationContext

Context for managing animation state and configuration.
"""
struct AnimationContext
    enabled::Bool
    auto_record::Bool
    frame_rate::Int
    resolution::Tuple{Int,Int}
    output_format::Symbol
    theme::Symbol
end

function AnimationContext(;
    enabled::Bool = true,
    auto_record::Bool = false,
    frame_rate::Int = 30,
    resolution::Tuple{Int,Int} = (1200, 800),
    output_format::Symbol = :mp4,
    theme::Symbol = :default,
)
    AnimationContext(enabled, auto_record, frame_rate, resolution, output_format, theme)
end

"""
    enable_animations!(context::AnimationContext = AnimationContext())

Enable automatic animation capture for all auction simulations.
"""
function enable_animations!(context::AnimationContext = AnimationContext())
    ANIMATION_STATE.enabled = context.enabled
    ANIMATION_STATE.config[:context] = context

    # Initialize observables for auction data streams
    ANIMATION_STATE.observables[:bids] = Observable(Point2f[])
    ANIMATION_STATE.observables[:prices] = Observable(Float32[])
    ANIMATION_STATE.observables[:winners] = Observable(Int[])
    ANIMATION_STATE.observables[:efficiency] = Observable(Float32(0.0))
    ANIMATION_STATE.observables[:revenue] = Observable(Float32(0.0))
    ANIMATION_STATE.observables[:time] = Observable(0.0)

    # Create main dashboard figure if auto-display is enabled
    if get(ANIMATION_STATE.config, :auto_display, false)
        create_dashboard()
    end

    return nothing
end

"""
    disable_animations!()

Disable animation capture.
"""
function disable_animations!()
    ANIMATION_STATE.enabled = false
    ANIMATION_STATE.recording = false
    empty!(ANIMATION_STATE.events)
    return nothing
end

"""
    with_animation(f::Function, context::AnimationContext = AnimationContext())

Execute a function with animation capture enabled.
"""
function with_animation(f::Function, context::AnimationContext = AnimationContext())
    old_state = ANIMATION_STATE.enabled
    enable_animations!(context)
    try
        ANIMATION_STATE.recording = true
        result = f()
        ANIMATION_STATE.recording = false
        return result
    finally
        ANIMATION_STATE.enabled = old_state
    end
end

# Method interception for automatic event capture
"""
Intercept conduct_auction to capture auction events.
"""
function AuctionSimulator.conduct_auction(auction::AbstractAuction, bidders::Vector{<:AbstractBidder})
    if !ANIMATION_STATE.enabled
        # Call original implementation
        return invoke(conduct_auction, Tuple{AbstractAuction,Vector{<:AbstractBidder}}, auction, bidders)
    end

    # Capture pre-auction state
    record_event(
        :auction_start,
        (
            auction_type = typeof(auction),
            num_bidders = length(bidders),
            reserve_price = auction.reserve_price,
            timestamp = time(),
        ),
    )

    # Call original implementation
    result = invoke(conduct_auction, Tuple{AbstractAuction,Vector{<:AbstractBidder}}, auction, bidders)

    # Capture post-auction state
    record_event(
        :auction_end,
        (
            winner_id = result.winner_id,
            winning_price = result.winning_price,
            num_bids = length(result.all_bids),
            revenue = result.winning_price,
            timestamp = time(),
        ),
    )

    # Update observables for real-time visualization
    update_observables(result)

    return result
end

"""
Intercept determine_winner to capture winner determination events.
"""
function AuctionSimulator.determine_winner(bids::Vector{Bid}, auction::AbstractAuction)
    if !ANIMATION_STATE.enabled
        return invoke(determine_winner, Tuple{Vector{Bid},AbstractAuction}, bids, auction)
    end

    # Capture bid sorting and filtering
    record_event(
        :winner_determination_start,
        (num_bids = length(bids), reserve_price = auction.reserve_price, timestamp = time()),
    )

    # Call original implementation
    result = invoke(determine_winner, Tuple{Vector{Bid},AbstractAuction}, bids, auction)

    # Capture winner selection
    record_event(
        :winner_determined,
        (
            winner_id = result.winner_id,
            winning_bid = result.winning_bid !== nothing ? result.winning_bid.value : 0.0,
            timestamp = time(),
        ),
    )

    return result
end

"""
Intercept calculate_payment to capture payment calculation events.
"""
function AuctionSimulator.calculate_payment(winner_info, bids::Vector{Bid}, auction::AbstractAuction)
    if !ANIMATION_STATE.enabled
        return invoke(calculate_payment, Tuple{Any,Vector{Bid},AbstractAuction}, winner_info, bids, auction)
    end

    # Capture payment calculation start
    record_event(
        :payment_calculation_start,
        (auction_type = typeof(auction), num_bids = length(bids), timestamp = time()),
    )

    # Call original implementation
    payment = invoke(calculate_payment, Tuple{Any,Vector{Bid},AbstractAuction}, winner_info, bids, auction)

    # Capture payment result
    record_event(:payment_calculated, (payment = payment, auction_type = typeof(auction), timestamp = time()))

    return payment
end

"""
Intercept generate_bid to capture bidding events.
"""
function AuctionSimulator.generate_bid(strategy::AbstractBiddingStrategy, bidder::AbstractBidder, auction_state)
    if !ANIMATION_STATE.enabled
        return invoke(generate_bid, Tuple{AbstractBiddingStrategy,AbstractBidder,Any}, strategy, bidder, auction_state)
    end

    # Capture bid generation
    record_event(
        :bid_generation_start,
        (
            bidder_id = get_id(bidder),
            strategy_type = typeof(strategy),
            valuation = get_valuation(bidder),
            timestamp = time(),
        ),
    )

    # Call original implementation
    bid = invoke(generate_bid, Tuple{AbstractBiddingStrategy,AbstractBidder,Any}, strategy, bidder, auction_state)

    # Capture generated bid
    record_event(:bid_generated, (bidder_id = bid.bidder_id, bid_value = bid.value, timestamp = bid.timestamp))

    # Update bid observable for real-time animation
    if haskey(ANIMATION_STATE.observables, :bids)
        current_bids = ANIMATION_STATE.observables[:bids][]
        push!(current_bids, Point2f(bid.timestamp, bid.value))
        ANIMATION_STATE.observables[:bids][] = current_bids
    end

    return bid
end

# Event recording utilities
"""
    record_event(event_type::Symbol, data::NamedTuple)

Record an auction event for animation playback.
"""
function record_event(event_type::Symbol, data::NamedTuple)
    if ANIMATION_STATE.recording
        push!(ANIMATION_STATE.events, merge((event_type = event_type,), data))
    end
end

"""
    update_observables(result::AuctionResult)

Update observable values for real-time visualization.
"""
function update_observables(result::AuctionResult)
    if haskey(ANIMATION_STATE.observables, :prices)
        current_prices = ANIMATION_STATE.observables[:prices][]
        push!(current_prices, Float32(result.winning_price))
        ANIMATION_STATE.observables[:prices][] = current_prices
    end

    if haskey(ANIMATION_STATE.observables, :winners) && result.winner_id !== nothing
        current_winners = ANIMATION_STATE.observables[:winners][]
        push!(current_winners, result.winner_id)
        ANIMATION_STATE.observables[:winners][] = current_winners
    end

    if haskey(ANIMATION_STATE.observables, :revenue)
        ANIMATION_STATE.observables[:revenue][] = Float32(result.winning_price)
    end

    if haskey(ANIMATION_STATE.observables, :efficiency) && haskey(result.statistics, "efficiency")
        ANIMATION_STATE.observables[:efficiency][] = Float32(result.statistics["efficiency"].value)
    end
end

# Visualization creation
"""
    create_dashboard()

Create the main animated dashboard for auction visualization.
"""
function create_dashboard()
    fig = Figure(resolution = get(ANIMATION_STATE.config[:context], :resolution, (1200, 800)))

    # Bid evolution panel
    ax1 = Axis(fig[1, 1], title = "Real-time Bid Evolution", xlabel = "Time", ylabel = "Bid Value")

    # Animated scatter plot for bids
    scatter!(ax1, ANIMATION_STATE.observables[:bids], color = :blue, markersize = 10, alpha = 0.6)

    # Price convergence panel
    ax2 = Axis(fig[1, 2], title = "Price Discovery", xlabel = "Auction Round", ylabel = "Winning Price")

    # Animated line for price evolution
    prices_obs = @lift(begin
        prices = $(ANIMATION_STATE.observables[:prices])
        if !isempty(prices)
            Point2f.(1:length(prices), prices)
        else
            Point2f[]
        end
    end)
    lines!(ax2, prices_obs, color = :red, linewidth = 3)

    # Efficiency tracking panel
    ax3 = Axis(fig[2, 1], title = "Auction Efficiency", xlabel = "Time", ylabel = "Efficiency")

    # Animated efficiency indicator
    efficiency_history = Observable(Float32[])
    on(ANIMATION_STATE.observables[:efficiency]) do eff
        push!(efficiency_history[], eff)
        efficiency_history[] = efficiency_history[]  # Trigger update
    end

    lines!(ax3, efficiency_history, color = :green, linewidth = 2)
    hlines!(ax3, [1.0], color = :black, linestyle = :dash)  # Optimal efficiency line

    # Revenue metrics panel
    ax4 = Axis(fig[2, 2], title = "Revenue Metrics", xlabel = "Auction Round", ylabel = "Revenue")

    # Animated revenue bars
    revenue_history = Observable(Float32[])
    on(ANIMATION_STATE.observables[:revenue]) do rev
        push!(revenue_history[], rev)
        revenue_history[] = revenue_history[]  # Trigger update
    end

    barplot!(ax4, revenue_history, color = :orange)

    ANIMATION_STATE.figures[:dashboard] = fig

    # Display if interactive
    if get(ANIMATION_STATE.config, :display_live, true)
        display(fig)
    end

    return fig
end

"""
    get_animation_data()

Retrieve captured animation data.
"""
function get_animation_data()
    return (
        events = copy(ANIMATION_STATE.events),
        observables = Dict(k => v[] for (k, v) in ANIMATION_STATE.observables),
        config = copy(ANIMATION_STATE.config),
    )
end

"""
    replay_animation(; speed::Float64 = 1.0, output_file::Union{String, Nothing} = nothing)

Replay captured auction events as an animation.
"""
function replay_animation(; speed::Float64 = 1.0, output_file::Union{String,Nothing} = nothing)
    if isempty(ANIMATION_STATE.events)
        @warn "No events captured for animation"
        return nothing
    end

    # Create replay figure
    fig = create_dashboard()

    # Sort events by timestamp
    sorted_events = sort(ANIMATION_STATE.events, by = e -> get(e, :timestamp, 0.0))

    # Calculate time scaling
    start_time = sorted_events[1].timestamp
    end_time = sorted_events[end].timestamp
    duration = end_time - start_time

    if output_file !== nothing
        # Record animation to file
        framerate = get(ANIMATION_STATE.config[:context], :frame_rate, 30)
        record(fig, output_file, 1:Int(duration*framerate/speed)) do frame
            # Interpolate to current frame time
            current_time = start_time + (frame - 1) * speed / framerate
            replay_events_to_time(sorted_events, current_time)
        end
    else
        # Live playback
        @async begin
            for event in sorted_events
                replay_event(event)
                sleep((event.timestamp - start_time) / speed)
            end
        end
    end

    return fig
end

"""
    replay_event(event::NamedTuple)

Replay a single auction event.
"""
function replay_event(event::NamedTuple)
    # Update observables based on event type
    if event.event_type == :bid_generated
        # Add bid to visualization
        if haskey(ANIMATION_STATE.observables, :bids)
            current_bids = ANIMATION_STATE.observables[:bids][]
            push!(current_bids, Point2f(event.timestamp, event.bid_value))
            ANIMATION_STATE.observables[:bids][] = current_bids
        end
    elseif event.event_type == :winner_determined
        # Highlight winning bid
        if haskey(ANIMATION_STATE.observables, :winners) && event.winner_id !== nothing
            current_winners = ANIMATION_STATE.observables[:winners][]
            push!(current_winners, event.winner_id)
            ANIMATION_STATE.observables[:winners][] = current_winners
        end
    elseif event.event_type == :payment_calculated
        # Update revenue
        if haskey(ANIMATION_STATE.observables, :revenue)
            ANIMATION_STATE.observables[:revenue][] = Float32(event.payment)
        end
    end
end

"""
    replay_events_to_time(events::Vector{NamedTuple}, target_time::Float64)

Replay all events up to a specific timestamp.
"""
function replay_events_to_time(events::Vector{NamedTuple}, target_time::Float64)
    for event in events
        if get(event, :timestamp, 0.0) <= target_time
            replay_event(event)
        else
            break
        end
    end
end

# Macro for simplified animation wrapping
"""
    @animated expr

Macro to automatically wrap an expression with animation capture.
"""
macro animated(expr)
    quote
        with_animation() do
            $(esc(expr))
        end
    end
end

end # module AnimationHooks
