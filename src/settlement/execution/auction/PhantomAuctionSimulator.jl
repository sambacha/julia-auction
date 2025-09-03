"""
    PhantomAuctionSimulator

Advanced simulation engine for phantom auctions with multiple bidding strategies,
market dynamics modeling, and comprehensive performance analysis.

This module provides a complete framework for simulating phantom auctions
under various market conditions and bidder behaviors.
"""
module PhantomAuctionSimulator

using Dates
using Distributions
using LinearAlgebra
using Random
using Statistics
# Import VCG mechanism
include("VCGMechanism.jl")
using .VCGMechanism
# Import configuration
include("../../../config/ConfigManager.jl")
using .ConfigManager: load_config, get_config, AuctionConfig
export PhantomSimulator, SimulationConfig, MarketConditions
export SimulationResult, BidderStrategy, SimulationMetrics
export run_simulation, run_monte_carlo, analyze_results
export calibrate_parameters, backtest_strategy

# Strategy types
abstract type BidderStrategy end

"""
    MarketConditions

Represents current market conditions for simulation.

# Fields
- `volatility::Float64`: Market volatility (annualized)
- `liquidity::Float64`: Liquidity score (0-1)
- `trend::Float64`: Market trend (-1 to 1, negative=bearish, positive=bullish)
- `spread::Float64`: Bid-ask spread in basis points
- `volume::Float64`: Recent trading volume
- `correlation_matrix::Matrix{Float64}`: Correlation between bidders
"""
struct MarketConditions
    volatility::Float64
    liquidity::Float64
    trend::Float64
    spread::Float64
    volume::Float64
    correlation_matrix::Matrix{Float64}

    function MarketConditions(;
        volatility::Float64 = 0.3,
        liquidity::Float64 = 0.7,
        trend::Float64 = 0.0,
        spread::Float64 = 10.0,
        volume::Float64 = 1000000.0,
        num_bidders::Int = 20,
    )
        # Generate correlation matrix with market-based correlations
        correlation_matrix = generate_correlation_matrix(num_bidders, liquidity)
        new(volatility, liquidity, trend, spread, volume, correlation_matrix)
    end
end

"""
    SimulationConfig

Configuration for phantom auction simulations.

# Fields
- `num_real_bidders::Int`: Number of real participants
- `num_phantom_bidders::Int`: Number of phantom bidders
- `auction_duration_ms::Int`: Duration of auction in milliseconds
- `num_simulations::Int`: Number of Monte Carlo simulations
- `seed::Union{Int, Nothing}`: Random seed for reproducibility
- `enable_vcg::Bool`: Use VCG mechanism
- `enable_learning::Bool`: Enable adaptive learning for strategies
"""
struct SimulationConfig
    num_real_bidders::Int
    num_phantom_bidders::Int
    auction_duration_ms::Int
    num_simulations::Int
    seed::Union{Int,Nothing}
    enable_vcg::Bool
    enable_learning::Bool

    function SimulationConfig(;
        num_real_bidders::Int = 5,
        num_phantom_bidders::Int = 15,
        auction_duration_ms::Int = 100,
        num_simulations::Int = 1000,
        seed::Union{Int,Nothing} = nothing,
        enable_vcg::Bool = true,
        enable_learning::Bool = false,
    )
        new(
            num_real_bidders,
            num_phantom_bidders,
            auction_duration_ms,
            num_simulations,
            seed,
            enable_vcg,
            enable_learning,
        )
    end
end

"""
    SimulatedBid

Represents a simulated bid with full metadata.
"""
struct SimulatedBid
    bidder_id::String
    price::Float64
    quantity::Float64
    timestamp::Float64  # ms since auction start
    is_phantom::Bool
    strategy::String
    priority_fee::Float64
end

"""
    SimulationMetrics

Comprehensive metrics from simulation run.
"""
struct SimulationMetrics
    avg_price_improvement::Float64
    price_discovery_efficiency::Float64
    mev_capture_rate::Float64
    bid_shading_reduction::Float64
    winner_diversity::Float64
    phantom_win_rate::Float64
    execution_time_ms::Float64
    convergence_speed::Float64
    volatility_reduction::Float64
    welfare_improvement::Float64
