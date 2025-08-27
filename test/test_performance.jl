# Performance and benchmarking tests
using BenchmarkTools
using Random
using Test
@testset "Performance Tests" begin
    @testset "Scalability Tests" begin
        # Test performance with different scales
        scales = [10, 100, 1000]
        
        for scale in scales
            @testset "Scale: $scale bidders" begin
                # Create test data
                bidders = [TruthfulBidder(i, rand(10.0:100.0)) for i in 1:scale]
                bids = [Bid(b.id, generate_bid(b, FirstPriceAuction())) for b in bidders]
                auction = FirstPriceAuction(reserve_price=5.0)
                
                # Benchmark auction execution
                benchmark_result = @benchmark run_auction($auction, $bids)
                
                # Performance should be reasonable
                median_time = median(benchmark_result.times)
                @test median_time < 1e8  # Less than 100ms for reasonable scales
                
                # Memory allocation should be bounded
                @test benchmark_result.memory < scale * 1000  # Linear scaling
            end
        end
    end
    
    @testset "Algorithm Complexity Tests" begin
        # Test that algorithms scale appropriately
        Random.seed!(456)
        
        # Test bid sorting performance (should be O(n log n))
        sizes = [100, 200, 400, 800]
        times = Float64[]
        
        for size in sizes
            bids = [Bid(i, rand(1.0:100.0)) for i in 1:size]
            auction = SecondPriceAuction(reserve_price=1.0)
            
            # Measure time
            time_result = @elapsed run_auction(auction, bids)
            push!(times, time_result)
        end
        
        # Check that growth is approximately O(n log n)
        # Time should not increase faster than quadratically
        for i in 2:length(times)
            ratio = times[i] / times[i-1]
            size_ratio = sizes[i] / sizes[i-1]
            @test ratio < size_ratio^2  # Should grow slower than quadratically
        end
    end
    
    @testset "Memory Usage Tests" begin
        # Test memory usage patterns
        Random.seed!(789)
        
        # Test that memory usage is reasonable
        function memory_test(n_bidders, n_auctions)
            config = SimulationConfig(
                n_bidders=n_bidders,
                n_auctions=n_auctions,
                valuation_distribution=:uniform,
                valuation_range=(10.0, 100.0),
                auction_type=:first_price
            )
            
            # Measure memory allocation
            alloc = @allocated run_simulation(config)
            return alloc
        end
        
        # Test different scales
        small_alloc = memory_test(5, 10)
        medium_alloc = memory_test(10, 20)
        large_alloc = memory_test(20, 40)
        
        # Memory should scale reasonably
        @test small_alloc > 0
        @test medium_alloc > small_alloc
        @test large_alloc > medium_alloc
        
        # But not excessively
        @test medium_alloc < small_alloc * 10
        @test large_alloc < medium_alloc * 10
    end
    
    @testset "Parallel Processing Tests" begin
        # Test parallel processing capabilities if available
        if Threads.nthreads() > 1
            @testset "Multi-threading Performance" begin
                Random.seed!(101112)
                
                # Create large simulation
                config = SimulationConfig(
                    n_bidders=50,
                    n_auctions=200,
                    valuation_distribution=:uniform,
                    valuation_range=(10.0, 100.0),
                    auction_type=:first_price
                )
                
                # Compare single-threaded vs multi-threaded performance
                single_time = @elapsed run_simulation(config, parallel=false)
                multi_time = @elapsed run_simulation(config, parallel=true)
                
                # Multi-threaded should be faster (or at least not much slower)
                @test multi_time <= single_time * 1.5  # Allow some overhead
            end
        end
    end
    
    @testset "Regression Tests" begin
        # Test that performance doesn't regress over time
        # These are baseline performance expectations
        
        @testset "Baseline Performance" begin
            Random.seed!(131415)
            
            # Standard benchmark scenario
            config = SimulationConfig(
                n_bidders=20,
                n_auctions=100,
                valuation_distribution=:uniform,
                valuation_range=(10.0, 100.0),
                auction_type=:first_price
            )
            
            # Measure performance
            time_taken = @elapsed run_simulation(config)
            
            # Should complete in reasonable time
            @test time_taken < 2.0  # Should complete in under 2 seconds
            
            # Memory usage should be reasonable
            memory_used = @allocated run_simulation(config)
            @test memory_used < 1_000_000  # Should use less than 1MB
        end
        
        @testset "Stress Tests" begin
            # Test system under stress
            Random.seed!(161718)
            
            # Large scale test
            stress_config = SimulationConfig(
                n_bidders=100,
                n_auctions=500,
                valuation_distribution=:uniform,
                valuation_range=(1.0, 1000.0),
                auction_type=:second_price
            )
            
            # Should complete without errors
            @test_nowarn run_simulation(stress_config)
            
            # Performance should still be reasonable
            stress_time = @elapsed run_simulation(stress_config)
            @test stress_time < 30.0  # Should complete in under 30 seconds
        end
    end
end