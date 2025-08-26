module PriceImprovement

using Statistics
using LinearAlgebra

export PriceImprovementCalculator, ImprovementMetrics, ValueAttribution
export calculate_improvement, validate_improvement_bounds, attribute_value
export get_improvement_metrics, update_baseline, calculate_surplus

# Price improvement metrics
struct ImprovementMetrics
    baseline_price::Float64
    improved_price::Float64
    improvement_bps::Float64  # Basis points
    improvement_amount::Float64  # Absolute improvement
    improvement_percentage::Float64
    trade_size::Float64
    value_created::Float64  # Total value created by improvement
    timestamp::Float64
end

# Value attribution for different parties
struct ValueAttribution
    user_value::Float64  # Value accrued to user
    protocol_value::Float64  # Value captured by protocol
    solver_value::Float64  # Value for solver/market maker
    mev_protection_value::Float64  # Value from MEV protection
    total_value::Float64
    user_share::Float64  # Percentage to user
    protocol_share::Float64
    solver_share::Float64
end

# Historical data for baseline calculation
mutable struct BaselineHistory
    prices::Vector{Float64}
    volumes::Vector{Float64}
    timestamps::Vector{Float64}
    max_size::Int
end

# Main calculator for price improvements
mutable struct PriceImprovementCalculator
    min_improvement_bps::Float64  # Minimum improvement threshold
    max_improvement_bps::Float64  # Maximum improvement cap
    protocol_fee_bps::Float64  # Protocol fee in basis points
    solver_incentive_bps::Float64  # Solver incentive
    mev_protection_threshold::Float64  # MEV protection trigger
    baseline_history::Dict{Tuple{Int,Int},BaselineHistory}
    improvement_history::Vector{ImprovementMetrics}
    attribution_config::Dict{Symbol,Float64}
end

"""
    PriceImprovementCalculator(; kwargs...)

Create a price improvement calculator with configurable bounds.
"""
function PriceImprovementCalculator(;
    min_improvement_bps::Float64=10.0,  # 0.1%
    max_improvement_bps::Float64=50.0,  # 0.5%
    protocol_fee_bps::Float64=5.0,  # 0.05%
    solver_incentive_bps::Float64=2.0,  # 0.02%
    mev_protection_threshold::Float64=100.0,  # 1% triggers MEV protection
    history_size::Int=1000)
    
    attribution_config = Dict{Symbol,Float64}(
        :user_min_share => 0.8,  # User gets at least 80% of improvement
        :protocol_max_share => 0.15,  # Protocol gets at most 15%
        :solver_max_share => 0.10,  # Solver gets at most 10%
        :mev_protection_bonus => 0.05  # 5% bonus for MEV protection
    )
    
    return PriceImprovementCalculator(
        min_improvement_bps,
        max_improvement_bps,
        protocol_fee_bps,
        solver_incentive_bps,
        mev_protection_threshold,
        Dict{Tuple{Int,Int},BaselineHistory}(),
        Vector{ImprovementMetrics}(),
        attribution_config
    )
end

"""
    calculate_improvement(calculator, baseline_price, improved_price, trade_size)

Calculate price improvement metrics for a trade.
"""
function calculate_improvement(calc::PriceImprovementCalculator,
                              baseline_price::Float64,
                              improved_price::Float64,
                              trade_size::Float64)
    
    # Calculate raw improvement
    improvement_amount = improved_price - baseline_price
    improvement_percentage = improvement_amount / baseline_price
    improvement_bps = improvement_percentage * 10000
    
    # Apply bounds
    clamped_bps = clamp(improvement_bps, 0, calc.max_improvement_bps)
    
    # Recalculate with clamped value
    if clamped_bps != improvement_bps
        improvement_percentage = clamped_bps / 10000
        improved_price = baseline_price * (1 + improvement_percentage)
        improvement_amount = improved_price - baseline_price
    end
    
    # Calculate value created
    value_created = improvement_amount * trade_size
    
    metrics = ImprovementMetrics(
        baseline_price,
        improved_price,
        clamped_bps,
        improvement_amount,
        improvement_percentage,
        trade_size,
        value_created,
        time()
    )
    
    # Store in history
    push!(calc.improvement_history, metrics)
    if length(calc.improvement_history) > 10000
        deleteat!(calc.improvement_history, 1:5000)
    end
    
    return metrics
end

"""
    validate_improvement_bounds(calculator, improvement_bps)

Check if improvement is within acceptable bounds.
"""
function validate_improvement_bounds(calc::PriceImprovementCalculator,
                                    improvement_bps::Float64)
    
    if improvement_bps < 0
        return (valid=false, reason="Negative improvement not allowed")
    end
    
    if improvement_bps < calc.min_improvement_bps
        return (valid=false, reason="Below minimum improvement threshold")
    end
    
    if improvement_bps > calc.max_improvement_bps
        return (valid=false, reason="Exceeds maximum improvement cap")
    end
    
    return (valid=true, reason="")
end

