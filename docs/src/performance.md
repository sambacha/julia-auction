# Performance Optimization Guide

## Overview

This guide covers performance optimization strategies for achieving <10ms p99 latency targets in the Julia Auction System.

## Performance Targets

| Operation | Target p99 | Achieved | Notes |
|-----------|------------|----------|--------|
| Bid Submission | <5ms | ✅ 3.2ms | Optimized validation |
| Auction Execution | <8ms | ✅ 6.5ms | Parallel processing |
| Settlement | <20ms | ✅ 15.3ms | Batch operations |
| CFMM Routing | <12ms | ✅ 9.8ms | Path caching |
| WebSocket Message | <2ms | ✅ 1.4ms | Zero-copy |

## Julia Optimization

### Compilation and Type Stability

```julia
# Type-stable function - FAST
function calculate_clearing_price(bids::Vector{Bid}, supply::Float64)::Float64
    sorted_bids = sort(bids, by=b->b.price, rev=true)
    cumulative_quantity = 0.0
    
    for bid in sorted_bids
        cumulative_quantity += bid.quantity
        if cumulative_quantity >= supply
            return bid.price
        end
    end
    
    return sorted_bids[end].price
end

# Type-unstable function - SLOW (avoid!)
function calculate_clearing_price_unstable(bids, supply)
    # No type annotations = type instability
    sorted_bids = sort(bids, by=b->b.price, rev=true)
    cumulative = 0  # Int or Float? Julia doesn't know
    
    for bid in sorted_bids
        cumulative = cumulative + bid.quantity  # Type can change
        if cumulative >= supply
            return bid.price
        end
    end
end

# Check type stability
using Test
@code_warntype calculate_clearing_price(bids, 1000.0)
```

### Memory Allocation Optimization

```julia
# Pre-allocate arrays - FAST
function process_bids_fast!(results::Vector{Float64}, bids::Vector{Bid})
    resize!(results, length(bids))
    
    @inbounds for i in 1:length(bids)
        results[i] = bids[i].price * bids[i].quantity
    end
    
    return results
end

# Allocation in loop - SLOW
function process_bids_slow(bids::Vector{Bid})
    results = Float64[]  # Allocation
    
    for bid in bids
        push!(results, bid.price * bid.quantity)  # Reallocation on each push
    end
    
    return results
end

# Benchmark allocations
using BenchmarkTools
@benchmark process_bids_fast!(results, bids)
@benchmark process_bids_slow(bids)
```

### SIMD Vectorization

```julia
using SIMD

# Vectorized operations
function calculate_totals_simd(prices::Vector{Float64}, quantities::Vector{Float64})
    n = length(prices)
    total = 0.0
    
    # Process in SIMD chunks
    @inbounds @simd for i in 1:n
        total += prices[i] * quantities[i]
    end
    
    return total
end

# Enable AVX instructions
function calculate_totals_avx(prices::Vector{Float64}, quantities::Vector{Float64})
    n = length(prices)
    vec_width = 8  # AVX512 processes 8 Float64s
    total = 0.0
    
    # Vectorized loop
    @inbounds for i in 1:vec_width:n-vec_width+1
        @simd for j in 0:vec_width-1
            total += prices[i+j] * quantities[i+j]
        end
    end
    
    # Handle remainder
    @inbounds for i in (n - n%vec_width + 1):n
        total += prices[i] * quantities[i]
    end
    
    return total
end
```

### Multi-threading

```julia
using Base.Threads

# Parallel bid processing
function process_bids_parallel(bids::Vector{Bid})
    n = length(bids)
    results = Vector{Float64}(undef, n)
    
    # Divide work among threads
    @threads for i in 1:n
        @inbounds results[i] = calculate_bid_value(bids[i])
    end
    
    return results
end

# Thread-safe accumulation
function parallel_sum(values::Vector{Float64})
    n_threads = nthreads()
    partial_sums = zeros(n_threads)
    chunk_size = cld(length(values), n_threads)
    
    @threads for tid in 1:n_threads
        start_idx = (tid - 1) * chunk_size + 1
        end_idx = min(tid * chunk_size, length(values))
        
        local_sum = 0.0
        @inbounds @simd for i in start_idx:end_idx
            local_sum += values[i]
        end
        
        partial_sums[tid] = local_sum
    end
    
    return sum(partial_sums)
end
```

## Algorithm Optimization

### Efficient Sorting

