module BundleEvaluatorModule

using Dates
using UUIDs
using Statistics
using SHA

export BundleScore, EvaluationCriteria, BundleEvaluator,
       evaluate_bundle, score_bundle, rank_bundles,
       calculate_profitability, estimate_revert_risk,
       analyze_bundle_composition, detect_sandwich_attacks

# Bundle evaluation criteria
struct EvaluationCriteria
    weight_profitability::Float64
    weight_gas_efficiency::Float64
    weight_revert_risk::Float64
    weight_fairness::Float64
    weight_builder_reputation::Float64
    min_profitability::Float64
    max_revert_risk::Float64
    penalize_sandwiches::Bool
    penalize_censorship::Bool
end

# Bundle scoring result
struct BundleScore
    bundle_id::UUID
    total_score::Float64
    profitability_score::Float64
    gas_efficiency_score::Float64
    revert_risk_score::Float64
    fairness_score::Float64
    reputation_score::Float64
    penalties::Float64
    evaluation_time::DateTime
    details::Dict{String, Any}
end

# Bundle evaluator
mutable struct BundleEvaluator
    criteria::EvaluationCriteria
    reputation_scores::Dict{String, Float64}  # builder_id => reputation
    historical_reverts::Dict{String, Vector{Float64}}  # builder_id => revert rates
    evaluation_cache::Dict{UUID, BundleScore}
    sandwich_detector_enabled::Bool
    censorship_detector_enabled::Bool
end

# Create a bundle evaluator with default criteria
function BundleEvaluator(;
    weight_profitability::Float64=0.4,
    weight_gas_efficiency::Float64=0.2,
    weight_revert_risk::Float64=0.2,
    weight_fairness::Float64=0.1,
    weight_builder_reputation::Float64=0.1
)::BundleEvaluator
    
    criteria = EvaluationCriteria(
        weight_profitability,
        weight_gas_efficiency,
        weight_revert_risk,
        weight_fairness,
        weight_builder_reputation,
        0.001,  # Min profitability (0.001 ETH)
        0.3,    # Max revert risk (30%)
        true,   # Penalize sandwiches
        true    # Penalize censorship
    )
    
    return BundleEvaluator(
        criteria,
        Dict{String, Float64}(),
        Dict{String, Vector{Float64}}(),
        Dict{UUID, BundleScore}(),
        true,
        true
    )
end

# Main bundle evaluation function
function evaluate_bundle(
    evaluator::BundleEvaluator,
    bundle::Dict{String, Any};
    use_cache::Bool=true
)::BundleScore
    
    bundle_id = get(bundle, "bundle_id", uuid4())
    
    # Check cache
    if use_cache && haskey(evaluator.evaluation_cache, bundle_id)
        return evaluator.evaluation_cache[bundle_id]
    end
    
    # Extract bundle information
    builder_id = get(bundle, "builder_id", "unknown")
    transactions = get(bundle, "transactions", [])
    bundle_value = Float64(get(bundle, "bundle_value", 0.0))
    gas_used = get(bundle, "gas_used", 0)
    gas_price = Float64(get(bundle, "gas_price", 0.0))
    
    # Calculate individual scores
    profitability_score = calculate_profitability_score(bundle_value, gas_used, gas_price)
    gas_efficiency_score = calculate_gas_efficiency_score(bundle_value, gas_used)
    revert_risk_score = estimate_revert_risk_score(evaluator, builder_id, transactions)
    fairness_score = calculate_fairness_score(evaluator, transactions)
    reputation_score = get_reputation_score(evaluator, builder_id)
    
    # Apply penalties
    penalties = 0.0
    
    if evaluator.sandwich_detector_enabled
        sandwich_penalty = detect_sandwich_penalty(transactions)
        penalties += sandwich_penalty
    end
    
    if evaluator.censorship_detector_enabled
        censorship_penalty = detect_censorship_penalty(transactions)
        penalties += censorship_penalty
    end
    
    # Calculate weighted total score
    total_score = (
        evaluator.criteria.weight_profitability * profitability_score +
        evaluator.criteria.weight_gas_efficiency * gas_efficiency_score +
        evaluator.criteria.weight_revert_risk * revert_risk_score +
        evaluator.criteria.weight_fairness * fairness_score +
        evaluator.criteria.weight_builder_reputation * reputation_score
    ) * (1.0 - penalties)
    
    # Create score result
    score = BundleScore(
        bundle_id,
        total_score,
        profitability_score,
        gas_efficiency_score,
        revert_risk_score,
        fairness_score,
        reputation_score,
        penalties,
        now(),
        Dict{String, Any}(
            "builder_id" => builder_id,
            "transaction_count" => length(transactions),
            "bundle_value" => bundle_value,
            "gas_used" => gas_used
        )
    )
    
    # Cache result
    evaluator.evaluation_cache[bundle_id] = score
    
    return score