end

"""
    SimulationResult

Complete result of a simulation run.
"""
struct SimulationResult
    winning_bid::Union{SimulatedBid,Nothing}
    clearing_price::Float64
    total_surplus::Float64
    metrics::SimulationMetrics
    all_bids::Vector{SimulatedBid}
    vcg_result::Union{VCGMechanism.VCGResult,Nothing}
    convergence_path::Vector{Float64}
    execution_trace::Dict{String,Any}
end

"""
    PhantomSimulator

Main simulation engine for phantom auctions.
"""
mutable struct PhantomSimulator
    config::SimulationConfig
    market::MarketConditions
    strategies::Vector{BidderStrategy}
    historical_results::Vector{SimulationResult}
    calibration_params::Dict{String,Float64}
    rng::Random.AbstractRNG

    function PhantomSimulator(config::SimulationConfig, market::MarketConditions)
        rng = config.seed === nothing ? Random.default_rng() : Random.MersenneTwister(config.seed)

        # Initialize with diverse strategies
        strategies = create_default_strategies(config.num_phantom_bidders)

        # Default calibration parameters
        calibration_params = Dict{String,Float64}(
            "bid_mean" => 25.0,  # Mean improvement in bps
            "bid_std" => 10.0,   # Std dev of improvements
            "arrival_rate" => 0.3,  # Poisson arrival rate
            "momentum_factor" => 0.7,  # Price momentum weight
            "mean_reversion_speed" => 0.1,  # Mean reversion parameter
        )

        new(config, market, strategies, SimulationResult[], calibration_params, rng)
    end
end

# Import strategy implementations
include("strategies/AggressiveStrategy.jl")
include("strategies/ConservativeStrategy.jl")
include("strategies/AdaptiveStrategy.jl")
include("strategies/RandomWalkStrategy.jl")
include("strategies/CompetitiveEquilibriumStrategy.jl")

"""
    run_simulation(simulator::PhantomSimulator, baseline_price::Float64, baseline_quantity::Float64)

Run a single phantom auction simulation.
"""
function run_simulation(simulator::PhantomSimulator, baseline_price::Float64, baseline_quantity::Float64)
    start_time = time()

    # Generate real bidder bids
    real_bids = generate_real_bids(simulator, baseline_price, baseline_quantity)

    # Generate phantom bids using strategies
    phantom_bids = generate_phantom_bids(simulator, baseline_price, baseline_quantity)

    # Combine all bids
    all_bids = vcat(real_bids, phantom_bids)

    # Track price convergence
    convergence_path = track_convergence(all_bids, baseline_price)

    # Run auction mechanism
    if simulator.config.enable_vcg
        vcg_result = run_vcg_auction_simulation(all_bids, baseline_quantity)
        clearing_price = calculate_vcg_clearing_price(vcg_result)
        winning_bid = determine_vcg_winner(vcg_result, all_bids)
    else
        # Standard first-price sealed bid
        sort!(all_bids, by = b->b.price, rev = true)
        winning_bid = isempty(all_bids) ? nothing : all_bids[1]
        clearing_price = winning_bid === nothing ? baseline_price : winning_bid.price
        vcg_result = nothing
    end

    # Calculate metrics
    execution_time = (time() - start_time) * 1000  # Convert to ms
    metrics = calculate_simulation_metrics(
        all_bids,
        winning_bid,
        clearing_price,
        baseline_price,
        execution_time,
        convergence_path,
    )

    # Calculate total surplus
    total_surplus = calculate_total_surplus(all_bids, clearing_price, baseline_price)

    # Create execution trace for debugging
    execution_trace = Dict{String,Any}(
        "num_real_bids" => length(real_bids),
        "num_phantom_bids" => length(phantom_bids),
        "bid_timestamps" => [b.timestamp for b in all_bids],
        "strategy_distribution" => count_strategies(phantom_bids),
        "price_range" => extrema([b.price for b in all_bids if !isempty(all_bids)]),
    )

    result = SimulationResult(
        winning_bid,
        clearing_price,
        total_surplus,
        metrics,
        all_bids,
        vcg_result,
        convergence_path,
        execution_trace,
    )

    # Store for analysis
    push!(simulator.historical_results, result)

    return result
