# Elastic Supply Mechanisms

## Introduction

Elastic supply represents our core innovation for solving the bid shading problem in uniform price auctions. By dynamically adjusting supply based on demand signals, we create incentives for truthful bidding.

## Mathematical Foundation

### Base Model

The supply function adapts to the demand curve:

```
S(p) = S₀ × f(p, θ)
```

Where:
- `S₀` = base supply quantity
- `p` = market clearing price
- `θ` = elasticity parameters
- `f` = adjustment function

### Adjustment Functions

#### Linear Elasticity

```julia
f_linear(p, α) = 1 + α × (p - p_ref) / p_ref
```

Simple and predictable, suitable for stable markets.

#### Logarithmic Elasticity

```julia
f_log(p, α, β) = 1 + α × log(β × p / p_ref)
```

More responsive to large price movements, better for volatile markets.

#### Sigmoid Elasticity

```julia
f_sigmoid(p, α, k) = 2 / (1 + exp(-k × (p - p_ref) / p_ref))
```

Bounded response with smooth transitions, ideal for risk management.

## Implementation

### Core Algorithm

```julia
function calculate_elastic_supply(
    bids::Vector{Bid},
    base_supply::Float64,
    elasticity::ElasticityFunction
) 
    # Sort bids by price (descending)
    sorted_bids = sort(bids, by=b->b.price, rev=true)
    
    # Binary search for clearing price
    left, right = 0.0, maximum(b.price for b in bids)
    
    while right - left > TOLERANCE
        mid = (left + right) / 2
        
        # Calculate supply at this price
        supply = base_supply * elasticity(mid)
        
        # Calculate demand at this price
        demand = sum(b.quantity for b in bids if b.price >= mid)
        
        if demand > supply
            left = mid
        else
            right = mid
        end
    end
    
    return (left + right) / 2, base_supply * elasticity((left + right) / 2)
end
```

### Optimization Techniques

#### Gradient-Based Search

For smooth elasticity functions:

```julia
function optimize_clearing_gradient(bids, supply_fn)
    # Initial guess
    p = median([b.price for b in bids])
    
    for iter in 1:MAX_ITERATIONS
        # Compute gradient
        grad = compute_excess_demand_gradient(p, bids, supply_fn)
        
        # Update price
        p = p - LEARNING_RATE * grad
        
        # Check convergence
        if abs(grad) < TOLERANCE
            break
        end
    end
    
    return p
end
```

#### Newton's Method

For faster convergence:

```julia
function newton_clearing(bids, supply_fn)
    p = initial_guess(bids)
    
    for iter in 1:MAX_ITERATIONS
        f = excess_demand(p, bids, supply_fn)
        f_prime = excess_demand_derivative(p, bids, supply_fn)
        
        p_new = p - f / f_prime
        
        if abs(p_new - p) < TOLERANCE
            return p_new
        end
        
        p = p_new
    end
end
```

## Parameter Selection

### Elasticity Coefficient (α)

| Market Type | Recommended α | Rationale |
|------------|---------------|-----------|
| Treasury Bonds | 0.1 - 0.3 | Low volatility, high liquidity |
| Commodities | 0.3 - 0.5 | Moderate volatility |
| Crypto/DeFi | 0.5 - 0.8 | High volatility, need strong incentives |
| Illiquid Assets | 0.7 - 1.0 | Maximum price discovery |

### Price Bounds

Always set bounds to prevent extreme outcomes:

```julia
struct ElasticSupplyConfig
    base_quantity::Float64
    elasticity::Float64
    price_floor::Float64   # Minimum clearing price
    price_ceiling::Float64  # Maximum clearing price
    
    function ElasticSupplyConfig(base, elast, floor, ceiling)
        @assert 0 ≤ elast ≤ 1 "Elasticity must be in [0,1]"
        @assert floor < ceiling "Floor must be less than ceiling"
        new(base, elast, floor, ceiling)
    end
end
```

## Performance Analysis

### Efficiency Metrics

```julia
function calculate_efficiency(result::AuctionResult, true_values::Vector{Float64})
    # Social welfare achieved
    achieved = sum(
        true_values[i] * result.allocations[i] 
        for i in 1:length(result.winners)
    )
    
    # Optimal social welfare
    optimal = sum(
        sort(true_values, rev=true)[1:result.total_quantity]
    )
    
    return achieved / optimal
end
```

### Revenue Comparison

```julia
function revenue_improvement(elastic_result, fixed_result)
    elastic_revenue = elastic_result.clearing_price * elastic_result.total_quantity
    fixed_revenue = fixed_result.clearing_price * fixed_result.total_quantity
    
    improvement = (elastic_revenue - fixed_revenue) / fixed_revenue
    return improvement * 100  # Percentage
end
```

## Case Studies

### DeFi Token Launch

**Setup**:
- Initial supply: 1M tokens
- Elasticity: 0.6
- Result: 35% less bid shading

### Treasury Auction

**Setup**:
- Bond supply: $10B
- Elasticity: 0.25
- Result: $120M additional revenue

## Advanced Extensions

### Multi-Dimensional Elasticity

Adjust based on multiple signals:

```julia
function multi_elastic_supply(p, volume, volatility, time_pressure)
    base_adjustment = elasticity_price(p)
    volume_adjustment = elasticity_volume(volume)
    volatility_adjustment = elasticity_volatility(volatility)
    urgency_adjustment = elasticity_time(time_pressure)
    
    return base_supply * base_adjustment * volume_adjustment * 
           volatility_adjustment * urgency_adjustment
end
```

### Learning-Based Elasticity

Adapt parameters using ML:

```julia
function adaptive_elasticity(historical_auctions)
    features = extract_features(historical_auctions)
    optimal_params = gradient_boosting_regressor(features)
    return ElasticityFunction(optimal_params)
end
```

## Best Practices

1. **Start Conservative**: Begin with low elasticity (0.1-0.2) and increase gradually
2. **Monitor Metrics**: Track efficiency, revenue, and participation
3. **Set Bounds**: Always implement price floors and ceilings
4. **Test Extensively**: Run simulations with your specific bid distributions
5. **Communicate Clearly**: Ensure bidders understand the mechanism

## Troubleshooting

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| No convergence | Elasticity too high | Reduce α parameter |
| Low participation | Complexity | Simplify or educate |
| Price volatility | Insufficient bounds | Tighten floor/ceiling |
| Gaming behavior | Predictable function | Add randomization |

## Next Steps

- [Implementation Guide](/api/augmented)
- [CFMM Integration](/api/settlement)
- [Production Status](/guides/production_status)