end

# Calculate profitability score
function calculate_profitability_score(
    bundle_value::Float64,
    gas_used::Int64,
    gas_price::Float64
)::Float64
    
    # Calculate profit after gas costs
    gas_cost = (gas_used * gas_price) / 1e18  # Convert to ETH
    net_profit = bundle_value - gas_cost
    
    # Normalize to 0-1 scale
    # Assume max expected profit is 10 ETH
    max_expected_profit = 10.0
    score = clamp(net_profit / max_expected_profit, 0.0, 1.0)
    
    return score
end

# Calculate gas efficiency score
function calculate_gas_efficiency_score(
    bundle_value::Float64,
    gas_used::Int64
)::Float64
    
    if gas_used == 0
        return 0.0
    end
    
    # Value per gas unit (in wei)
    value_per_gas = (bundle_value * 1e18) / gas_used
    
    # Normalize based on expected range
    # Good efficiency: > 1000 wei per gas
    target_efficiency = 1000.0
    score = clamp(value_per_gas / target_efficiency, 0.0, 1.0)
    
    return score
end

# Estimate revert risk score
function estimate_revert_risk_score(
    evaluator::BundleEvaluator,
    builder_id::String,
    transactions::Vector{Any}
)::Float64
    
    # Get historical revert rate for builder
    historical_rate = 0.0
    if haskey(evaluator.historical_reverts, builder_id)
        rates = evaluator.historical_reverts[builder_id]
        if !isempty(rates)
            historical_rate = mean(rates)
        end
    end
    
    # Analyze transaction complexity
    complexity_risk = analyze_transaction_complexity(transactions)
    
    # Combine historical and complexity-based risk
    total_risk = 0.7 * historical_rate + 0.3 * complexity_risk
    
    # Convert to score (lower risk = higher score)
    score = 1.0 - clamp(total_risk, 0.0, 1.0)
    
    return score
end

# Analyze transaction complexity for revert risk
function analyze_transaction_complexity(transactions::Vector{Any})::Float64
    
    if isempty(transactions)
        return 0.0
    end
    
    risk_factors = 0.0
    
    for tx in transactions
        # Check for complex operations
        data = get(tx, "data", "")
        
        # Longer data usually means more complex operations
        if length(data) > 1000
            risk_factors += 0.1
        end
        
        # Check for known risky patterns
        if contains_defi_interaction(tx)
            risk_factors += 0.2
        end
        
        if contains_flash_loan(tx)
            risk_factors += 0.3
        end
    end
    
    # Normalize risk
    avg_risk = risk_factors / length(transactions)
    return clamp(avg_risk, 0.0, 1.0)
end