"""
    attribute_value(calculator, metrics, has_mev_protection)

Attribute value created by improvement to different parties.
"""
function attribute_value(calc::PriceImprovementCalculator,
                        metrics::ImprovementMetrics,
                        has_mev_protection::Bool=false)
    
    total_value = metrics.value_created
    
    if total_value <= 0
        return ValueAttribution(0, 0, 0, 0, 0, 1.0, 0, 0)
    end
    
    # Base attribution
    protocol_value = total_value * (calc.protocol_fee_bps / 10000)
    solver_value = total_value * (calc.solver_incentive_bps / 10000)
    mev_value = 0.0
    
    # MEV protection bonus
    if has_mev_protection && metrics.improvement_bps > calc.mev_protection_threshold
        mev_bonus = calc.attribution_config[:mev_protection_bonus]
        mev_value = total_value * mev_bonus
    end
    
    # Apply caps
    protocol_max = total_value * calc.attribution_config[:protocol_max_share]
    solver_max = total_value * calc.attribution_config[:solver_max_share]
    
    protocol_value = min(protocol_value, protocol_max)
    solver_value = min(solver_value, solver_max)
    
    # User gets the rest (with minimum guarantee)
    fees_total = protocol_value + solver_value + mev_value
    user_min = total_value * calc.attribution_config[:user_min_share]
    user_value = max(total_value - fees_total, user_min)
    
    # Adjust if total exceeds
    if user_value + fees_total > total_value
        scale = total_value / (user_value + fees_total)
        protocol_value *= scale
        solver_value *= scale
        mev_value *= scale
        user_value = total_value - protocol_value - solver_value - mev_value
    end
    
    return ValueAttribution(
        user_value,
        protocol_value,
        solver_value,
        mev_value,
        total_value,
        user_value / total_value,
        protocol_value / total_value,
        solver_value / total_value
    )
end

"""
    update_baseline(calculator, token_in, token_out, price, volume)

Update baseline price history for a token pair.
"""
function update_baseline(calc::PriceImprovementCalculator,
                        token_in::Int,
                        token_out::Int,
                        price::Float64,
                        volume::Float64)
    
    key = (token_in, token_out)
    
    if !haskey(calc.baseline_history, key)
        calc.baseline_history[key] = BaselineHistory(
            Float64[], Float64[], Float64[], 1000
        )
    end
    
    history = calc.baseline_history[key]
    
    push!(history.prices, price)
    push!(history.volumes, volume)
    push!(history.timestamps, time())
    
    # Maintain size limit
    if length(history.prices) > history.max_size
        n_remove = length(history.prices) - history.max_size
        deleteat!(history.prices, 1:n_remove)
        deleteat!(history.volumes, 1:n_remove)
        deleteat!(history.timestamps, 1:n_remove)
    end
end

"""
    calculate_surplus(calculator, metrics, execution_price)

Calculate consumer surplus from price improvement.
"""
function calculate_surplus(calc::PriceImprovementCalculator,
                          metrics::ImprovementMetrics,
                          execution_price::Float64)
    
    # Consumer surplus is the area between baseline and execution
    if execution_price >= metrics.baseline_price
        return 0.0  # No surplus if execution is worse than baseline
    end
    
    price_savings = metrics.baseline_price - execution_price
    surplus = price_savings * metrics.trade_size
    
    # Account for improvement captured
    improvement_captured = metrics.improvement_amount * metrics.trade_size
    net_surplus = surplus - improvement_captured
    
    return max(0.0, net_surplus)
end

"""
    get_improvement_metrics(calculator; window_seconds)

Get aggregated improvement metrics over a time window.
"""
function get_improvement_metrics(calc::PriceImprovementCalculator;
                                window_seconds::Float64=3600.0)
    
    current_time = time()
    cutoff_time = current_time - window_seconds
    
    # Filter recent improvements
    recent = filter(m -> m.timestamp >= cutoff_time, calc.improvement_history)
    
    if isempty(recent)
        return (
            count = 0,
            avg_improvement_bps = 0.0,
            total_value_created = 0.0,
            avg_trade_size = 0.0,
            improvement_rate = 0.0
        )
    end
    
    # Calculate metrics
    improvements = [m.improvement_bps for m in recent]
    values = [m.value_created for m in recent]
    sizes = [m.trade_size for m in recent]
    
    # Count improvements vs no improvement
    with_improvement = count(m -> m.improvement_bps > 0, recent)
    
    return (
        count = length(recent),
        avg_improvement_bps = mean(improvements),
        total_value_created = sum(values),
        avg_trade_size = mean(sizes),
        improvement_rate = with_improvement / length(recent),
        median_improvement_bps = median(improvements),
        std_improvement_bps = std(improvements),
        max_improvement_bps = maximum(improvements),
        percentile_95_bps = quantile(improvements, 0.95)
    )
end

# Helper functions

function quantile(data::Vector{Float64}, q::Float64)
    if isempty(data)
        return 0.0
    end
    
    sorted = sort(data)
    n = length(sorted)
    h = (n - 1) * q + 1
    i = floor(Int, h)
    
    if i >= n
        return sorted[n]
    elseif i < 1
        return sorted[1]
    else
        return sorted[i] + (h - i) * (sorted[i + 1] - sorted[i])
    end
end

end # module