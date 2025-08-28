"""
    AuctionVisualizer.jl

Comprehensive visualization module for auction simulations.
Provides graphs for different stages of the auction process.
"""

module AuctionVisualizer

using Plots
using StatsPlots
using DataFrames
using Statistics
using Dates
using ..AuctionSimulator
using ..AuctionSimulator: NumericStat, StatisticsDict

export plot_bid_progression, plot_revenue_efficiency, plot_winner_distribution
export plot_competition_analysis, plot_auction_comparison, plot_bidder_performance
export create_auction_dashboard, save_all_plots
export AuctionVisualizationData, collect_auction_data

# Data collection structure
struct AuctionVisualizationData
    auction_type::String
    rounds::Vector{Int}
    bids_history::Vector{Vector{Float64}}
    revenues::Vector{Float64}
    efficiencies::Vector{Float64}
    winners::Vector{Union{Int, Nothing}}
    winning_prices::Vector{Float64}
    bidder_valuations::Dict{Int, Vector{Float64}}
    bidder_bids::Dict{Int, Vector{Float64}}
    timestamps::Vector{DateTime}
    metadata::Dict{String, Any}
end

"""
    collect_auction_data(results::Vector{AuctionResult}, bidders::Vector{<:AbstractBidder})

Collect and organize auction data for visualization.
"""
function collect_auction_data(results::Vector{<:Any}, bidders::Vector{<:AbstractBidder})
    n_rounds = length(results)
    
    # Initialize collections
    rounds = collect(1:n_rounds)
    bids_history = Vector{Vector{Float64}}()
    revenues = Float64[]
    efficiencies = Float64[]
    winners = Union{Int, Nothing}[]
    winning_prices = Float64[]
    timestamps = DateTime[]
    
    # Bidder-specific data
    bidder_valuations = Dict{Int, Vector{Float64}}()
    bidder_bids = Dict{Int, Vector{Float64}}()
    
    for bidder in bidders
        bidder_id = get_id(bidder)
        bidder_valuations[bidder_id] = Float64[]
        bidder_bids[bidder_id] = Float64[]
    end
    
    # Process each auction result
    for (i, result) in enumerate(results)
        # Extract bid values for this round
        round_bids = [bid.value for bid in result.all_bids]
        push!(bids_history, round_bids)
        
        # Extract metrics
        push!(revenues, get(result.statistics, "revenue", NumericStat(0.0)).value)
        push!(efficiencies, get(result.statistics, "efficiency", NumericStat(0.0)).value)
        push!(winners, result.winner_id)
        push!(winning_prices, result.winning_price)
        push!(timestamps, now())
        
        # Track individual bidder data
        for bid in result.all_bids
            if haskey(bidder_bids, bid.bidder_id)
                push!(bidder_bids[bid.bidder_id], bid.value)
            end
        end
    end
    
    # Get auction type
    auction_type = length(results) > 0 ? string(typeof(results[1].auction_type)) : "Unknown"
    
    # Metadata
    metadata = Dict{String, Any}(
        "total_rounds" => n_rounds,
        "num_bidders" => length(bidders),
        "avg_revenue" => mean(revenues),
        "avg_efficiency" => mean(efficiencies),
        "unique_winners" => length(unique(filter(x -> x !== nothing, winners)))
    )
    
    return AuctionVisualizationData(
        auction_type,
        rounds,
        bids_history,
        revenues,
        efficiencies,
        winners,
        winning_prices,
        bidder_valuations,
        bidder_bids,
        timestamps,
        metadata
    )
end