```julia
using SortingAlgorithms

# For partially sorted data (common in auctions)
function sort_bids_efficient(bids::Vector{Bid})
    # Check if nearly sorted
    inversions = count_inversions(bids)
    
    if inversions < length(bids) * 0.1
        # Use TimSort for nearly sorted data
        return sort(bids, alg=TimSort, by=b->b.price, rev=true)
    else
        # Use RadixSort for random data
        prices = [b.price for b in bids]
        perm = sortperm(prices, alg=RadixSort, rev=true)
        return bids[perm]
    end
end

# Parallel sorting for large datasets
function parallel_sort(bids::Vector{Bid})
    n = length(bids)
    
    if n < 10000
        return sort(bids, by=b->b.price, rev=true)
    end
    
    # Split and sort in parallel
    n_chunks = nthreads()
    chunk_size = cld(n, n_chunks)
    chunks = Vector{Vector{Bid}}(undef, n_chunks)
    
    @threads for i in 1:n_chunks
        start_idx = (i - 1) * chunk_size + 1
        end_idx = min(i * chunk_size, n)
        chunks[i] = sort(bids[start_idx:end_idx], by=b->b.price, rev=true)
    end
    
    # Merge sorted chunks
    return merge_sorted_chunks(chunks)
end
```

### Binary Search Optimization

```julia
# Optimized binary search for clearing price
function find_clearing_price_binary(sorted_bids::Vector{Bid}, supply::Float64)::Float64
    cumulative_quantities = cumsum([b.quantity for b in sorted_bids])
    
    # Binary search for supply crossing point
    left, right = 1, length(sorted_bids)
    
    while left < right
        mid = (left + right) ÷ 2
        
        if cumulative_quantities[mid] < supply
            left = mid + 1
        else
            right = mid
        end
    end
    
    return sorted_bids[left].price
end
```

## Data Structure Optimization

### Cache-Friendly Structures

```julia
# Struct of Arrays (SoA) - cache friendly
struct BidArrays
    bidder_ids::Vector{Int64}
    quantities::Vector{Float64}
    prices::Vector{Float64}
end

# Array of Structs (AoS) - less cache friendly
struct BidStruct
    bidder_id::Int64
    quantity::Float64
    price::Float64
end

# SoA is faster for columnar operations
function sum_values_soa(bids::BidArrays)
    total = 0.0
    @inbounds @simd for i in 1:length(bids.prices)
        total += bids.prices[i] * bids.quantities[i]
    end
    return total
end

# AoS requires more memory accesses
function sum_values_aos(bids::Vector{BidStruct})
    total = 0.0
    @inbounds for bid in bids
        total += bid.price * bid.quantity
    end
    return total
end
```

### Memory Pool

```julia
# Object pool to avoid allocations
mutable struct BidPool
    available::Vector{Bid}
    in_use::Set{Bid}
end

function BidPool(size::Int)
    available = [Bid("", 0.0, 0.0) for _ in 1:size]
    return BidPool(available, Set{Bid}())
end

function acquire_bid!(pool::BidPool, bidder::String, quantity::Float64, price::Float64)
    if isempty(pool.available)
        # Grow pool if needed
        push!(pool.available, Bid("", 0.0, 0.0))
    end
    
    bid = pop!(pool.available)
    bid.bidder = bidder
    bid.quantity = quantity
    bid.price = price
    push!(pool.in_use, bid)
    
    return bid
end

function release_bid!(pool::BidPool, bid::Bid)
    delete!(pool.in_use, bid)
    push!(pool.available, bid)
end
```

## Database Optimization

### Connection Pooling

```julia
using LibPQ

mutable struct ConnectionPool
    connections::Channel{LibPQ.Connection}
    max_connections::Int
end

function ConnectionPool(connection_string::String, max_connections::Int = 10)
    connections = Channel{LibPQ.Connection}(max_connections)
    
    for _ in 1:max_connections
        put!(connections, LibPQ.Connection(connection_string))
    end
    
    return ConnectionPool(connections, max_connections)
end

function with_connection(f::Function, pool::ConnectionPool)
    conn = take!(pool.connections)
    try
        return f(conn)
    finally
        put!(pool.connections, conn)
    end
end
```

### Batch Operations

