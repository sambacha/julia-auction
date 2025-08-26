"""
    Adapters

Protocol-specific adapters for different CFMM implementations.
Each adapter handles the unique characteristics of its protocol.

Future adapters can be added here for:
- Uniswap V2/V3
- Balancer
- Curve
- Custom protocols
"""
module Adapters

export ProtocolAdapter, GenericAdapter
export has_liquidity, get_pool_state, format_call_data

abstract type ProtocolAdapter end

"""
    GenericAdapter

Generic CFMM adapter for standard constant product pools.
"""
struct GenericAdapter <: ProtocolAdapter
    pools::Dict{Tuple{String, String}, Float64}  # (tokenA, tokenB) => liquidity
    
    function GenericAdapter()
        new(Dict{Tuple{String, String}, Float64}())
    end
end

"""
    has_liquidity(adapter, token_in, token_out)

Check if the protocol has liquidity for the given token pair.
"""
function has_liquidity(adapter::GenericAdapter, token_in::String, token_out::String)
    return haskey(adapter.pools, (token_in, token_out)) ||
           haskey(adapter.pools, (token_out, token_in))
end

"""
    get_pool_state(adapter, token_in, token_out)

Get the current pool state for the token pair.
"""
function get_pool_state(adapter::GenericAdapter, token_in::String, token_out::String)
    key = haskey(adapter.pools, (token_in, token_out)) ? 
          (token_in, token_out) : (token_out, token_in)
    
    return get(adapter.pools, key, 0.0)
end

"""
    format_call_data(adapter, params)

Format call data according to protocol-specific requirements.
"""
function format_call_data(adapter::ProtocolAdapter, params::NamedTuple)
    # Generic formatting - override in specific adapters
    return params
end

"""
    get_adapter(protocol)

Factory function to get the appropriate adapter for a protocol.
"""
function get_adapter(protocol::Symbol)
    if protocol == :generic
        return GenericAdapter()
    else
        # Future: Return specific adapters
        return GenericAdapter()
    end
end

end # module Adapters