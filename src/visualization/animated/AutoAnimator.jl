"""
AutoAnimator.jl - Automatic animation injection system

This module provides automatic animation support for all simulations
without requiring any code changes. It uses Julia's module precompilation
and method extension features to transparently add animation capabilities.
"""
module AutoAnimator

using Requires
using ..AuctionSimulator
using Makie
using GLMakie
using Observables

export auto_animate, AnimationMode, get_current_animation

# Animation modes
@enum AnimationMode begin
    DISABLED = 0
    PASSIVE = 1      # Collect data but don't display
    INTERACTIVE = 2  # Display live animations
    RECORDING = 3    # Record to file
end

# Global configuration
mutable struct AutoAnimationConfig
    mode::AnimationMode
    auto_detect::Bool
    output_dir::String
    theme::Attributes
    dashboard_layout::Symbol  # :compact, :full, :minimal
    performance_mode::Bool    # Optimize for performance vs quality
end

const GLOBAL_CONFIG = AutoAnimationConfig(DISABLED, true, "animations", Attributes(), :full, false)

# Animation data collector
mutable struct AnimationCollector
    auction_states::Vector{NamedTuple}
    bid_streams::Dict{Int,Vector{Point2f}}
    price_evolution::Vector{Float64}
    efficiency_timeline::Vector{Float64}
    winner_distribution::Dict{Int,Int}
    current_figure::Union{Figure,Nothing}
    observables::Dict{Symbol,Observable}
end

const COLLECTOR = AnimationCollector(
    NamedTuple[],
    Dict{Int,Vector{Point2f}}(),
    Float64[],
    Float64[],
    Dict{Int,Int}(),
    nothing,
    Dict{Symbol,Observable}(),
)

"""
    auto_animate(mode::AnimationMode = INTERACTIVE; kwargs...)

Enable automatic animation for all auction simulations.

# Arguments
- `mode::AnimationMode`: Animation mode (DISABLED, PASSIVE, INTERACTIVE, RECORDING)

# Keyword Arguments
- `output_dir::String = "animations"`: Directory for saving animations
- `theme::Attributes = Attributes()`: Makie theme for visualizations
- `dashboard_layout::Symbol = :full`: Dashboard layout (:compact, :full, :minimal)
- `performance_mode::Bool = false`: Optimize for performance
- `auto_detect::Bool = true`: Automatically detect simulation starts

# Examples
```julia
# Enable interactive animations
auto_animate(INTERACTIVE)

# Enable recording mode
auto_animate(RECORDING, output_dir="my_animations")

# Run simulation - animations will be generated automatically
result = run_simulation(auction, bidders, config)
```
"""
function auto_animate(mode::AnimationMode = INTERACTIVE; kwargs...)
    GLOBAL_CONFIG.mode = mode

    # Update configuration
    for (key, value) in kwargs
        if hasfield(typeof(GLOBAL_CONFIG), key)
            setfield!(GLOBAL_CONFIG, key, value)
        end
    end

    # Set up method extensions if not disabled
    if mode != DISABLED
        inject_animation_hooks()

        # Create output directory if in recording mode
        if mode == RECORDING && !isdir(GLOBAL_CONFIG.output_dir)
            mkpath(GLOBAL_CONFIG.output_dir)
        end

        # Initialize dashboard if interactive
        if mode == INTERACTIVE
            initialize_dashboard()
        end
    end

    return nothing
end

"""
    inject_animation_hooks()

Inject animation hooks into auction methods using method extension.
"""
function inject_animation_hooks()
    # Extend run_simulation to capture simulation lifecycle
    @eval AuctionSimulator begin
        const _original_run_simulation = run_simulation

        function run_simulation(auction_type, bidders, config::AuctionConfig)
            if AutoAnimator.GLOBAL_CONFIG.mode != AutoAnimator.DISABLED
                AutoAnimator.on_simulation_start(auction_type, bidders, config)
            end

            result = _original_run_simulation(auction_type, bidders, config)

            if AutoAnimator.GLOBAL_CONFIG.mode != AutoAnimator.DISABLED
                AutoAnimator.on_simulation_end(result)
            end

            return result
        end
    end

    # Extend conduct_auction to capture auction events
    @eval AuctionSimulator begin
        const _original_conduct_auction = conduct_auction

        function conduct_auction(auction::AbstractAuction, bidders::Vector{<:AbstractBidder})
            if AutoAnimator.GLOBAL_CONFIG.mode != AutoAnimator.DISABLED
                AutoAnimator.on_auction_start(auction, bidders)
            end

            result = _original_conduct_auction(auction, bidders)

            if AutoAnimator.GLOBAL_CONFIG.mode != AutoAnimator.DISABLED
                AutoAnimator.on_auction_end(auction, result)
            end

            return result
        end
    end

    # Extend generate_bid to capture bidding dynamics
    @eval AuctionSimulator begin
        const _original_generate_bid = generate_bid

        function generate_bid(strategy::AbstractBiddingStrategy, bidder::AbstractBidder, auction_state)
            bid = _original_generate_bid(strategy, bidder, auction_state)

            if AutoAnimator.GLOBAL_CONFIG.mode != AutoAnimator.DISABLED
                AutoAnimator.on_bid_generated(bidder, bid)
            end

            return bid
        end
    end