"""
    plot_bid_progression(data::AuctionVisualizationData; kwargs...)

Plot the progression of bids over auction rounds.
Shows how bidding behavior changes throughout the simulation.
"""
function plot_bid_progression(data::AuctionVisualizationData; 
                             show_mean=true, 
                             show_range=true,
                             title="Bid Progression Over Auction Rounds")
    
    # Calculate statistics for each round
    mean_bids = [mean(bids) for bids in data.bids_history]
    max_bids = [maximum(bids) for bids in data.bids_history]
    min_bids = [minimum(bids) for bids in data.bids_history]
    
    p = plot(title=title,
             xlabel="Auction Round",
             ylabel="Bid Value",
             legend=:topright,
             grid=true,
             size=(800, 500))
    
    # Plot range if requested
    if show_range
        plot!(p, data.rounds, max_bids, 
              ribbon=(max_bids .- min_bids, zeros(length(max_bids))),
              fillalpha=0.2, 
              label="Bid Range",
              color=:blue)
    end
    
    # Plot mean if requested
    if show_mean
        plot!(p, data.rounds, mean_bids, 
              label="Mean Bid",
              color=:red,
              linewidth=2,
              marker=:circle,
              markersize=2)
    end
    
    # Add winning price line
    plot!(p, data.rounds, data.winning_prices,
          label="Winning Price",
          color=:green,
          linewidth=2,
          linestyle=:dash)
    
    return p
end

"""
    plot_revenue_efficiency(data::AuctionVisualizationData; kwargs...)

Plot revenue and efficiency metrics over time.
Shows dual y-axis plot with revenue on left and efficiency on right.
"""
function plot_revenue_efficiency(data::AuctionVisualizationData;
                               title="Revenue and Efficiency Analysis")
    
    # Create subplot for revenue
    p1 = plot(data.rounds, data.revenues,
              title=title,
              ylabel="Revenue",
              xlabel="",
              label="Revenue",
              color=:blue,
              linewidth=2,
              marker=:square,
              markersize=3,
              grid=true,
              legend=:topleft)
    
    # Add moving average
    if length(data.revenues) >= 10
        ma_window = 10
        ma_revenue = [mean(data.revenues[max(1,i-ma_window+1):i]) for i in 1:length(data.revenues)]
        plot!(p1, data.rounds, ma_revenue,
              label="10-Round MA",
              color=:navy,
              linewidth=2,
              linestyle=:dash)
    end
    
    # Create subplot for efficiency
    p2 = plot(data.rounds, data.efficiencies,
              ylabel="Efficiency",
              xlabel="Auction Round",
              label="Efficiency",
              color=:green,
              linewidth=2,
              marker=:circle,
              markersize=3,
              grid=true,
              legend=:bottomright,
              ylims=(0, 1.05))
    
    # Add efficiency threshold line
    hline!(p2, [0.9], 
           label="90% Threshold",
           color=:red,
           linestyle=:dash,
           linewidth=1)
    
    # Combine plots
    p = plot(p1, p2, layout=(2, 1), size=(800, 600))
    
    return p
end

"""
    plot_winner_distribution(data::AuctionVisualizationData; kwargs...)

Plot the distribution of auction winners.
Shows which bidders win most frequently.
"""
function plot_winner_distribution(data::AuctionVisualizationData;
                                title="Winner Distribution")
    
    # Count wins per bidder
    winner_counts = Dict{Int, Int}()
    for winner in data.winners
        if winner !== nothing
            winner_counts[winner] = get(winner_counts, winner, 0) + 1
        end
    end
    
    # Sort by bidder ID
    bidder_ids = sort(collect(keys(winner_counts)))
    win_counts = [winner_counts[id] for id in bidder_ids]
    
    # Create bar plot
    p = bar(bidder_ids, win_counts,
            title=title,
            xlabel="Bidder ID",
            ylabel="Number of Wins",
            label="Wins",
            color=:steelblue,
            size=(800, 500),
            xticks=bidder_ids)
    
    # Add win percentage annotations
    total_auctions = length(data.winners)
    for (i, (id, count)) in enumerate(zip(bidder_ids, win_counts))
        percentage = round(100 * count / total_auctions, digits=1)
        annotate!(p, id, count, 
                 text("$(percentage)%", :center, 8))
    end
    
    # Add average line
    avg_wins = mean(win_counts)
    hline!(p, [avg_wins], 
           label="Average",
           color=:red,
           linestyle=:dash,
           linewidth=2)
    
    return p
