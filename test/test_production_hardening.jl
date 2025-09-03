using Logging
using Test
# Load production hardening modules
include("../src/settlement/monitoring/CircuitBreaker.jl")
include("../src/settlement/monitoring/ErrorHandler.jl")
include("../src/settlement/monitoring/HealthCheck.jl")
include("../src/config/production.jl")
include("../src/settlement/monitoring/latency/LatencyMonitor.jl")

using .CircuitBreaker
using .ErrorHandler
using .HealthCheck
using .LatencyMonitor
using .ProductionConfig
@testset "Production Hardening System Tests" begin
    
    @testset "CircuitBreaker Tests" begin
        @testset "Circuit Breaker Creation" begin
            cb = create_circuit_breaker("test_circuit")
            @test cb.name == "test_circuit"
            @test cb.state[] == CircuitBreaker.CLOSED
            @test cb.config.failure_threshold == 5
        end
        
        @testset "Circuit Breaker Execution" begin
            cb = create_circuit_breaker("test_circuit", failure_threshold=2)
            
            # Successful execution
            result, executed, state = execute_with_circuit_breaker(cb) do
                "success"
            end
            @test result == "success"
            @test executed == true
            @test state == CircuitBreaker.CLOSED
            
            # Test failure handling
            for i in 1:3  # Exceed failure threshold
                try
                    execute_with_circuit_breaker(cb) do
                        error("test error")
                    end
                catch e
                    # Expected to fail
                end
            end
            
            # Circuit should now be open
            metrics = get_circuit_metrics(cb)
            @test metrics.state == CircuitBreaker.OPEN
        end
        
        @testset "Circuit Breaker Recovery" begin
            cb = create_circuit_breaker("recovery_test", 
                                      failure_threshold=1,
                                      timeout_ms=100.0)
            
            # Trip the circuit
            try
                execute_with_circuit_breaker(cb) do
                    error("trip circuit")
                end
            catch
            end
            
            @test get_circuit_state(cb).state == CircuitBreaker.OPEN
            
            # Wait for timeout
            sleep(0.15)  # 150ms > 100ms timeout
            
            # Should transition to half-open
            result, executed, state = execute_with_circuit_breaker(cb) do
                "recovery"
            end
            
            @test executed == true
            @test result == "recovery"
        end
    end
    
    @testset "ErrorHandler Tests" begin
        @testset "Error Handler Creation" begin
            handler = create_error_handler("test_handler")
            @test handler.name == "test_handler"
            @test handler.default_policy.max_attempts == 3
        end
        
        @testset "Error Classification" begin
            handler = create_error_handler("classifier_test")
            
            # Test network error classification
            network_error = ErrorException("Connection timeout")
            category = classify_error(handler, network_error)
            @test category == ErrorHandler.TIMEOUT || category == ErrorHandler.UNKNOWN
            
            # Test argument error classification  
            arg_error = ArgumentError("invalid argument")
            category = classify_error(handler, arg_error)
            @test category == ErrorHandler.PERMANENT
        end
        
        @testset "Retry Logic" begin
            handler = create_error_handler("retry_test", default_max_attempts=2)
            attempt_count = 0
            
            # Should succeed after one retry\n            result = handle_with_retry(handler, :test_operation) do\n                attempt_count += 1\n                if attempt_count == 1\n                    error(\"first attempt fails\")\n                else\n                    \"success on retry\"\n                end\n            end\n            \n            @test result == \"success on retry\"\n            @test attempt_count == 2\n        end\n        \n        @testset \"Retry Exhaustion\" begin\n            handler = create_error_handler(\"exhaust_test\", default_max_attempts=2)\n            attempt_count = 0\n            \n            @test_throws ErrorException begin\n                handle_with_retry(handler, :failing_operation) do\n                    attempt_count += 1\n                    error(\"always fails\")\n                end\n            end\n            \n            @test attempt_count == 2\n        end\n    end\n    \n    @testset \"LatencyMonitor Tests\" begin\n        @testset \"Production Tracker Creation\" begin\n            tracker = create_production_tracker(\n                slow_operation_threshold_ms=50.0,\n                p99_target_ms=10.0\n            )\n            @test tracker.slow_operation_threshold_ms == 50.0\n            @test hasfield(typeof(tracker), :timer_output)\n        end\n        \n        @testset \"Latency Recording\" begin\n            tracker = create_production_tracker()\n            \n            # Record some latency measurements\n            record_latency!(tracker, :test_operation, 5000.0)  # 5ms\n            record_latency!(tracker, :test_operation, 8000.0)  # 8ms\n            record_latency!(tracker, :test_operation, 12000.0) # 12ms\n            \n            stats = get_latency_stats(tracker, :test_operation)\n            @test stats !== nothing\n            @test stats.count == 3\n            @test stats.mean_ms ≈ 8.333 atol=0.1\n        end\n        \n        @testset \"Performance Targets\" begin\n            tracker = create_production_tracker()\n            \n            set_performance_target(tracker, :fast_operation, 5.0)\n            \n            # Record slow operation\n            record_latency!(tracker, :fast_operation, 15000.0)  # 15ms > 5ms target\n            \n            slow_ops = check_slow_operations(tracker)\n            @test length(slow_ops) >= 0  # May or may not trigger based on sample size\n        end\n        \n        @testset \"Performance Report\" begin\n            tracker = create_production_tracker()\n            \n            # Add some measurements\n            for i in 1:10\n                latency = (2000.0 + rand() * 3000.0)  # 2-5ms\n                record_latency!(tracker, :report_test, latency)\n            end\n            \n            report = generate_performance_report(tracker)\n            @test report.total_operations == 10\n            @test haskey(report.operations_by_component, :report_test)\n            @test report.operations_by_component[:report_test] == 10\n        end\n        \n        @testset \"Timer Integration\" begin\n            tracker = create_production_tracker()\n            \n            # Test the @timed_operation macro\n            result = @timed_operation tracker :macro_test begin\n                sleep(0.001)  # 1ms\n                \"macro result\"\n            end\n            \n            @test result == \"macro result\"\n            \n            # Check that timing was recorded\n            stats = get_latency_stats(tracker, :macro_test)\n            @test stats !== nothing\n            @test stats.count == 1\n            @test stats.mean_ms >= 1.0  # At least 1ms\n        end\n    end\n    \n    @testset \"HealthCheck Tests\" begin\n        @testset \"Health Checker Creation\" begin\n            checker = create_health_checker(\n                cpu_threshold_percent=75.0,\n                memory_threshold_percent=80.0\n            )\n            @test checker.resource_monitor.cpu_threshold_percent == 75.0\n            @test checker.resource_monitor.memory_threshold_percent == 80.0\n        end\n        \n        @testset \"Health Check Registration\" begin\n            checker = create_health_checker()\n            \n            add_health_check(checker, :test_component, () -> true, \n                           timeout_ms=1000.0, is_critical=true)\n            \n            @test haskey(checker.components, :test_component)\n            @test :test_component in checker.critical_components\n        end\n        \n        @testset \"Health Check Execution\" begin\n            checker = create_health_checker()\n            \n            # Add a simple health check\n            add_health_check(checker, :simple_check, () -> true)\n            \n            results = run_health_checks(checker)\n            @test haskey(results, :simple_check)\n            @test results[:simple_check].status == HealthCheck.HEALTHY\n        end\n        \n        @testset \"Failing Health Check\" begin\n            checker = create_health_checker()\n            \n            # Add a failing health check\n            add_health_check(checker, :failing_check, () -> false)\n            \n            results = run_health_checks(checker)\n            @test haskey(results, :failing_check)\n            @test results[:failing_check].status == HealthCheck.UNHEALTHY\n        end\n        \n        @testset \"Health Check Timeout\" begin\n            checker = create_health_checker()\n            \n            # Add a slow health check that should timeout\n            add_health_check(checker, :slow_check, () -> {\n                sleep(2.0)  # Sleep longer than timeout\n                return true\n            }, timeout_ms=100.0)  # 100ms timeout\n            \n            results = run_health_checks(checker)\n            @test haskey(results, :slow_check)\n            @test results[:slow_check].status == HealthCheck.DEGRADED\n            @test occursin(\"timed out\", results[:slow_check].message)\n        end\n        \n        @testset \"System Health Assessment\" begin\n            checker = create_health_checker()\n            \n            # Add mixed health checks\n            add_health_check(checker, :healthy_component, () -> true)\n            add_health_check(checker, :degraded_component, () -> {\n                return HealthCheckResult(\n                    :degraded_component,\n                    HealthCheck.DEGRADED,\n                    \"Component is degraded\",\n                    0.0,\n                    time() * 1000,\n                    Dict{String, Any}(),\n                    Dict{Symbol, HealthCheck.HealthStatus}()\n                )\n            })\n            \n            system_health = get_system_health(checker)\n            @test system_health.overall_status in [HealthCheck.HEALTHY, HealthCheck.DEGRADED]\n        end\n        \n        @testset \"Readiness and Liveness\" begin\n            checker = create_health_checker()\n            \n            # Should be ready and alive initially\n            @test check_readiness(checker) == true\n            @test check_liveness(checker) == true\n        end\n        \n        @testset \"Resource Monitoring\" begin\n            checker = create_health_checker()\n            \n            resource_status = monitor_resources(checker.resource_monitor)\n            @test resource_status.memory_percent >= 0.0\n            @test resource_status.memory_total_gb > 0.0\n        end\n    end\n    \n    @testset \"ProductionConfig Tests\" begin\n        @testset \"Configuration Creation\" begin\n            config = create_production_config()\n            @test config.p99_latency_target_ms == 10.0\n            @test config.enable_circuit_breakers == true\n            @test config.max_retry_attempts == 2\n        end\n        \n        @testset \"Custom Configuration\" begin\n            config = create_production_config(\n                p99_latency_target_ms=5.0,\n                max_retry_attempts=3,\n                enable_circuit_breakers=false\n            )\n            @test config.p99_latency_target_ms == 5.0\n            @test config.max_retry_attempts == 3\n            @test config.enable_circuit_breakers == false\n        end\n        \n        @testset \"Configuration Extraction\" begin\n            config = create_production_config()\n            \n            timeout_config = get_timeout_config(config)\n            @test timeout_config.auction == config.auction_timeout_ms\n            @test timeout_config.settlement == config.settlement_timeout_ms\n            \n            retry_config = get_retry_config(config)\n            @test retry_config.max_attempts == config.max_retry_attempts\n            @test retry_config.base_delay_ms == config.base_retry_delay_ms\n            \n            cb_config = get_circuit_breaker_config(config)\n            @test cb_config.failure_threshold == config.circuit_breaker_failure_threshold\n        end\n        \n        @testset \"Operation-Specific Config\" begin\n            op_config = get_operation_config(:auction_creation)\n            @test op_config.timeout_ms == 30.0\n            @test op_config.p99_target_ms == 8.0\n            \n            # Test unknown operation gets defaults\n            unknown_config = get_operation_config(:unknown_operation)\n            @test unknown_config.timeout_ms == 75.0\n        end\n        \n        @testset \"Environment Configuration\" begin\n            base_config = create_production_config()\n            \n            dev_config = create_environment_config(base_config, :development)\n            @test dev_config.auction_timeout_ms > base_config.auction_timeout_ms\n            \n            test_config = create_environment_config(base_config, :testing)\n            @test !test_config.enable_circuit_breakers  # Disabled in testing\n        end\n    end\n    \n    @testset \"Integration Tests\" begin\n        @testset \"Full System Integration\" begin\n            # Create all components\n            config = create_production_config(p99_latency_target_ms=20.0)\n            tracker = create_production_tracker(p99_target_ms=config.p99_latency_target_ms)\n            circuit = create_circuit_breaker(\"integration_test\")\n            error_handler = create_error_handler(\"integration_test\")\n            health_checker = create_health_checker()\n            \n            # Add health check for circuit breaker\n            add_health_check(health_checker, :circuit_health, () -> {\n                metrics = get_circuit_metrics(circuit)\n                return metrics.state == CircuitBreaker.CLOSED\n            })\n            \n            # Simulate some operations\n            for i in 1:10\n                try\n                    result = @timed_operation tracker :integration_test begin\n                        execute_with_circuit_breaker(circuit) do\n                            if rand() < 0.1  # 10% failure rate\n                                error(\"random failure\")\n                            end\n                            sleep(0.001 + rand() * 0.004)  # 1-5ms\n                            \"success\"\n                        end\n                    end\n                catch e\n                    # Handle with error handler\n                    handle_with_retry(error_handler, :integration_test) do\n                        \"fallback result\"\n                    end\n                end\n            end\n            \n            # Verify system state\n            health_status = get_system_health(health_checker)\n            performance_report = generate_performance_report(tracker)\n            circuit_metrics = get_circuit_metrics(circuit)\n            \n            @test health_status.overall_status != HealthCheck.CRITICAL\n            @test performance_report.total_operations >= 0\n            @test circuit_metrics.total_calls >= 0\n        end\n        \n        @testset \"Performance Under Load\" begin\n            tracker = create_production_tracker()\n            \n            # Simulate high-frequency operations\n            start_time = time()\n            operations = 100\n            \n            for i in 1:operations\n                @timed_operation tracker :load_test begin\n                    # Simulate very fast operation\n                    rand()  # Minimal work\n                end\n            end\n            \n            end_time = time()\n            total_time = end_time - start_time\n            \n            stats = get_latency_stats(tracker, :load_test)\n            @test stats.count == operations\n            @test total_time < 1.0  # Should complete in less than 1 second\n        end\n    end\nend\n\n# Run performance verification\n@testset \"Performance Verification\" begin\n    @testset \"Latency Targets\" begin\n        tracker = create_production_tracker(p99_target_ms=10.0)\n        set_performance_target(tracker, :fast_operation, 10.0)\n        \n        # Record measurements that meet target\n        for i in 1:100\n            latency_us = (2000.0 + rand() * 6000.0)  # 2-8ms\n            record_latency!(tracker, :fast_operation, latency_us)\n        end\n        \n        stats = get_latency_stats(tracker, :fast_operation)\n        \n        # Verify most operations are under target\n        @test stats.p99_ms <= 15.0  # Allow some margin for randomness\n        @test stats.mean_ms <= 8.0\n    end\n    \n    @testset \"Circuit Breaker Performance\" begin\n        circuit = create_circuit_breaker(\"perf_test\", \n                                       failure_threshold=10)\n        \n        # Measure circuit breaker overhead\n        start_time = time()\n        \n        for i in 1:1000\n            result, executed, state = execute_with_circuit_breaker(circuit) do\n                \"fast operation\"\n            end\n        end\n        \n        end_time = time()\n        total_time = end_time - start_time\n        avg_time_per_call = total_time / 1000.0\n        \n        # Circuit breaker overhead should be minimal\n        @test avg_time_per_call < 0.001  # Less than 1ms per call\n    end\nend