end

# Event handlers
"""
    on_simulation_start(auction_type, bidders, config)

Handle simulation start event.
"""
function on_simulation_start(auction_type, bidders, config)
    # Reset collector
    empty!(COLLECTOR.auction_states)
    empty!(COLLECTOR.bid_streams)
    empty!(COLLECTOR.price_evolution)
    empty!(COLLECTOR.efficiency_timeline)
    empty!(COLLECTOR.winner_distribution)

    # Initialize observables
    COLLECTOR.observables[:current_round] = Observable(0)
    COLLECTOR.observables[:total_revenue] = Observable(0.0)
    COLLECTOR.observables[:avg_efficiency] = Observable(0.0)
    COLLECTOR.observables[:bid_count] = Observable(0)

    # Log start
    push!(
        COLLECTOR.auction_states,
        (
            event = :simulation_start,
            timestamp = time(),
            auction_type = string(typeof(auction_type)),
            num_bidders = length(bidders),
            num_rounds = config.num_rounds,
        ),
    )

    # Update dashboard if interactive
    if GLOBAL_CONFIG.mode == INTERACTIVE && COLLECTOR.current_figure !== nothing
        update_dashboard_title("Simulation Starting...")
    end
end

"""
    on_simulation_end(result)

Handle simulation end event.
"""
function on_simulation_end(result::SimulationResult)
    push!(
        COLLECTOR.auction_states,
        (
            event = :simulation_end,
            timestamp = time(),
            total_revenue = sum(result.revenues),
            avg_efficiency = mean(result.efficiencies),
            winner_distribution = result.bidder_wins,
        ),
    )

    # Generate final visualization
    if GLOBAL_CONFIG.mode == RECORDING
        save_animation(result)
    elseif GLOBAL_CONFIG.mode == INTERACTIVE
        finalize_dashboard(result)
    end
end

"""
    on_auction_start(auction, bidders)

Handle auction start event.
"""
function on_auction_start(auction::AbstractAuction, bidders::Vector{<:AbstractBidder})
    current_round = get(COLLECTOR.observables, :current_round, Observable(0))
    current_round[] += 1

    push!(
        COLLECTOR.auction_states,
        (
            event = :auction_start,
            timestamp = time(),
            round = current_round[],
            reserve_price = auction.reserve_price,
            num_bidders = length(bidders),
        ),
    )

    # Clear bid streams for new auction
    for bidder in bidders
        COLLECTOR.bid_streams[get_id(bidder)] = Point2f[]
    end
end

"""
    on_auction_end(auction, result)

Handle auction end event.
"""
function on_auction_end(auction::AbstractAuction, result::AuctionResult)
    # Collect auction outcome data
    push!(COLLECTOR.price_evolution, result.winning_price)

    if haskey(result.statistics, "efficiency")
        push!(COLLECTOR.efficiency_timeline, result.statistics["efficiency"].value)
    end

    if result.winner_id !== nothing
        COLLECTOR.winner_distribution[result.winner_id] = get(COLLECTOR.winner_distribution, result.winner_id, 0) + 1
    end

    # Update observables for live animation
    if GLOBAL_CONFIG.mode == INTERACTIVE
        update_live_dashboard(result)
    end

    push!(
        COLLECTOR.auction_states,
        (
            event = :auction_end,
            timestamp = time(),
            winner = result.winner_id,
            price = result.winning_price,
            efficiency = get(result.statistics, "efficiency", nothing),
        ),
    )