end

"""
    plot_competition_analysis(data::AuctionVisualizationData; kwargs...)

Analyze competition intensity through bid spread and participation.
"""
function plot_competition_analysis(data::AuctionVisualizationData;
                                 title="Competition Analysis")
    
    # Calculate competition metrics
    bid_spreads = Float64[]
    participation_rates = Float64[]
    avg_bids = Float64[]
    
    for bids in data.bids_history
        if length(bids) > 0
            push!(bid_spreads, maximum(bids) - minimum(bids))
            push!(avg_bids, mean(bids))
            # Assuming full participation for now
            push!(participation_rates, length(bids) / data.metadata["num_bidders"])
        end
    end
    
    # Create subplots
    p1 = plot(data.rounds[1:length(bid_spreads)], bid_spreads,
              title="Bid Spread (Competition Intensity)",
              ylabel="Spread",
              xlabel="",
              label="Max-Min Spread",
              color=:orange,
              linewidth=2,
              marker=:diamond,
              markersize=3,
              grid=true)
    
    p2 = scatter(avg_bids, bid_spreads,
                 title="Bid Amount vs Spread",
                 xlabel="Average Bid",
                 ylabel="Bid Spread",
                 label=nothing,
                 color=:purple,
                 alpha=0.6,
                 markersize=4,
                 grid=true)
    
    # Add trend line
    if length(avg_bids) > 1
        # Simple linear trend
        X = hcat(ones(length(avg_bids)), avg_bids)
        y = bid_spreads
        β = X \ y  # Least squares solution
        trend_line = β[1] .+ β[2] .* avg_bids
        plot!(p2, avg_bids, trend_line,
              label="Trend",
              color=:red,
              linewidth=2,
              linestyle=:dash)
    end
    
    p = plot(p1, p2, layout=(1, 2), size=(1000, 400))
    
    return p
end

"""
    plot_auction_comparison(data_list::Vector{AuctionVisualizationData}; kwargs...)

Compare multiple auction types side by side.
"""
function plot_auction_comparison(data_list::Vector{AuctionVisualizationData};
                               metrics=[:revenue, :efficiency],
                               title="Auction Type Comparison")
    
    # Prepare data for comparison
    auction_types = [d.auction_type for d in data_list]
    
    plots_array = []
    
    if :revenue in metrics
        avg_revenues = [mean(d.revenues) for d in data_list]
        std_revenues = [std(d.revenues) for d in data_list]
        
        p_rev = bar(1:length(auction_types), avg_revenues,
                    yerror=std_revenues,
                    title="Average Revenue",
                    ylabel="Revenue",
                    label=nothing,
                    color=:blue,
                    xticks=(1:length(auction_types), auction_types),
                    xrotation=45)
        push!(plots_array, p_rev)
    end
    
    if :efficiency in metrics
        avg_efficiencies = [mean(d.efficiencies) for d in data_list]
        std_efficiencies = [std(d.efficiencies) for d in data_list]
        
        p_eff = bar(1:length(auction_types), avg_efficiencies,
                    yerror=std_efficiencies,
                    title="Average Efficiency",
                    ylabel="Efficiency",
                    label=nothing,
                    color=:green,
                    ylims=(0, 1.1),
                    xticks=(1:length(auction_types), auction_types),
                    xrotation=45)
        push!(plots_array, p_eff)
    end
    
    if length(plots_array) > 1
        p = plot(plots_array..., layout=(1, length(plots_array)), 
                size=(400*length(plots_array), 400))
    else
        p = plots_array[1]
    end
    
    return p
end

