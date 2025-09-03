"""
    PriceImprovement

Calculate and track price improvements achieved through settlement optimization.
Compares auction prices with actual execution prices to measure value captured.

# Metrics
- Basis point improvement
- Dollar value improvement
- Improvement attribution (phantom auction, route optimization, etc.)
"""

struct PriceImprovementMetrics
    auction_price::Float64
    execution_price::Float64
    improvement_bps::Float64
    improvement_value::Float64
    volume::Float64
    attribution::Dict{Symbol, Float64}
end

"""
    calculate_improvement(auction_result, execution_result)

Calculate price improvement between auction and execution.

# Returns
- `PriceImprovementMetrics` with detailed improvement breakdown
"""
function calculate_improvement(auction_result, execution_result)
    auction_price = auction_result.winning_price
    execution_price = get(execution_result, :avg_price, auction_price)
    volume = get(execution_result, :volume, 0.0)
    
    # Calculate improvement
    if auction_price > 0
        improvement_bps = (auction_price - execution_price) / auction_price * 10000
    else
        improvement_bps = 0.0
    end
    
    improvement_value = (auction_price - execution_price) * volume
    
    # Attribution analysis
    attribution = analyze_attribution(auction_result, execution_result)
    
    return PriceImprovementMetrics(
        auction_price,
        execution_price,
        improvement_bps,
        improvement_value,
        volume,
        attribution
    )
end

"""
    analyze_attribution(auction_result, execution_result)

Attribute price improvement to different optimization components.

# Returns
- Dict mapping component to improvement contribution
"""
function analyze_attribution(auction_result, execution_result)
    attribution = Dict{Symbol, Float64}()
    
    # Phantom auction contribution
    phantom_improvement = get(execution_result, :phantom_improvement, 0.0)
    attribution[:phantom_auction] = phantom_improvement * 10000  # Convert to bps
    
    # Route optimization contribution
    route_optimization = get(execution_result, :route_optimization, 0.0)
    attribution[:route_optimization] = route_optimization * 10000
    
    # Multi-hop routing contribution
    multi_hop = get(execution_result, :multi_hop_benefit, 0.0)
    attribution[:multi_hop] = multi_hop * 10000
    
    # Timing optimization
    timing = get(execution_result, :timing_benefit, 0.0)
    attribution[:timing] = timing * 10000
    
    return attribution
end

"""
    aggregate_improvements(improvements::Vector{PriceImprovementMetrics})

Aggregate multiple improvement metrics for reporting.

# Returns
- Aggregated metrics including averages and totals
"""
function aggregate_improvements(improvements::Vector{PriceImprovementMetrics})
    if isempty(improvements)
        return nothing
    end
    
    total_volume = sum(m.volume for m in improvements)
    total_value = sum(m.improvement_value for m in improvements)
    
    # Volume-weighted average improvement
    weighted_improvement = sum(
        m.improvement_bps * m.volume for m in improvements
    ) / total_volume
    
    # Aggregate attribution
    attribution_totals = Dict{Symbol, Float64}()
    for metric in improvements
        for (component, value) in metric.attribution
            attribution_totals[component] = get(attribution_totals, component, 0.0) + 
                                           value * metric.volume / total_volume
        end
    end
    
    return (
        total_improvement_value = total_value,
        avg_improvement_bps = weighted_improvement,
        total_volume = total_volume,
        attribution = attribution_totals,
        num_settlements = length(improvements)
    )
end

"""
    PriceImprovementTracker

Tracks price improvement metrics over time.
"""
mutable struct PriceImprovementTracker
    metrics::Vector{PriceImprovementMetrics}
    window_size::Int
    summary_stats::Dict{Symbol, Float64}
    
    function PriceImprovementTracker(; window_size::Int = 1000)
        new(
            Vector{PriceImprovementMetrics}(),
            window_size,
            Dict{Symbol, Float64}(
                :total_value_captured => 0.0,
                :avg_improvement_bps => 0.0,
                :best_improvement_bps => 0.0,
                :improvement_rate => 0.0  # Percentage of trades with improvement
            )
        )
    end
end

"""
    record_improvement!(tracker, metrics)

Record new price improvement metrics and update summary statistics.
"""
function record_improvement!(
    tracker::PriceImprovementTracker,
    metrics::PriceImprovementMetrics
)
    push!(tracker.metrics, metrics)
    
    # Maintain window size
    if length(tracker.metrics) > tracker.window_size
        popfirst!(tracker.metrics)
    end
    
    # Update summary stats
    update_summary_stats!(tracker)
end

function update_summary_stats!(tracker::PriceImprovementTracker)
    if isempty(tracker.metrics)
        return
    end
    
    # Calculate summary statistics
    improvements = [m.improvement_bps for m in tracker.metrics]
    values = [m.improvement_value for m in tracker.metrics]
    
    tracker.summary_stats[:total_value_captured] = sum(values)
    tracker.summary_stats[:avg_improvement_bps] = mean(improvements)
    tracker.summary_stats[:best_improvement_bps] = maximum(improvements)
    
    # Calculate improvement rate (percentage with positive improvement)
    positive_improvements = count(x -> x > 0, improvements)
    tracker.summary_stats[:improvement_rate] = 
        positive_improvements / length(improvements) * 100
end

# Statistical helper (simplified - would use Statistics.jl in production)
function mean(values::Vector{Float64})
    isempty(values) ? 0.0 : sum(values) / length(values)
end