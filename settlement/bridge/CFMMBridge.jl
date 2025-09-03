"""
    CFMMBridge

Interface adapter between settlement orchestrator and CFMM router.
Handles protocol translation, route preparation, and execution.

# Responsibilities
- Translate auction results to CFMM operations
- Optimize routing across multiple pools
- Handle protocol-specific quirks
- Manage slippage and price impact
"""

using ...Execution: AtomicTransaction
using .Adapters: ProtocolAdapter, get_adapter
using .Optimization: RouteOptimizer, optimize_routes
using CFMMRouter
struct CFMMConfig
    max_slippage_bps::Float64
    max_price_impact_bps::Float64
    split_threshold::Float64
    enable_multi_hop::Bool
    
    function CFMMConfig(;
        max_slippage_bps::Float64 = 50.0,  # 0.5%
        max_price_impact_bps::Float64 = 100.0,  # 1%
        split_threshold::Float64 = 10000.0,
        enable_multi_hop::Bool = true
    )
        new(max_slippage_bps, max_price_impact_bps, split_threshold, enable_multi_hop)
    end
end

mutable struct CFMMBridge
    router::CFMMRouter.Router
    optimizer::RouteOptimizer
    adapters::Dict{Symbol, ProtocolAdapter}
    config::CFMMConfig
    metrics::Dict{Symbol, Float64}
    
    function CFMMBridge(
        router::CFMMRouter.Router;
        config::CFMMConfig = CFMMConfig()
    )
        optimizer = RouteOptimizer(config)
        adapters = Dict{Symbol, ProtocolAdapter}()
        metrics = Dict{Symbol, Float64}(
            :total_volume => 0.0,
            :total_routes => 0.0,
            :avg_price_impact => 0.0,
            :avg_gas_used => 0.0
        )
        new(router, optimizer, adapters, config, metrics)
    end
end

"""
    prepare_routes(bridge, transaction)

Prepare optimized routes for the transaction across CFMM pools.

# Returns
- Vector of route values optimized for minimal price impact
"""
function prepare_routes(
    bridge::CFMMBridge,
    transaction::AtomicTransaction
)
    # Extract trade parameters from transaction
    trade_params = extract_trade_params(transaction)
    
    # Determine which protocols to use
    protocols = identify_protocols(bridge, trade_params)
    
    # Optimize routes across protocols
    routes = optimize_routes(
        bridge.optimizer,
        trade_params,
        protocols
    )
    
    # Validate against slippage limits
    validate_routes(bridge, routes, trade_params)
    
    return routes
end

"""
    execute_transaction(bridge, transaction)

Execute the transaction on the CFMM router with the prepared routes.

# Returns
- Execution result with actual prices and gas used
"""
function execute_transaction(
    bridge::CFMMBridge,
    transaction::AtomicTransaction
)
    routes = transaction.routes
    
    # Build router call data
    call_data = build_call_data(bridge, transaction, routes)
    
    # Simulate execution first
    simulation = simulate_execution(bridge.router, call_data)
    
    if simulation.price_impact > bridge.config.max_price_impact_bps / 10000
        throw(ErrorException("Price impact exceeds limit: $(simulation.price_impact)"))
    end
    
    # Execute on router
    result = CFMMRouter.execute(bridge.router, call_data)
    
    # Update metrics
    update_metrics!(bridge, result)
    
    return result
end

"""
    estimate_impact(bridge, transaction)

Estimate the price impact of executing the transaction.

# Returns
- Estimated price impact as a fraction
"""
function estimate_impact(
    bridge::CFMMBridge,
    transaction::AtomicTransaction
)
    routes = transaction.routes
    trade_params = extract_trade_params(transaction)
    
    impact = 0.0
    for (i, route) in enumerate(routes)
        pool_impact = estimate_pool_impact(
            bridge,
            trade_params.amounts[i],
            route
        )
        impact += pool_impact * (trade_params.amounts[i] / sum(trade_params.amounts))
    end
    
    return impact
end

# Helper functions

function extract_trade_params(transaction::AtomicTransaction)
    # Extract trading parameters from transaction
    return (
        token_in = get(transaction.metadata, :token_in, ""),
        token_out = get(transaction.metadata, :token_out, ""),
        amounts = get(transaction.metadata, :amounts, Float64[]),
        deadline = get(transaction.metadata, :deadline, 0)
    )
end

function identify_protocols(bridge::CFMMBridge, trade_params)
    # Identify which protocols have liquidity for this trade
    protocols = Symbol[]
    
    # Check each registered adapter
    for (protocol, adapter) in bridge.adapters
        if has_liquidity(adapter, trade_params.token_in, trade_params.token_out)
            push!(protocols, protocol)
        end
    end
    
    # Default to generic router if no specific protocols
    if isempty(protocols)
        push!(protocols, :generic)
    end
    
    return protocols
end

function validate_routes(bridge::CFMMBridge, routes::Vector, trade_params)
    total_amount = sum(trade_params.amounts)
    route_total = sum(routes)
    
    if abs(route_total - total_amount) > 0.01 * total_amount
        throw(ErrorException("Route amounts don't match trade amount"))
    end
    
    for route in routes
        if route < 0
            throw(ErrorException("Negative route amount detected"))
        end
    end
end

function build_call_data(
    bridge::CFMMBridge,
    transaction::AtomicTransaction,
    routes::Vector
)
    # Build router-specific call data
    trade_params = extract_trade_params(transaction)
    
    return CFMMRouter.CallData(
        function_name = "swap",
        token_in = trade_params.token_in,
        token_out = trade_params.token_out,
        amounts = routes,
        deadline = trade_params.deadline,
        min_amount_out = calculate_min_amount(bridge, trade_params, routes)
    )
end

function simulate_execution(router::CFMMRouter.Router, call_data)
    # Simulate execution to estimate gas and price impact
    return CFMMRouter.simulate(router, call_data)
end

function calculate_min_amount(bridge::CFMMBridge, trade_params, routes)
    # Calculate minimum output accounting for slippage
    expected_output = sum(routes)  # Simplified
    slippage_factor = 1 - bridge.config.max_slippage_bps / 10000
    return expected_output * slippage_factor
end

function estimate_pool_impact(bridge::CFMMBridge, amount::Float64, route)
    # Estimate price impact for a single pool/route
    # Simplified - in production would query actual pool reserves
    return amount / 1000000  # Mock impact calculation
end

function update_metrics!(bridge::CFMMBridge, result)
    bridge.metrics[:total_volume] += result.volume
    bridge.metrics[:total_routes] += 1
    bridge.metrics[:avg_price_impact] = 
        0.9 * bridge.metrics[:avg_price_impact] + 0.1 * result.price_impact
    bridge.metrics[:avg_gas_used] = 
        0.9 * bridge.metrics[:avg_gas_used] + 0.1 * result.gas_used
end