"""
    plot_bidder_performance(data::AuctionVisualizationData, bidder_id::Int; kwargs...)

Analyze individual bidder performance over time.
"""
function plot_bidder_performance(data::AuctionVisualizationData, bidder_id::Int;
                               title="Bidder $bidder_id Performance")
    
    # Extract bidder-specific data
    bidder_bids = get(data.bidder_bids, bidder_id, Float64[])
    bidder_wins = [i for (i, w) in enumerate(data.winners) if w == bidder_id]
    
    if isempty(bidder_bids)
        return plot(title="No data for Bidder $bidder_id", 
                   grid=false, 
                   showaxis=false)
    end
    
    # Plot bid history
    p1 = plot(1:length(bidder_bids), bidder_bids,
              title=title,
              ylabel="Bid Value",
              xlabel="Round",
              label="Bids",
              color=:blue,
              linewidth=2,
              marker=:circle,
              markersize=3,
              grid=true)
    
    # Mark winning rounds
    if !isempty(bidder_wins)
        win_bids = [bidder_bids[w] for w in bidder_wins if w <= length(bidder_bids)]
        scatter!(p1, bidder_wins, win_bids,
                label="Wins",
                color=:gold,
                markersize=8,
                markershape=:star)
    end
    
    # Calculate win rate over time
    window_size = min(20, length(data.rounds) ÷ 5)
    win_rates = Float64[]
    
    for i in window_size:length(data.rounds)
        window_wins = count(w -> i - window_size < w <= i, bidder_wins)
        push!(win_rates, window_wins / window_size)
    end
    
    if !isempty(win_rates)
        p2 = plot(window_size:length(data.rounds), win_rates,
                 ylabel="Win Rate",
                 xlabel="Round",
                 label="$window_size-Round Win Rate",
                 color=:green,
                 linewidth=2,
                 grid=true,
                 ylims=(0, 1))
        
        p = plot(p1, p2, layout=(2, 1), size=(800, 600))
    else
        p = p1
    end
    
    return p
end

"""
    create_auction_dashboard(data::AuctionVisualizationData; kwargs...)

Create a comprehensive dashboard with multiple visualizations.
"""
function create_auction_dashboard(data::AuctionVisualizationData;
                                save_path=nothing)
    
    # Create individual plots
    p1 = plot_bid_progression(data, title="")
    p2 = plot_revenue_efficiency(data, title="")
    p3 = plot_winner_distribution(data, title="")
    p4 = plot_competition_analysis(data, title="")
    
    # Create dashboard layout
    dashboard = plot(p1, p2, p3, p4,
                    layout=(2, 2),
                    size=(1400, 900),
                    plot_title="Auction Simulation Dashboard - $(data.auction_type)",
                    plot_titlefontsize=14)
    
    # Save if path provided
    if save_path !== nothing
        savefig(dashboard, save_path)
        println("Dashboard saved to: $save_path")
    end
    
    return dashboard
end

"""
    save_all_plots(data::AuctionVisualizationData, output_dir::String)

Save all individual plots to files.
"""
function save_all_plots(data::AuctionVisualizationData, output_dir::String)
    # Create output directory if it doesn't exist
    mkpath(output_dir)
    
    # Generate timestamp for unique filenames
    timestamp = Dates.format(now(), "yyyymmdd_HHMMSS")
    
    # Save individual plots
    plots_to_save = [
        (plot_bid_progression(data), "bid_progression"),
        (plot_revenue_efficiency(data), "revenue_efficiency"),
        (plot_winner_distribution(data), "winner_distribution"),
        (plot_competition_analysis(data), "competition_analysis")
    ]
    
    for (plot, name) in plots_to_save
        filename = joinpath(output_dir, "$(name)_$(timestamp).png")
        savefig(plot, filename)
        println("Saved: $filename")
    end
    
    # Save dashboard
    dashboard = create_auction_dashboard(data)
    dashboard_file = joinpath(output_dir, "dashboard_$(timestamp).png")
    savefig(dashboard, dashboard_file)
    println("Saved dashboard: $dashboard_file")
end

end # module AuctionVisualizer