end

"""
    on_bid_generated(bidder, bid)

Handle bid generation event.
"""
function on_bid_generated(bidder::AbstractBidder, bid::Bid)
    # Store bid in stream
    bidder_id = get_id(bidder)
    if !haskey(COLLECTOR.bid_streams, bidder_id)
        COLLECTOR.bid_streams[bidder_id] = Point2f[]
    end

    push!(COLLECTOR.bid_streams[bidder_id], Point2f(time(), bid.value))

    # Update bid counter
    if haskey(COLLECTOR.observables, :bid_count)
        COLLECTOR.observables[:bid_count][] += 1
    end

    # Animate bid in real-time if interactive
    if GLOBAL_CONFIG.mode == INTERACTIVE && COLLECTOR.current_figure !== nothing
        animate_bid(bidder_id, bid)
    end
end

# Dashboard creation and updates
"""
    initialize_dashboard()

Create the live animation dashboard.
"""
function initialize_dashboard()
    layout = GLOBAL_CONFIG.dashboard_layout

    resolution = layout == :compact ? (800, 600) : layout == :minimal ? (600, 400) : (1400, 900)

    fig = Figure(resolution = resolution)

    if layout == :minimal
        # Single panel view
        ax = Axis(fig[1, 1], title = "Auction Progress")
        COLLECTOR.observables[:main_axis] = ax
    else
        # Multi-panel dashboard
        create_full_dashboard(fig)
    end

    COLLECTOR.current_figure = fig
    display(fig)

    return fig
end

"""
    create_full_dashboard(fig::Figure)

Create a comprehensive dashboard layout.
"""
function create_full_dashboard(fig::Figure)
    # Bid evolution panel
    ax1 = Axis(fig[1, 1], title = "Live Bid Streams", xlabel = "Time", ylabel = "Bid Value")
    COLLECTOR.observables[:bid_axis] = ax1

    # Price discovery panel
    ax2 = Axis(fig[1, 2], title = "Price Evolution", xlabel = "Round", ylabel = "Winning Price")

    # Observable for price line
    price_points = @lift begin
        prices = COLLECTOR.price_evolution
        isempty(prices) ? Point2f[] : Point2f.(1:length(prices), prices)
    end
    lines!(ax2, price_points, color = :red, linewidth = 3)
    COLLECTOR.observables[:price_axis] = ax2

    # Efficiency tracking
    ax3 = Axis(
        fig[2, 1],
        title = "Efficiency Over Time",
        xlabel = "Round",
        ylabel = "Efficiency",
        limits = (nothing, nothing, 0, 1.1),
    )

    efficiency_points = @lift begin
        effs = COLLECTOR.efficiency_timeline
        isempty(effs) ? Point2f[] : Point2f.(1:length(effs), effs)
    end
    lines!(ax3, efficiency_points, color = :green, linewidth = 2)
    hlines!(ax3, [1.0], color = :black, linestyle = :dash, alpha = 0.3)
    COLLECTOR.observables[:efficiency_axis] = ax3

    # Winner distribution
    ax4 = Axis(fig[2, 2], title = "Winner Distribution", xlabel = "Bidder ID", ylabel = "Wins")
    COLLECTOR.observables[:winner_axis] = ax4

    # Statistics panel
    if GLOBAL_CONFIG.dashboard_layout == :full
        stats_box = fig[3, :] = GridLayout()
        create_statistics_panel(stats_box)
    end
end

"""
    create_statistics_panel(layout::GridLayout)

Create a statistics display panel.
"""
function create_statistics_panel(layout::GridLayout)
    # Current round indicator
    round_label = Label(layout[1, 1], @lift("Round: $(COLLECTOR.observables[:current_round][])"))

    # Total revenue
    revenue_label =
        Label(layout[1, 2], @lift("Total Revenue: \$$(round(COLLECTOR.observables[:total_revenue][], digits=2))"))

    # Average efficiency
    efficiency_label =
        Label(layout[1, 3], @lift("Avg Efficiency: $(round(COLLECTOR.observables[:avg_efficiency][], digits=3))"))

    # Bid counter
    bid_label = Label(layout[1, 4], @lift("Total Bids: $(COLLECTOR.observables[:bid_count][])"))
end

