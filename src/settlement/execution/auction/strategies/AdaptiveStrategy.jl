"""
    AdaptiveStrategy

Machine learning-based strategy that adapts to market conditions.
Uses reinforcement learning principles to optimize bidding.
"""
mutable struct AdaptiveStrategy <: BidderStrategy
    base_improvement::Float64
    learning_rate::Float64
    exploration_rate::Float64
    q_table::Dict{Int, Float64}  # State-action values
    recent_rewards::Vector{Float64}
    state_history::Vector{Int}
    
    function AdaptiveStrategy()
        new(
            25.0,  # Base improvement in bps
            0.1,   # Learning rate
            0.2,   # Exploration rate
            Dict{Int, Float64}(),
            Float64[],
            Int[]
        )
    end
end

"""
    get_market_state(market::MarketConditions)

Discretize market conditions into state representation.
"""
function get_market_state(market::MarketConditions)
    # Create discrete state from continuous market conditions
    volatility_bucket = min(3, floor(Int, market.volatility * 10))
    liquidity_bucket = min(3, floor(Int, market.liquidity * 4))
    trend_bucket = sign(market.trend) + 1  # -1, 0, 1 -> 0, 1, 2
    
    # Combine into single state index
    return volatility_bucket * 100 + liquidity_bucket * 10 + trend_bucket
end

"""
    generate_bid(strategy::AdaptiveStrategy, baseline_price, baseline_quantity, market, rng)

Generate adaptive bid using Q-learning approach.
"""
function generate_bid(strategy::AdaptiveStrategy,
                     baseline_price::Float64,
                     baseline_quantity::Float64,
                     market::MarketConditions,
                     rng::Random.AbstractRNG)
    
    state = get_market_state(market)
    
    # Epsilon-greedy action selection
    if rand(rng) < strategy.exploration_rate
        # Explore: random action
        improvement_bps = rand(rng, Uniform(10.0, 50.0))
    else
        # Exploit: use learned values
        if haskey(strategy.q_table, state)
            # Use Q-value as improvement factor
            q_value = strategy.q_table[state]
            improvement_bps = strategy.base_improvement * (1 + q_value)
            improvement_bps = clamp(improvement_bps, 10.0, 50.0)
        else
            improvement_bps = strategy.base_improvement
        end
    end
    
    # Adapt to market conditions
    improvement_bps *= (1 + market.trend * 0.15)
    improvement_bps *= (1 - market.volatility * 0.2)
    
    price = baseline_price * (1 + improvement_bps / 10000)
    
    # Adaptive quantity based on confidence
    confidence = get(strategy.q_table, state, 0.0)
    quantity = baseline_quantity * (0.5 + 0.5 * sigmoid(confidence))
    
    # Variable arrival time based on market activity
    timestamp = rand(rng, Exponential(20.0 / (1 + market.volume / 1000000)))
    
    # Store state for learning
    push!(strategy.state_history, state)
    
    return (
        price = price,
        quantity = quantity,
        timestamp = timestamp,
        priority_fee = price * (0.001 + 0.001 * market.volatility)
    )
end

"""
    update_strategy!(strategy::AdaptiveStrategy, reward::Float64)

Update Q-values based on observed reward.
"""
function update_strategy!(strategy::AdaptiveStrategy, reward::Float64)
    push!(strategy.recent_rewards, reward)
    
    if !isempty(strategy.state_history)
        state = strategy.state_history[end]
        
        # Q-learning update
        old_value = get(strategy.q_table, state, 0.0)
        new_value = old_value + strategy.learning_rate * (reward - old_value)
        strategy.q_table[state] = new_value
        
        # Decay exploration rate
        strategy.exploration_rate *= 0.995
        strategy.exploration_rate = max(0.05, strategy.exploration_rate)
    end
    
    # Keep history bounded
    if length(strategy.recent_rewards) > 100
        popfirst!(strategy.recent_rewards)
    end
    if length(strategy.state_history) > 100
        popfirst!(strategy.state_history)
    end
end

"""
    sigmoid(x)

Sigmoid activation function for confidence scaling.
"""
sigmoid(x::Float64) = 1.0 / (1.0 + exp(-x))