# Check if transaction contains DeFi interaction
function contains_defi_interaction(tx::Any)::Bool
    # Simplified check - look for common DeFi contract signatures
    data = string(get(tx, "data", ""))
    
    # Common DeFi function selectors (first 8 chars of keccak256 hash)
    defi_selectors = [
        "38ed1739",  # swapExactTokensForTokens
        "7ff36ab5",  # swapExactETHForTokens
        "18cbafe5",  # swapExactTokensForETH
        "a9059cbb",  # transfer
        "23b872dd",  # transferFrom
    ]
    
    for selector in defi_selectors
        if startswith(data, "0x" * selector)
            return true
        end
    end
    
    return false
end

# Check if transaction contains flash loan
function contains_flash_loan(tx::Any)::Bool
    data = string(get(tx, "data", ""))
    
    # Flash loan function selectors
    flash_loan_selectors = [
        "5ceae9c4",  # flashLoan (Aave v2)
        "ab9c4b5d",  # flashLoan (dYdX)
        "0d4d0e27",  # flashSwap (Uniswap v2)
    ]
    
    for selector in flash_loan_selectors
        if contains(data, selector)
            return true
        end
    end
    
    return false
end

# Calculate fairness score
function calculate_fairness_score(
    evaluator::BundleEvaluator,
    transactions::Vector{Any}
)::Float64
    
    if isempty(transactions)
        return 1.0
    end
    
    fairness = 1.0
    
    # Check for sandwich attacks
    if detect_sandwich_attacks(transactions)
        fairness -= 0.5
    end
    
    # Check for front-running patterns
    if detect_frontrunning(transactions)
        fairness -= 0.3
    end
    
    # Check for censorship
    if detect_censorship(transactions)
        fairness -= 0.2
    end
    
    return clamp(fairness, 0.0, 1.0)
end

# Detect sandwich attacks in bundle
function detect_sandwich_attacks(transactions::Vector{Any})::Bool
    
    if length(transactions) < 3
        return false
    end
    
    # Look for sandwich pattern: buy -> victim -> sell
    for i in 2:(length(transactions)-1)
        prev_tx = transactions[i-1]
        curr_tx = transactions[i]
        next_tx = transactions[i+1]
        
        # Check if prev and next are from same sender
        if get(prev_tx, "from", "") == get(next_tx, "from", "")
            # Check if they interact with same contract
            if get(prev_tx, "to", "") == get(next_tx, "to", "")
                # Likely sandwich attack
                return true
            end
        end
    end
    
    return false
end

# Calculate sandwich penalty
function detect_sandwich_penalty(transactions::Vector{Any})::Float64
    if detect_sandwich_attacks(transactions)
        return 0.3  # 30% penalty
    end
    return 0.0
end

# Detect front-running patterns
function detect_frontrunning(transactions::Vector{Any})::Bool
    
    # Simplified detection - look for transactions with similar targets
    # and increasing gas prices
    
    if length(transactions) < 2
        return false
    end
    
    targets = Dict{String, Int}()
    
    for tx in transactions
        target = get(tx, "to", "")
        if target != ""
            targets[target] = get(targets, target, 0) + 1
        end
    end
    
    # If multiple transactions to same target, might be front-running
    for count in values(targets)
        if count >= 2
            return true
        end
    end
    
    return false
end

# Detect censorship patterns
function detect_censorship(transactions::Vector{Any})::Bool
    # Simplified - would need actual implementation based on
    # known censored addresses or transaction patterns
    return false
end

# Calculate censorship penalty
function detect_censorship_penalty(transactions::Vector{Any})::Float64
    if detect_censorship(transactions)
        return 0.5  # 50% penalty for censorship
    end
    return 0.0
end

# Get reputation score for builder
function get_reputation_score(
    evaluator::BundleEvaluator,
    builder_id::String
)::Float64
    
    return get(evaluator.reputation_scores, builder_id, 0.5)  # Default 0.5 for unknown builders
end

