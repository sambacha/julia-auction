# Julia Style Guide

## Code Style Standards

### Naming Conventions

```julia
# Functions: snake_case
function calculate_clearing_price(bids, supply)
    # ...
end

# Types: UpperCamelCase  
struct AuctionResult
    clearing_price::Float64
    allocations::Vector{Allocation}
end

# Constants: UPPER_SNAKE_CASE
const MAX_BATCH_SIZE = 1000
const DEFAULT_TIMEOUT = 30.0

# Variables: snake_case
auction_result = run_auction(bids, config)
```

### Type Annotations

Always use type annotations for:
- Function parameters
- Function return types
- Struct fields

```julia
# Good - type stable
function process_bid(bid::Bid, reserve_price::Float64)::Bool
    return bid.price >= reserve_price
end

# Bad - type unstable
function process_bid(bid, reserve_price)
    return bid.price >= reserve_price
end
```

### Line Length

Keep lines under 92 characters:

```julia
# Good - proper line breaking
result = calculate_complex_value(
    first_parameter,
    second_parameter,
    third_parameter
)

# Bad - line too long
result = calculate_complex_value(first_parameter, second_parameter, third_parameter, fourth_parameter)
```

### Indentation

Use 4 spaces (never tabs):

```julia
function example()
    if condition
        for i in 1:10
            process(i)
        end
    end
end
```

### Module Organization

```julia
module AuctionSystem

# Exports at the top
export run_auction, calculate_clearing_price

# Imports next
using Base.Threads
using DataStructures

# Types
struct Bid
    bidder::String
    quantity::Float64
    price::Float64
end

# Functions
function run_auction(bids::Vector{Bid}, config::Config)
    # Implementation
end

end # module
```

### Error Handling

```julia
# Use specific error types
struct AuctionError <: Exception
    message::String
end

# Provide helpful error messages
function validate_bid(bid::Bid)
    if bid.quantity <= 0
        throw(AuctionError("Bid quantity must be positive, got $(bid.quantity)"))
    end
end
```

### Documentation

Every exported function needs documentation:

```julia
"""
    run_auction(bids::Vector{Bid}, config::Config) -> AuctionResult

Run a uniform price auction with the given bids and configuration.

See also: [`calculate_clearing_price`](@ref), [`AuctionResult`](@ref)
"""
function run_auction(bids::Vector{Bid}, config::Config)
    # Implementation
end
```

### Testing

```julia
# Use @testset for organization
@testset "Auction Tests" begin
    @testset "Basic functionality" begin
        @test calculate_clearing_price(bids, 100.0) == 45.0
    end
    
    @testset "Edge cases" begin
        @test_throws AuctionError run_auction([], config)
    end
end
```

### Performance Considerations

```julia
# Preallocate arrays
function process_bids(bids::Vector{Bid})
    results = Vector{Float64}(undef, length(bids))  # Preallocate
    
    @inbounds for i in 1:length(bids)
        results[i] = bids[i].price * bids[i].quantity
    end
    
    return results
end

# Use @inbounds when safe
@inbounds for i in 1:length(array)
    array[i] = compute_value(i)
end
```

## Common Patterns

### Builder Pattern

```julia
mutable struct AuctionBuilder
    config::AuctionConfig
end

function AuctionBuilder()
    AuctionBuilder(AuctionConfig())
end

function with_reserve_price(builder::AuctionBuilder, price::Float64)
    builder.config.reserve_price = price
    return builder
end

function build(builder::AuctionBuilder)
    return Auction(builder.config)
end

# Usage
auction = AuctionBuilder() |>
    b -> with_reserve_price(b, 20.0) |>
    b -> with_supply(b, 1000.0) |>
    build
```

### Result Types

```julia
struct Result{T}
    value::Union{T, Nothing}
    error::Union{String, Nothing}
end

is_success(r::Result) = !isnothing(r.value)
is_error(r::Result) = !isnothing(r.error)

# Usage
function safe_divide(a::Float64, b::Float64)::Result{Float64}
    if b == 0
        return Result{Float64}(nothing, "Division by zero")
    end
    return Result{Float64}(a / b, nothing)
end
```

## Anti-patterns to Avoid

### ❌ Using Any Types
```julia
# Bad
function process(data::Any)
    # ...
end

# Good
function process(data::Union{String, Int, Float64})
    # ...
end
```

### ❌ Global Mutable State
```julia
# Bad
global counter = 0
function increment()
    global counter += 1
end

# Good
mutable struct Counter
    value::Int
end
increment!(c::Counter) = c.value += 1
```

### ❌ Magic Numbers
```julia
# Bad
if bid.price > 100.0
    # ...
end

# Good
const MAX_BID_PRICE = 100.0
if bid.price > MAX_BID_PRICE
    # ...
end
```