"""
    update_live_dashboard(result::AuctionResult)

Update the dashboard with new auction results.
"""
function update_live_dashboard(result::AuctionResult)
    # Update revenue
    if haskey(COLLECTOR.observables, :total_revenue)
        COLLECTOR.observables[:total_revenue][] += result.winning_price
    end

    # Update average efficiency
    if haskey(COLLECTOR.observables, :avg_efficiency) && !isempty(COLLECTOR.efficiency_timeline)
        COLLECTOR.observables[:avg_efficiency][] = mean(COLLECTOR.efficiency_timeline)
    end

    # Update winner distribution plot
    if haskey(COLLECTOR.observables, :winner_axis)
        ax = COLLECTOR.observables[:winner_axis]
        empty!(ax)

        if !isempty(COLLECTOR.winner_distribution)
            bidder_ids = collect(keys(COLLECTOR.winner_distribution))
            wins = collect(values(COLLECTOR.winner_distribution))
            barplot!(ax, bidder_ids, wins, color = :orange)
        end
    end
end

"""
    animate_bid(bidder_id::Int, bid::Bid)

Animate a single bid on the dashboard.
"""
function animate_bid(bidder_id::Int, bid::Bid)
    if haskey(COLLECTOR.observables, :bid_axis)
        ax = COLLECTOR.observables[:bid_axis]

        # Add bid point with animation
        scatter!(ax, [Point2f(time(), bid.value)], color = :blue, markersize = 15, alpha = 0.6)
    end
end

"""
    update_dashboard_title(title::String)

Update the dashboard title.
"""
function update_dashboard_title(title::String)
    if COLLECTOR.current_figure !== nothing
        COLLECTOR.current_figure.content[1].title = title
    end
end

"""
    finalize_dashboard(result::SimulationResult)

Finalize the dashboard after simulation completion.
"""
function finalize_dashboard(result::SimulationResult)
    update_dashboard_title("Simulation Complete - $(result.auction_type)")

    # Add summary statistics
    if COLLECTOR.current_figure !== nothing
        fig = COLLECTOR.current_figure

        summary_text = """
        Total Rounds: $(result.config.num_rounds)
        Total Revenue: \$$(round(sum(result.revenues), digits=2))
        Avg Efficiency: $(round(mean(result.efficiencies), digits=3))
        Runtime: $(round(result.total_time, digits=2))s
        """

        Label(fig[end+1, :], summary_text, fontsize = 12)
    end
end

"""
    save_animation(result::SimulationResult)

Save the animation to a file.
"""
function save_animation(result::SimulationResult)
    timestamp = Dates.format(Dates.now(), "yyyymmdd_HHMMSS")
    filename = joinpath(GLOBAL_CONFIG.output_dir, "auction_$(result.auction_type)_$(timestamp).mp4")

    # Create animation from collected data
    fig = initialize_dashboard()

    # Replay events as animation
    framerate = 30
    frames = length(COLLECTOR.auction_states)

    record(fig, filename, 1:frames, framerate = framerate) do frame
        # Replay events up to this frame
        replay_to_frame(frame)
    end

    println("Animation saved to: $filename")
end

"""
    replay_to_frame(frame::Int)

Replay animation to a specific frame.
"""
function replay_to_frame(frame::Int)
    if frame <= length(COLLECTOR.auction_states)
        state = COLLECTOR.auction_states[frame]

        # Update visualization based on state
        if state.event == :auction_end
            # Update price evolution
            if haskey(COLLECTOR.observables, :price_axis)
                # Price data is already accumulated
            end
        end
    end
end

"""
    get_current_animation()

Get the current animation figure and data.
"""
function get_current_animation()
    return (
        figure = COLLECTOR.current_figure,
        data = (
            states = COLLECTOR.auction_states,
            bids = COLLECTOR.bid_streams,
            prices = COLLECTOR.price_evolution,
            efficiency = COLLECTOR.efficiency_timeline,
            winners = COLLECTOR.winner_distribution,
        ),
        config = GLOBAL_CONFIG,
    )
end

# Initialize on module load
function __init__()
    # Check for environment variable to auto-enable
    if haskey(ENV, "JULIA_AUCTION_ANIMATE")
        mode = get(ENV, "JULIA_AUCTION_ANIMATE", "interactive")
        if mode == "passive"
            auto_animate(PASSIVE)
        elseif mode == "recording"
            auto_animate(RECORDING)
        elseif mode == "interactive"
            auto_animate(INTERACTIVE)
        end
    end
end

end # module AutoAnimator