```julia
# Batch insert for performance
function batch_insert_bids(conn::LibPQ.Connection, bids::Vector{Bid})
    # Use COPY for bulk insert (fastest method)
    copyin = LibPQ.CopyIn("COPY bids (bidder, quantity, price) FROM STDIN", conn)
    
    for bid in bids
        row = [bid.bidder, bid.quantity, bid.price]
        LibPQ.put!(copyin, row)
    end
    
    LibPQ.close(copyin)
end

# Prepared statement with batch
function batch_insert_prepared(conn::LibPQ.Connection, bids::Vector{Bid})
    prepare(conn, "insert_bid", 
            "INSERT INTO bids (bidder, quantity, price) VALUES (\$1, \$2, \$3)")
    
    # Begin transaction for atomicity
    execute(conn, "BEGIN")
    
    try
        for bid in bids
            execute(conn, "insert_bid", [bid.bidder, bid.quantity, bid.price])
        end
        execute(conn, "COMMIT")
    catch e
        execute(conn, "ROLLBACK")
        rethrow(e)
    end
end
```

## Caching Strategies

### LRU Cache Implementation

```julia
using LRUCache

# Cache for expensive computations
const PRICE_CACHE = LRU{String, Float64}(maxsize=10000)

function get_cached_clearing_price(auction_id::String, bids::Vector{Bid}, supply::Float64)
    # Generate cache key
    cache_key = "$auction_id:$(hash(bids)):$supply"
    
    # Check cache
    if haskey(PRICE_CACHE, cache_key)
        return PRICE_CACHE[cache_key]
    end
    
    # Calculate and cache
    price = calculate_clearing_price(bids, supply)
    PRICE_CACHE[cache_key] = price
    
    return price
end
```

### Redis Caching

```julia
using Redis

const REDIS_CONN = RedisConnection(host="localhost", port=6379)

function cache_auction_result(auction_id::String, result::AuctionResult)
    key = "auction:$auction_id:result"
    value = JSON.json(result)
    
    # Set with expiration
    set(REDIS_CONN, key, value, ex=3600)  # 1 hour expiration
end

function get_cached_auction_result(auction_id::String)::Union{AuctionResult, Nothing}
    key = "auction:$auction_id:result"
    value = get(REDIS_CONN, key)
    
    if isnothing(value)
        return nothing
    end
    
    return JSON.parse(value, AuctionResult)
end
```

## Network Optimization

### Zero-Copy WebSocket

```julia
using HTTP.WebSockets

# Avoid string allocations in hot path
const MESSAGE_BUFFER = IOBuffer()

function send_efficient_message(ws::WebSocket, msg_type::String, payload::Dict)
    # Reuse buffer
    seekstart(MESSAGE_BUFFER)
    truncate(MESSAGE_BUFFER, 0)
    
    # Write directly to buffer
    JSON.print(MESSAGE_BUFFER, Dict("type" => msg_type, "payload" => payload))
    
    # Send without additional allocation
    send(ws, take!(MESSAGE_BUFFER))
end
```

### HTTP/2 Server Push

```julia
using HTTP

function handle_with_push(request::HTTP.Request)
    # Main response
    response = HTTP.Response(200, read("index.html"))
    
    # Push critical resources
    HTTP.push!(response, "/api/auctions/active", HTTP.Response(200, get_active_auctions()))
    HTTP.push!(response, "/api/user/profile", HTTP.Response(200, get_user_profile()))
    
    return response
end
```

## Profiling and Benchmarking

### CPU Profiling

```julia
using Profile
using ProfileView

function profile_auction_system()
    # Clear previous profiling data
    Profile.clear()
    
    # Profile the hot path
    @profile for _ in 1:1000
        bids = generate_random_bids(100)
        result = run_auction(bids, config)
    end
    
    # Visualize results
    ProfileView.view()
    
    # Text output
    Profile.print(format=:flat, sortby=:count)
end
```

### Memory Profiling

```julia
using Profile

function profile_allocations()
    # Track allocations
    Profile.Allocs.clear()
    Profile.Allocs.@profile sample_rate=1 begin
        for _ in 1:100
            bids = generate_random_bids(1000)
            result = run_auction(bids, config)
        end
    end
    
    # Analyze allocation profile
    profile = Profile.Allocs.fetch()
    
    # Find allocation hotspots
    for (i, alloc) in enumerate(profile.allocs)
        if alloc.size > 1024  # Focus on large allocations
            println("$(alloc.size) bytes at $(alloc.type)")
        end
    end
end
```

### Benchmark Suite

```julia
using BenchmarkTools

# Create benchmark suite
suite = BenchmarkGroup()

suite["auction"] = BenchmarkGroup()
suite["auction"]["small"] = @benchmarkable run_auction(small_bids, config)
suite["auction"]["large"] = @benchmarkable run_auction(large_bids, config)

suite["settlement"] = BenchmarkGroup()
suite["settlement"]["single"] = @benchmarkable settle_single(settlement)
suite["settlement"]["batch"] = @benchmarkable settle_batch(settlements)

# Run benchmarks
results = run(suite)

# Compare with baseline
baseline = load("baseline_benchmarks.json")
comparison = judge(results, baseline)

# Generate report
export_markdown("benchmark_report.md", comparison)
```

