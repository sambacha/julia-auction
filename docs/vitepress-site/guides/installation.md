# Installation Guide

## Document Information
**Type:** Setup Instructions
**Requirements:** Julia 1.6+
**Time Required:** 10-15 minutes

## Executive Summary

This guide provides complete installation instructions for the Julia Auction System. Users install Julia, clone the repository, and verify functionality through example executions. The process requires basic command-line familiarity and internet connectivity for package downloads.

## Prerequisites

### System Requirements

Your system requires these components before installation:

**Software Requirements:**
- Julia version 1.6 or higher
- Git for repository cloning
- Terminal or command prompt access

**Hardware Requirements:**
- 4GB RAM minimum (8GB recommended)
- 1GB disk space for dependencies
- Internet connection for packages

### Julia Installation

Download Julia from the official website:

1. Visit [julialang.org/downloads](https://julialang.org/downloads)
2. Select your operating system version
3. Run the installer following platform instructions
4. Verify installation: `julia --version`

## Installation Process

### Step 1: Clone Repository

Open your terminal and clone the project:

```bash
git clone https://github.com/your-org/julia-auction.git
cd julia-auction
```

This command creates a local copy of the entire codebase.

### Step 2: Activate Environment

Start Julia with the project environment:

```bash
julia --project=.
```

The `--project=.` flag activates the local Project.toml environment.

### Step 3: Install Dependencies

Within the Julia REPL, install all required packages:

```julia
using Pkg
Pkg.instantiate()  # Downloads and installs dependencies
```

Package installation typically takes 3-5 minutes depending on connection speed.

### Step 4: Verify Installation

Test the installation with a simple auction:

```julia
# Load simulation module
include("src/simulation.jl")

# Create default configuration
config = default_config()

# Verify modules load correctly
println("Installation successful!")
```

Expected output: "Installation successful!" without errors.

## Running Examples

### Basic Auction Example

Execute the included examples to explore functionality:

```bash
julia --project=. examples/usage_examples.jl
```

This script demonstrates core auction mechanisms with various configurations.

### Augmented Auction Demo

Run the augmented uniform price auction demonstration:

```bash
julia --project=. examples/augmented_auction_demo.jl
```

The demo showcases elastic supply schedules and tie-breaking mechanisms.

### Visualization Example

Generate auction visualization plots:

```bash
julia --project=. examples/visualization_demo.jl
```

Output files appear in the `auction_visualizations/` directory.

## Testing Installation

### Run Test Suite

Verify complete installation through the test suite:

```julia
using Pkg
Pkg.test()
```

Tests validate all core functionality and report any issues.

### Expected Test Output

Successful tests display:
- "Test Summary: Julia Auction System | Pass"
- Individual module test results
- No error messages or failures

## Troubleshooting

### Common Issues and Solutions

**Julia Version Incompatibility**

*Problem:* "ERROR: This package requires Julia 1.6+"

*Solution:* Update Julia from [julialang.org](https://julialang.org/downloads). Verify version with `julia --version`.

**Package Installation Failures**

*Problem:* "ERROR: Unable to install packages"

*Solution:* 
1. Check internet connectivity
2. Clear package cache: `rm -rf ~/.julia/packages/`
3. Retry: `Pkg.instantiate()`

**Memory Errors During Simulation**

*Problem:* "ERROR: OutOfMemoryError()"

*Solution:*
1. Reduce simulation parameters in configuration
2. Close other applications
3. Increase system swap space

**Module Loading Errors**

*Problem:* "ERROR: UndefVarError: module not defined"

*Solution:*
1. Ensure correct project activation: `julia --project=.`
2. Reinstall packages: `Pkg.instantiate()`
3. Check file paths are correct

### Getting Help

**Documentation Resources:**
- Review [API Reference](../../api_reference.md) for function details
- Check [Examples](../examples/) for usage patterns
- See [Development Guide](development.md) for advanced setup

**Community Support:**
- Submit issues to the GitHub repository
- Review existing issues for solutions
- Contact maintainers for critical problems

## Development Setup

### Additional Tools for Development

Developers require additional tools:

**Recommended IDE:**
- VS Code with Julia extension
- Juno IDE for Atom (deprecated but functional)
- Jupyter notebooks for experimentation

**Development Dependencies:**
```julia
Pkg.add("Revise")      # Auto-reload code changes
Pkg.add("BenchmarkTools")  # Performance testing
Pkg.add("ProfileView")     # Profiling visualization
```

**Git Configuration:**
```bash
git config user.name "Your Name"
git config user.email "your.email@example.com"
```

## Next Steps

After successful installation:

1. **Explore Examples:** Review [Basic Examples](../examples/basic.md) for usage patterns
2. **Read Concepts:** Understand [Core Concepts](concepts.md) for theoretical background
3. **Try Tutorials:** Follow [Quick Start](quickstart.md) for hands-on learning
4. **Review API:** Study [API Reference](../../api_reference.md) for function details

## Summary

Installation completes in four steps: clone repository, activate environment, install dependencies, and verify functionality. The system requires Julia 1.6+ with 4GB RAM minimum. Test suite validation confirms proper installation. Examples demonstrate core functionality for immediate exploration.