end

"""
    run_monte_carlo(simulator::PhantomSimulator, baseline_price::Float64, baseline_quantity::Float64)

Run Monte Carlo simulation with multiple iterations.
"""
function run_monte_carlo(simulator::PhantomSimulator, baseline_price::Float64, baseline_quantity::Float64)
    results = SimulationResult[]

    for i = 1:simulator.config.num_simulations
        # Vary market conditions slightly for each run
        perturbed_market = perturb_market_conditions(simulator.market, simulator.rng)
        simulator.market = perturbed_market

        result = run_simulation(simulator, baseline_price, baseline_quantity)
        push!(results, result)

        # Adaptive learning update
        if simulator.config.enable_learning && i % 100 == 0
            update_strategies!(simulator, results[max(1, i-99):i])
        end
    end

    return results
end

"""
    generate_real_bids(simulator, baseline_price, baseline_quantity)

Generate bids from real participants based on market conditions.
"""
function generate_real_bids(simulator::PhantomSimulator, baseline_price::Float64, baseline_quantity::Float64)
    bids = SimulatedBid[]

    for i = 1:simulator.config.num_real_bidders
        # Real bidders follow informed distribution
        improvement_bps = rand(
            simulator.rng,
            Normal(simulator.calibration_params["bid_mean"], simulator.calibration_params["bid_std"]),
        )

        # Adjust for market conditions
        improvement_bps *= (1 + simulator.market.trend * 0.2)
        improvement_bps = max(10, min(50, improvement_bps))  # Bound between 10-50 bps

        price = baseline_price * (1 + improvement_bps / 10000)
        quantity = baseline_quantity * rand(simulator.rng, Uniform(0.1, 2.0))

        # Arrival time follows Poisson process
        timestamp = rand(simulator.rng, Exponential(30.0))  # Mean 30ms arrival

        push!(bids, SimulatedBid(
            "real_$i",
            price,
            quantity,
            timestamp,
            false,
            "real_informed",
            price * 0.001,  # 0.1% priority fee
        ))
    end

    return bids
end

"""
    generate_phantom_bids(simulator, baseline_price, baseline_quantity)

Generate phantom bids using configured strategies.
"""
function generate_phantom_bids(simulator::PhantomSimulator, baseline_price::Float64, baseline_quantity::Float64)
    bids = SimulatedBid[]

    for (i, strategy) in enumerate(simulator.strategies[1:simulator.config.num_phantom_bidders])
        bid = generate_bid(strategy, baseline_price, baseline_quantity, simulator.market, simulator.rng)

        if bid !== nothing
            push!(
                bids,
                SimulatedBid(
                    "phantom_$i",
                    bid.price,
                    bid.quantity,
                    bid.timestamp,
                    true,
                    string(typeof(strategy)),
                    bid.priority_fee,
                ),
            )
        end
    end

    return bids
end

"""
    run_vcg_auction_simulation(bids, supply)

Run VCG auction on simulated bids.
"""
function run_vcg_auction_simulation(bids::Vector{SimulatedBid}, supply::Float64)
    # Convert to VCG bid format
    vcg_auction = VCGMechanism.VCGAuction(supply, 0.0, enable_multi_unit = true)

    for bid in bids
        vcg_bid = VCGMechanism.VCGBid(
            bid.bidder_id,
            bid.price,
            bid.quantity,
            is_phantom = bid.is_phantom,
            metadata = Dict(:strategy => bid.strategy),
        )
        push!(vcg_auction.bids, vcg_bid)
    end

    return VCGMechanism.run_vcg_auction(vcg_auction)
end