# Update builder reputation
function update_reputation(
    evaluator::BundleEvaluator,
    builder_id::String,
    success::Bool,
    revert_rate::Float64
)
    
    current_reputation = get(evaluator.reputation_scores, builder_id, 0.5)
    
    # Update based on success
    if success
        new_reputation = current_reputation * 0.9 + 0.1 * 1.0
    else
        new_reputation = current_reputation * 0.9 + 0.1 * 0.0
    end
    
    # Adjust for revert rate
    new_reputation *= (1.0 - revert_rate * 0.5)
    
    evaluator.reputation_scores[builder_id] = clamp(new_reputation, 0.0, 1.0)
    
    # Update historical reverts
    if !haskey(evaluator.historical_reverts, builder_id)
        evaluator.historical_reverts[builder_id] = Float64[]
    end
    
    push!(evaluator.historical_reverts[builder_id], revert_rate)
    
    # Keep only last 100 records
    if length(evaluator.historical_reverts[builder_id]) > 100
        evaluator.historical_reverts[builder_id] = evaluator.historical_reverts[builder_id][end-99:end]
    end
end

# Score a bundle (simplified interface)
function score_bundle(
    evaluator::BundleEvaluator,
    bundle::Dict{String, Any}
)::Float64
    
    score = evaluate_bundle(evaluator, bundle)
    return score.total_score
end

# Rank multiple bundles
function rank_bundles(
    evaluator::BundleEvaluator,
    bundles::Vector{Dict{String, Any}}
)::Vector{Tuple{Dict{String, Any}, BundleScore}}
    
    scored_bundles = Tuple{Dict{String, Any}, BundleScore}[]
    
    for bundle in bundles
        score = evaluate_bundle(evaluator, bundle)
        push!(scored_bundles, (bundle, score))
    end
    
    # Sort by total score (descending)
    sort!(scored_bundles, by=x->x[2].total_score, rev=true)
    
    return scored_bundles
end

# Calculate expected profitability
function calculate_profitability(
    bundle_value::Float64,
    gas_used::Int64,
    gas_price::Float64,
    base_fee::Float64
)::Float64
    
    gas_cost = gas_used * (gas_price - base_fee) / 1e18
    return bundle_value - gas_cost
end

# Estimate revert risk
function estimate_revert_risk(
    evaluator::BundleEvaluator,
    builder_id::String,
    transaction_count::Int64
)::Float64
    
    # Base risk from historical data
    base_risk = 0.0
    if haskey(evaluator.historical_reverts, builder_id)
        rates = evaluator.historical_reverts[builder_id]
        if !isempty(rates)
            base_risk = mean(rates)
        end
    else
        base_risk = 0.1  # Default 10% for unknown builders
    end
    
    # Adjust for transaction count (more txs = higher risk)
    complexity_multiplier = 1.0 + (transaction_count - 1) * 0.05
    
    return clamp(base_risk * complexity_multiplier, 0.0, 1.0)
end

# Analyze bundle composition
function analyze_bundle_composition(bundle::Dict{String, Any})::Dict{String, Any}
    
    transactions = get(bundle, "transactions", [])
    
    analysis = Dict{String, Any}(
        "transaction_count" => length(transactions),
        "has_sandwich" => detect_sandwich_attacks(transactions),
        "has_frontrunning" => detect_frontrunning(transactions),
        "defi_interactions" => 0,
        "flash_loans" => 0,
        "unique_targets" => Set{String}(),
        "total_gas" => 0
    )
    
    for tx in transactions
        if contains_defi_interaction(tx)
            analysis["defi_interactions"] += 1
        end
        
        if contains_flash_loan(tx)
            analysis["flash_loans"] += 1
        end
        
        target = get(tx, "to", "")
        if target != ""
            push!(analysis["unique_targets"], target)
        end
        
        analysis["total_gas"] += get(tx, "gas", 0)
    end
    
    analysis["unique_target_count"] = length(analysis["unique_targets"])
    delete!(analysis, "unique_targets")  # Remove set from output
    
    return analysis
end

end # module