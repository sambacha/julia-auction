"""
    ConservativeStrategy

Low-frequency bidding with larger improvements.
Suitable for volatile or illiquid markets.
"""
struct ConservativeStrategy <: BidderStrategy
    frequency_ms::Float64
    improvement_range::Tuple{Float64,Float64}
    min_liquidity::Float64  # Minimum market liquidity to bid
    max_volatility::Float64  # Maximum volatility tolerance

    function ConservativeStrategy()
        new(30.0, (30.0, 50.0), 0.5, 0.5)
    end
end

"""
    generate_bid(strategy::ConservativeStrategy, baseline_price, baseline_quantity, market, rng)

Generate conservative bid with lower frequency and higher improvements.
"""
function generate_bid(
    strategy::ConservativeStrategy,
    baseline_price::Float64,
    baseline_quantity::Float64,
    market::MarketConditions,
    rng::Random.AbstractRNG,
)

    # Only bid in favorable conditions
    if market.liquidity < strategy.min_liquidity || market.volatility > strategy.max_volatility
        return nothing
    end

    # Lower probability of bidding
    if rand(rng) > 0.4  # 60% probability
        # Larger improvement for conservative strategy
        improvement_bps = rand(rng, Uniform(strategy.improvement_range...))

        # Reduce improvement in bearish markets
        if market.trend < 0
            improvement_bps *= (1 + market.trend * 0.2)
        end

        price = baseline_price * (1 + improvement_bps / 10000)
        quantity = baseline_quantity * rand(rng, Uniform(0.5, 1.0))

        # Slower arrival time
        timestamp = rand(rng, Exponential(strategy.frequency_ms))

        return (
            price = price,
            quantity = quantity,
            timestamp = timestamp,
            priority_fee = price * 0.002,  # Higher priority fee for conservative bids
        )
    end

    return nothing
end