"""
    calculate_simulation_metrics(bids, winner, clearing_price, baseline_price, exec_time, convergence)

Calculate comprehensive simulation metrics.
"""
function calculate_simulation_metrics(
    bids::Vector{SimulatedBid},
    winner::Union{SimulatedBid,Nothing},
    clearing_price::Float64,
    baseline_price::Float64,
    exec_time::Float64,
    convergence_path::Vector{Float64},
)
    # Price improvement
    price_improvement = (clearing_price - baseline_price) / baseline_price * 10000

    # Price discovery efficiency (how close to true market price)
    prices = [b.price for b in bids]
    true_price = isempty(prices) ? baseline_price : median(prices)
    discovery_efficiency = 1 - abs(clearing_price - true_price) / true_price

    # MEV capture (value that would go to arbitrageurs)
    mev_potential = maximum([0.0; [b.price - baseline_price for b in bids]])
    mev_captured = clearing_price - baseline_price
    mev_capture_rate = mev_potential > 0 ? mev_captured / mev_potential : 0.0

    # Bid shading reduction (compare to theoretical truthful values)
    bid_shading = estimate_bid_shading(bids, clearing_price)

    # Winner diversity
    phantom_wins = count(b -> b.is_phantom && b == winner, bids)
    phantom_win_rate = winner !== nothing && winner.is_phantom ? 1.0 : 0.0

    # Convergence speed (iterations to stability)
    convergence_speed = calculate_convergence_speed(convergence_path)

    # Volatility reduction
    price_volatility = std(prices)
    baseline_volatility = baseline_price * 0.02  # Assume 2% baseline volatility
    volatility_reduction = max(0, (baseline_volatility - price_volatility) / baseline_volatility)

    # Welfare improvement (total surplus generated)
    welfare_improvement = sum([max(0, b.price - baseline_price) * b.quantity for b in bids])

    return SimulationMetrics(
        price_improvement,
        discovery_efficiency,
        mev_capture_rate,
        1 - bid_shading,  # Reduction is inverse of shading
        1 - phantom_win_rate,  # Diversity is inverse of phantom dominance
        phantom_win_rate,
        exec_time,
        convergence_speed,
        volatility_reduction,
        welfare_improvement,
    )
end

"""
    analyze_results(results::Vector{SimulationResult})

Analyze Monte Carlo simulation results for statistical properties.
"""
function analyze_results(results::Vector{SimulationResult})
    metrics = [r.metrics for r in results]

    analysis = Dict{String,Dict{String,Float64}}()

    # Analyze each metric
    for field in fieldnames(SimulationMetrics)
        values = [getfield(m, field) for m in metrics]
        analysis[string(field)] = Dict(
            "mean" => mean(values),
            "median" => median(values),
            "std" => std(values),
            "min" => minimum(values),
            "max" => maximum(values),
            "p05" => quantile(values, 0.05),
            "p95" => quantile(values, 0.95),
        )
    end

    # Add aggregate metrics
    clearing_prices = [r.clearing_price for r in results]
    analysis["clearing_price"] = Dict(
        "mean" => mean(clearing_prices),
        "std" => std(clearing_prices),
        "volatility" => std(clearing_prices) / mean(clearing_prices),
    )

    # Strategy performance
    strategy_wins = Dict{String,Int}()
    for r in results
        if r.winning_bid !== nothing
            strategy = r.winning_bid.strategy
            strategy_wins[strategy] = get(strategy_wins, strategy, 0) + 1
        end
    end

    total_auctions = length(results)
    analysis["strategy_performance"] = Dict(k => v / total_auctions for (k, v) in strategy_wins)

    return analysis
end

# Helper functions

"""
    generate_correlation_matrix(n, liquidity)

Generate correlation matrix based on market liquidity.
Higher liquidity implies higher correlations (herding behavior).
"""
function generate_correlation_matrix(n::Int, liquidity::Float64)
    # Base correlation increases with liquidity
    base_corr = 0.1 + 0.4 * liquidity

    # Create correlation matrix
    corr_matrix = Matrix{Float64}(I, n, n)

    for i = 1:n
        for j = (i+1):n
            # Correlation decreases with "distance" between bidders
            distance_factor = exp(-abs(i - j) / 10)
            correlation = base_corr * distance_factor * (0.8 + 0.4 * rand())
            corr_matrix[i, j] = correlation
            corr_matrix[j, i] = correlation
        end
    end

    # Ensure positive definiteness
    min_eigenvalue = minimum(eigvals(corr_matrix))
    if min_eigenvalue < 0.01
        corr_matrix += (0.01 - min_eigenvalue) * I
    end

    return corr_matrix
end

