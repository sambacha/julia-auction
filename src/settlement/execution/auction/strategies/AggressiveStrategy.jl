"""
    AggressiveStrategy

High-frequency bidding strategy with small improvements.
Suitable for liquid markets with tight spreads.
"""
struct AggressiveStrategy <: BidderStrategy
    frequency_ms::Float64  # Bidding frequency in milliseconds
    improvement_range::Tuple{Float64, Float64}  # Min/max improvement in bps
    volume_multiplier::Float64  # Multiplier for baseline volume
    
    function AggressiveStrategy()
        new(10.0, (10.0, 15.0), 0.8)
    end
end

"""
    generate_bid(strategy::AggressiveStrategy, baseline_price, baseline_quantity, market, rng)

Generate aggressive bid with high frequency and small improvements.
"""
function generate_bid(strategy::AggressiveStrategy, 
                     baseline_price::Float64,
                     baseline_quantity::Float64,
                     market::MarketConditions,
                     rng::Random.AbstractRNG)
    
    # High probability of bidding
    if rand(rng) > 0.1  # 90% probability
        # Small improvement adjusted for market volatility
        improvement_bps = rand(rng, Uniform(strategy.improvement_range...))
        improvement_bps *= (1 + market.volatility * 0.3)
        
        # Adjust for market trend
        improvement_bps *= (1 + market.trend * 0.1)
        
        price = baseline_price * (1 + improvement_bps / 10000)
        quantity = baseline_quantity * strategy.volume_multiplier
        
        # Fast arrival time
        timestamp = rand(rng, Exponential(strategy.frequency_ms))
        
        return (
            price = price,
            quantity = quantity,
            timestamp = timestamp,
            priority_fee = price * 0.0005  # Low priority fee for aggressive strategy
        )
    end
    
    return nothing
end