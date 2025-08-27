# Installation Guide

## Prerequisites

You need:
- Julia 1.6 or higher
- Git to clone the repository

## Installation Steps

1. Clone the repository:
```bash
git clone https://github.com/julia-auction/julia-auction.git
cd julia-auction
```

2. Add to Julia environment:
```julia
using Pkg
Pkg.add(path=".")
```

3. Install dependencies:
```julia
Pkg.instantiate()
```

## Verify Installation

Test your installation:
```julia
using AugmentedUniformPriceAuction
bid = Bid("test", 100.0, 50.0)
```