"""
    perturb_market_conditions(market, rng)

Add small random perturbations to market conditions.
"""
function perturb_market_conditions(market::MarketConditions, rng::Random.AbstractRNG)
    return MarketConditions(
        volatility = market.volatility * (1 + 0.1 * randn(rng)),
        liquidity = clamp(market.liquidity + 0.05 * randn(rng), 0.1, 1.0),
        trend = clamp(market.trend + 0.1 * randn(rng), -1.0, 1.0),
        spread = max(1.0, market.spread * (1 + 0.1 * randn(rng))),
        volume = max(1000.0, market.volume * (1 + 0.2 * randn(rng))),
        num_bidders = size(market.correlation_matrix, 1),
    )
end

"""
    create_default_strategies(n)

Create a diverse mix of strategies for phantom bidders.
"""
function create_default_strategies(n::Int)
    strategies = BidderStrategy[]

    # Mix of different strategies
    strategy_mix = [
        (AggressiveStrategy, 0.3),
        (ConservativeStrategy, 0.2),
        (AdaptiveStrategy, 0.2),
        (RandomWalkStrategy, 0.15),
        (CompetitiveEquilibriumStrategy, 0.15),
    ]

    for i = 1:n
        # Select strategy based on weights
        r = rand()
        cumsum = 0.0
        for (strategy_type, weight) in strategy_mix
            cumsum += weight
            if r <= cumsum
                push!(strategies, strategy_type())
                break
            end
        end
    end

    return strategies
end

"""
    track_convergence(bids, baseline_price)

Track price convergence path during auction.
"""
function track_convergence(bids::Vector{SimulatedBid}, baseline_price::Float64)
    if isempty(bids)
        return [baseline_price]
    end

    # Sort bids by timestamp
    sorted_bids = sort(bids, by = b->b.timestamp)

    convergence_path = [baseline_price]
    current_best = baseline_price

    for bid in sorted_bids
        if bid.price > current_best
            current_best = bid.price
            push!(convergence_path, current_best)
        end
    end

    return convergence_path
end

"""
    calculate_convergence_speed(path)

Calculate how quickly the price converges to stability.
"""
function calculate_convergence_speed(path::Vector{Float64})
    if length(path) < 2
        return 1.0
    end

    # Find when price stabilizes (changes < 0.1%)
    for i = 2:length(path)
        if abs(path[i] - path[end]) / path[end] < 0.001
            return i / length(path)
        end
    end

    return 0.5  # Didn't converge
end

"""
    estimate_bid_shading(bids, clearing_price)

Estimate the degree of bid shading.
"""
function estimate_bid_shading(bids::Vector{SimulatedBid}, clearing_price::Float64)
    if isempty(bids)
        return 0.0
    end

    # Assume true values are 5-10% higher than bids (typical shading)
    estimated_true_values = [b.price * 1.075 for b in bids]
    actual_bids = [b.price for b in bids]

    # Shading is the average percentage reduction
    shading = mean((estimated_true_values .- actual_bids) ./ estimated_true_values)

    return clamp(shading, 0.0, 0.3)  # Cap at 30% shading
end

"""
    calculate_total_surplus(bids, clearing_price, baseline_price)

Calculate total economic surplus generated.
"""
function calculate_total_surplus(bids::Vector{SimulatedBid}, clearing_price::Float64, baseline_price::Float64)
    consumer_surplus = sum([max(0, b.price - clearing_price) * b.quantity for b in bids if b.price >= clearing_price])

    producer_surplus = (clearing_price - baseline_price) * sum([b.quantity for b in bids if b.price >= clearing_price])

    return consumer_surplus + producer_surplus
end

"""
    count_strategies(bids)

Count distribution of strategies used.
"""
function count_strategies(bids::Vector{SimulatedBid})
    strategy_counts = Dict{String,Int}()

    for bid in bids
        strategy_counts[bid.strategy] = get(strategy_counts, bid.strategy, 0) + 1
    end

    return strategy_counts
end

"""
    calculate_vcg_clearing_price(vcg_result)

Extract effective clearing price from VCG result.
"""
function calculate_vcg_clearing_price(vcg_result::VCGMechanism.VCGResult)
    if isempty(vcg_result.allocations)
        return 0.0
    end

    # Use average payment per unit as clearing price
    total_payment = vcg_result.total_revenue
    total_quantity = sum(a.quantity for a in vcg_result.allocations)

    return total_quantity > 0 ? total_payment / total_quantity : 0.0
