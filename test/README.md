# Julia Auction System Test Suite

This directory contains a comprehensive test suite for the Julia auction system, covering all major components and edge cases.

## Test Structure

### Main Test Files

1. **`runtests.jl`** - Main test runner that executes all tests
2. **`test_config.jl`** - Test configuration, utilities, and helper functions
3. **`test_types.jl`** - Extended type system tests
4. **`test_performance.jl`** - Performance and benchmarking tests  
5. **`test_edge_cases.jl`** - Edge cases and boundary condition tests

### Test Categories

#### 1. Type System Tests
- **AbstractBidder Type Tests**: Validates abstract type hierarchy
- **Bidder Type Tests**: Tests concrete bidder implementations
- **Bid Type Tests**: Validates bid structure and constraints
- **AuctionResult Type Tests**: Tests auction result validity
- **Type Interface Tests**: Ensures all types implement required interfaces
- **Type Stability Tests**: Validates type inference and stability
- **Memory Efficiency Tests**: Tests memory usage patterns

#### 2. Auction Mechanism Tests
- **FirstPriceAuction Tests**: 
  - Basic functionality and correctness
  - Reserve price handling
  - Single bid scenarios
  - Tie breaking mechanisms
  - Empty auction handling
- **SecondPriceAuction Tests**:
  - Second price payment verification
  - Truthful bidding incentives
  - Reserve price interactions
  - Strategic bidding scenarios

#### 3. Bidding Strategy Tests
- **TruthfulBidder Tests**: Validates truthful bidding behavior
- **ShadedBidder Tests**: Tests bid shading strategies
- **RandomBidder Tests**: Tests random bidding with bounds
- **Strategy Consistency Tests**: Ensures strategies behave appropriately across auction types

#### 4. Simulation Engine Tests
- **Basic Simulation Tests**: End-to-end simulation workflows
- **Reproducibility Tests**: Ensures consistent results with same random seed
- **Configuration Tests**: Validates simulation parameter handling
- **Scale Tests**: Tests performance with different problem sizes

#### 5. Performance and Benchmarking Tests
- **Scalability Tests**: Performance with increasing problem sizes
- **Algorithm Complexity Tests**: Validates expected algorithmic complexity
- **Memory Usage Tests**: Tracks memory allocation patterns
- **Regression Tests**: Ensures performance doesn't degrade over time
- **Stress Tests**: System behavior under high load

#### 6. Edge Cases and Boundary Tests
- **Extreme Value Tests**: Very small and very large numerical values
- **Degenerate Cases**: Empty auctions, single bidders, no valid bids
- **Tie Breaking Tests**: Multiple identical bids and partial ties
- **Numerical Precision Tests**: Floating point precision edge cases
- **Boundary Value Tests**: Values at reserve price boundaries

#### 7. Integration Tests
- **Complete Workflow Tests**: End-to-end auction processes
- **Data Consistency Tests**: Validates data integrity across components
- **Error Handling Tests**: Proper error propagation and handling
- **Cross-Component Tests**: Interactions between different system parts

## Running Tests

### Run All Tests
```julia
julia test/runtests.jl
```

### Run Specific Test Categories
```julia
using Test
include("test/test_config.jl")

# Run only type tests
run_category_tests(:types)

# Run only performance tests  
run_category_tests(:performance)

# Run only edge case tests
run_category_tests(:edge_cases)
```

### Run Individual Test Files
```julia
include("test/test_types.jl")
include("test/test_performance.jl")
include("test/test_edge_cases.jl")
```

## Test Utilities

The test suite includes several utility functions for consistent testing:

### Data Generation
- `generate_test_bidders(n, valuation_range)`: Generate test bidders
- `generate_test_bids(bidders, auction)`: Generate bids from bidders
- `generate_test_config(...)`: Generate simulation configurations

### Assertions
- `assert_valid_auction_result(result)`: Validate auction results
- `assert_valid_bid(bid)`: Validate bid structure
- `assert_valid_bidder(bidder)`: Validate bidder properties
- `assert_results_consistency(results)`: Check result collection consistency

### Performance Testing
- `test_performance(f, max_time)`: Test execution time limits
- `test_memory_usage(f, max_memory)`: Test memory usage limits
- `test_type_stability(f, args...)`: Test type inference stability

### Environment Management
- `with_test_seed(f, seed)`: Execute function with fixed random seed
- `setup_test_environment()`: Initialize test environment
- `cleanup_test_environment()`: Clean up after tests

## Test Configuration

### Constants
- `TEST_SEED = 12345`: Fixed random seed for reproducibility
- `PERFORMANCE_TIMEOUT = 30.0`: Maximum test execution time (seconds)
- `MEMORY_LIMIT = 100_000_000`: Maximum memory usage (bytes)

### Test Data Ranges
- Default valuation range: `(10.0, 100.0)`
- Default bidder count: `10`
- Default auction count: `50`

## Expected Test Coverage

The test suite aims for comprehensive coverage of:

1. **Functionality**: All public functions and methods
2. **Edge Cases**: Boundary conditions and degenerate cases
3. **Error Handling**: Invalid inputs and error conditions
4. **Performance**: Scalability and efficiency requirements
5. **Integration**: Component interactions and workflows
6. **Consistency**: Data integrity and result validation

## Test Requirements

### Julia Packages Required
- `Test.jl`: Core testing framework
- `Random.jl`: Random number generation
- `Statistics.jl`: Statistical functions
- `BenchmarkTools.jl`: Performance benchmarking (optional)

### System Requirements
- Julia 1.0 or higher
- At least 1GB available RAM for large-scale tests
- Multi-threading support (optional, for parallel tests)

## Test Maintenance

### Adding New Tests
1. Add test functions to appropriate test files
2. Use descriptive test names and documentation
3. Include both positive and negative test cases
4. Add performance regression tests for new features
5. Update this README with new test descriptions

### Test Naming Conventions
- Use descriptive names: `@testset "Feature Name Tests"`
- Group related tests together
- Include edge case indicators: `"Edge Case: Empty Input"`
- Use consistent formatting and indentation

### Performance Expectations
- Small tests (< 10 bidders, < 50 auctions): < 1 second
- Medium tests (< 100 bidders, < 500 auctions): < 10 seconds  
- Large tests (< 1000 bidders, < 5000 auctions): < 60 seconds
- Memory usage should scale linearly with problem size

## Troubleshooting

### Common Issues
1. **Type Errors**: Ensure all required types are properly defined
2. **Missing Functions**: Verify all auction and bidding functions exist
3. **Performance Failures**: Check system load and available resources
4. **Random Failures**: Verify random seeds are set consistently

### Debug Mode
To enable verbose test output:
```julia
ENV["JULIA_TEST_VERBOSE"] = "true"
include("test/runtests.jl")
```

## Contributing

When adding new functionality:
1. Write tests before implementation (TDD approach)
2. Ensure new tests pass consistently
3. Add performance benchmarks for new features
4. Update test documentation as needed
5. Consider edge cases and error conditions