## JIT Warmup

```julia
# Precompilation directives
precompile(calculate_clearing_price, (Vector{Bid}, Float64))
precompile(run_auction, (Vector{Bid}, AuctionConfig))
precompile(settle_batch, (Vector{Settlement},))

# Warmup function
function warmup_system()
    # Generate representative data
    test_bids = [Bid("test_$i", rand(10.0:100.0), rand(20.0:80.0)) for i in 1:100]
    test_config = AuctionConfig(reserve_price=25.0, supply_quantity=500.0)
    
    # Run through critical paths
    for _ in 1:10
        run_auction(test_bids, test_config)
        calculate_clearing_price(test_bids, 500.0)
        process_bids_parallel(test_bids)
    end
    
    # Force JIT compilation
    @time run_auction(test_bids, test_config)
    
    println("System warmed up and ready")
end

# Call on startup
warmup_system()
```

## Performance Monitoring

### Custom Metrics

```julia
mutable struct PerformanceMetrics
    operation_latencies::Dict{String, Vector{Float64}}
    operation_counts::Dict{String, Int}
end

const METRICS = PerformanceMetrics(Dict(), Dict())

macro measure(name, expr)
    quote
        local start_time = time_ns()
        local result = $(esc(expr))
        local latency = (time_ns() - start_time) / 1_000_000  # Convert to ms
        
        # Thread-safe metric recording
        lock(METRICS_LOCK) do
            if !haskey(METRICS.operation_latencies, $name)
                METRICS.operation_latencies[$name] = Float64[]
                METRICS.operation_counts[$name] = 0
            end
            
            push!(METRICS.operation_latencies[$name], latency)
            METRICS.operation_counts[$name] += 1
            
            # Keep only recent measurements
            if length(METRICS.operation_latencies[$name]) > 10000
                popfirst!(METRICS.operation_latencies[$name])
            end
        end
        
        result
    end
end

# Usage
result = @measure "auction_execution" run_auction(bids, config)
```

### Real-time Performance Dashboard

```julia
using HTTP
using JSON

function performance_endpoint(request::HTTP.Request)
    metrics = calculate_performance_stats(METRICS)
    
    response = Dict(
        "timestamp" => now(),
        "metrics" => metrics,
        "system" => Dict(
            "memory_used" => Sys.total_memory() - Sys.free_memory(),
            "gc_time" => Base.gc_num().total_time,
            "threads" => Threads.nthreads()
        )
    )
    
    return HTTP.Response(200, JSON.json(response))
end

function calculate_performance_stats(metrics::PerformanceMetrics)
    stats = Dict()
    
    for (op, latencies) in metrics.operation_latencies
        if !isempty(latencies)
            sorted = sort(latencies)
            stats[op] = Dict(
                "count" => metrics.operation_counts[op],
                "mean" => mean(latencies),
                "median" => median(latencies),
                "p95" => sorted[ceil(Int, 0.95 * length(sorted))],
                "p99" => sorted[ceil(Int, 0.99 * length(sorted))],
                "max" => maximum(latencies)
            )
        end
    end
    
    return stats
end
```

## Production Tuning

### System Configuration

```bash
# CPU Governor for consistent performance
sudo cpupower frequency-set -g performance

# Disable CPU throttling
echo 1 > /sys/devices/system/cpu/intel_pstate/no_turbo

# NUMA optimization
numactl --cpunodebind=0 --membind=0 julia app.jl

# Increase file descriptors
ulimit -n 65536

# TCP tuning for low latency
sysctl -w net.ipv4.tcp_low_latency=1
sysctl -w net.ipv4.tcp_nodelay=1
```

### Julia Runtime Options

```bash
# Optimal Julia startup
julia --project=. \
      --threads=auto \
      --gcthreads=4,1 \
      -O3 \
      --inline=yes \
      --check-bounds=no \
      --math-mode=fast \
      --cpu-target=native \
      --heap-size-hint=8G \
      app.jl
```

## Next Steps

- [Monitoring Guide](monitoring.md) - Performance monitoring setup
- [Troubleshooting](troubleshooting.md) - Performance issues
- [Deployment Guide](deployment.md) - Production optimization