end

"""
    determine_vcg_winner(vcg_result, bids)

Determine the primary winner from VCG allocation.
"""
function determine_vcg_winner(vcg_result::VCGMechanism.VCGResult, bids::Vector{SimulatedBid})
    if isempty(vcg_result.allocations)
        return nothing
    end

    # Find bidder with largest allocation
    best_allocation = vcg_result.allocations[argmax([a.quantity for a in vcg_result.allocations])]

    # Find corresponding bid
    winner_idx = findfirst(b -> b.bidder_id == best_allocation.bidder_id, bids)

    return winner_idx !== nothing ? bids[winner_idx] : nothing
end

"""
    update_strategies!(simulator, recent_results)

Update strategies based on recent performance (for adaptive learning).
"""
function update_strategies!(simulator::PhantomSimulator, recent_results::Vector{SimulationResult})
    # Analyze recent performance
    strategy_performance = Dict{String,Float64}()

    for result in recent_results
        if result.winning_bid !== nothing && result.winning_bid.is_phantom
            strategy = result.winning_bid.strategy
            improvement = (result.clearing_price - result.winning_bid.price) / result.winning_bid.price

            current_score = get(strategy_performance, strategy, 0.0)
            strategy_performance[strategy] = current_score + improvement
        end
    end

    # Update strategy weights or parameters based on performance
    # This is a placeholder for more sophisticated learning algorithms
    for (strategy, score) in strategy_performance
        if score > 0
            # Increase probability of successful strategies
            # Implementation depends on specific strategy adaptation mechanism
        end
    end
end

"""
    calibrate_parameters(simulator, historical_data)

Calibrate simulation parameters from historical market data.
"""
function calibrate_parameters(simulator::PhantomSimulator, historical_data::Dict)
    # Extract bid improvements from historical data
    if haskey(historical_data, "bid_improvements")
        improvements = historical_data["bid_improvements"]
        simulator.calibration_params["bid_mean"] = mean(improvements)
        simulator.calibration_params["bid_std"] = std(improvements)
    end

    # Calibrate arrival rates
    if haskey(historical_data, "bid_timestamps")
        timestamps = historical_data["bid_timestamps"]
        inter_arrival_times = diff(sort(timestamps))
        simulator.calibration_params["arrival_rate"] = 1.0 / mean(inter_arrival_times)
    end

    # Calibrate market dynamics
    if haskey(historical_data, "prices")
        prices = historical_data["prices"]
        returns = diff(log.(prices))

        # Estimate momentum and mean reversion
        if length(returns) > 2
            # Simple AR(1) model for momentum
            X = returns[1:(end-1)]
            y = returns[2:end]
            simulator.calibration_params["momentum_factor"] = cor(X, y)
            simulator.calibration_params["mean_reversion_speed"] = 1.0 - abs(cor(X, y))
        end
    end

    return simulator.calibration_params
end

"""
    backtest_strategy(simulator, strategy, historical_scenarios)

Backtest a strategy against historical scenarios.
"""
function backtest_strategy(simulator::PhantomSimulator, strategy::BidderStrategy, historical_scenarios::Vector{Dict})
    results = []

    for scenario in historical_scenarios
        baseline_price = scenario["baseline_price"]
        baseline_quantity = scenario["baseline_quantity"]
        market_conditions = scenario["market_conditions"]

        # Generate bid using strategy
        bid = generate_bid(strategy, baseline_price, baseline_quantity, market_conditions, simulator.rng)

        # Compare to actual outcome
        actual_clearing = scenario["actual_clearing_price"]

        if bid !== nothing
            profit = bid.price >= actual_clearing ? (bid.price - actual_clearing) * bid.quantity : 0.0

            push!(
                results,
                Dict(
                    "profit" => profit,
                    "won" => bid.price >= actual_clearing,
                    "improvement" => (bid.price - baseline_price) / baseline_price * 10000,
                ),
            )
        end
    end

    return results
end

end # module PhantomAuctionSimulator
