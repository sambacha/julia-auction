"""
    RandomWalkStrategy

Stochastic bidding strategy based on geometric Brownian motion.
Models price discovery as a random walk with drift.
"""
struct RandomWalkStrategy <: BidderStrategy
    drift::Float64  # Drift parameter (annualized)
    volatility::Float64  # Volatility parameter (annualized)
    mean_reversion_speed::Float64  # Mean reversion parameter
    long_run_mean::Float64  # Long-run mean improvement in bps
    jump_intensity::Float64  # Poisson jump intensity
    jump_size_mean::Float64  # Mean jump size in bps

    function RandomWalkStrategy()
        new(
            0.05,   # 5% annual drift
            0.2,    # 20% annual volatility
            0.1,    # Mean reversion speed
            25.0,   # Long-run mean of 25 bps
            0.05,   # Jump probability
            10.0,    # Average jump of 10 bps
        )
    end
end

"""
    generate_bid(strategy::RandomWalkStrategy, baseline_price, baseline_quantity, market, rng)

Generate bid following stochastic process with jumps.
"""
function generate_bid(
    strategy::RandomWalkStrategy,
    baseline_price::Float64,
    baseline_quantity::Float64,
    market::MarketConditions,
    rng::Random.AbstractRNG,
)

    # Time step (fraction of year for 100ms auction)
    dt = 100.0 / (365 * 24 * 60 * 60 * 1000)

    # Current improvement level (start from long-run mean)
    current_improvement = strategy.long_run_mean

    # Ornstein-Uhlenbeck process with mean reversion
    drift_component = strategy.mean_reversion_speed * (strategy.long_run_mean - current_improvement) * dt

    # Brownian motion component
    diffusion_component = strategy.volatility * sqrt(dt) * randn(rng)

    # Jump component (compound Poisson process)
    jump_component = 0.0
    if rand(rng) < strategy.jump_intensity * dt
        jump_component = strategy.jump_size_mean * randn(rng)
    end

    # Combined improvement
    improvement_bps = current_improvement + drift_component + diffusion_component * current_improvement + jump_component

    # Adjust for market conditions
    improvement_bps *= (1 + market.volatility * randn(rng) * 0.2)
    improvement_bps = max(5.0, min(60.0, improvement_bps))  # Bound improvements

    price = baseline_price * (1 + improvement_bps / 10000)

    # Quantity follows log-normal distribution
    quantity = baseline_quantity * exp(0.2 * randn(rng))
    quantity = clamp(quantity, baseline_quantity * 0.1, baseline_quantity * 3.0)

    # Arrival time follows inhomogeneous Poisson process
    intensity = 1.0 / (20.0 * (1 + market.liquidity))
    timestamp = rand(rng, Exponential(1.0 / intensity))

    return (
        price = price,
        quantity = quantity,
        timestamp = timestamp,
        priority_fee = price * abs(0.001 + 0.0005 * randn(rng)),
    )
end

"""
    simulate_path(strategy::RandomWalkStrategy, n_steps::Int, dt::Float64, rng)

Simulate a full price path for analysis.
"""
function simulate_path(strategy::RandomWalkStrategy, n_steps::Int, dt::Float64, rng::Random.AbstractRNG)
    path = zeros(n_steps + 1)
    path[1] = strategy.long_run_mean

    for i = 2:(n_steps+1)
        # Mean reversion
        drift = strategy.mean_reversion_speed * (strategy.long_run_mean - path[i-1])

        # Diffusion
        diffusion = strategy.volatility * sqrt(dt) * randn(rng)

        # Jump
        jump = rand(rng) < strategy.jump_intensity * dt ? strategy.jump_size_mean * randn(rng) : 0.0

        path[i] = path[i-1] + drift * dt + diffusion * path[i-1] + jump
        path[i] = max(0.0, path[i])  # Ensure non-negative
    end

    return path
end
