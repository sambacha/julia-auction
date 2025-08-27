# Installation Guide

## Prerequisites

### System Requirements
- **Julia**: Version 1.9 or higher
- **Memory**: 8GB RAM minimum, 16GB recommended for production
- **OS**: Linux, macOS, or Windows with WSL2
- **Network**: Internet connectivity for package installation

### Required Tools
```bash
# Check Julia version
julia --version  # Should show 1.9.0 or higher

# Install Julia (if needed)
# macOS
brew install julia

# Linux
wget https://julialang-s3.julialang.org/bin/linux/x64/1.9/julia-1.9.0-linux-x86_64.tar.gz
tar xvfz julia-1.9.0-linux-x86_64.tar.gz

# Windows
# Download installer from https://julialang.org/downloads/
```

## Installation Steps

### 1. Clone the Repository
```bash
git clone https://github.com/julia-auction/julia-auction.git
cd julia-auction
```

### 2. Install Dependencies
```bash
# Using Julia's package manager
julia --project=. -e 'using Pkg; Pkg.instantiate()'

# Or interactively
julia --project=.
julia> using Pkg
julia> Pkg.instantiate()
```

### 3. Verify Installation
```bash
# Run tests
julia --project=. test/runtests.jl

# Expected output
# Test Summary: | Pass  Total
# All Tests     |   97     97
```

### 4. Configuration Setup
```bash
# Copy default configuration
cp config/default.toml config/local.toml

# Edit local configuration as needed
vim config/local.toml
```

## Environment-Specific Setup

### Development Environment
```bash
# Set development environment
export JULIA_AUCTION_ENV=development

# Enable debug logging
export JULIA_DEBUG=AuctionSystem

# Start development server
julia --project=. src/main.jl
```

### Production Environment
```bash
# Set production environment
export JULIA_AUCTION_ENV=production

# Configure production settings
export AUCTION_COORDINATOR_CONSENSUS_THRESHOLD=0.8
export AUCTION_SETTLEMENT_MAX_BATCH_SIZE=100

# Start with production config
julia --project=. --threads=auto src/main.jl
```

## Docker Installation

### Using Docker
```dockerfile
FROM julia:1.9

WORKDIR /app
COPY . .

RUN julia --project=. -e 'using Pkg; Pkg.instantiate()'

ENV JULIA_AUCTION_ENV=production
CMD ["julia", "--project=.", "--threads=auto", "src/main.jl"]
```

### Build and Run
```bash
# Build image
docker build -t julia-auction .

# Run container
docker run -p 8080:8080 \
  -e JULIA_AUCTION_ENV=production \
  julia-auction
```

## Kubernetes Deployment

### Helm Installation
```bash
# Add repository
helm repo add julia-auction https://charts.julia-auction.io

# Install chart
helm install auction julia-auction/auction \
  --set environment=production \
  --set replicas=3 \
  --set resources.requests.memory=16Gi
```

## Verification

### Health Checks
```bash
# Check readiness
curl http://localhost:8080/health/ready

# Check liveness
curl http://localhost:8080/health/live

# Check metrics
curl http://localhost:8080/metrics
```

### API Verification
```julia
using HTTP
using JSON

# Test auction creation
response = HTTP.post(
    "http://localhost:8080/api/v1/auction",
    ["Content-Type" => "application/json"],
    JSON.json(Dict(
        "type" => "uniform_price",
        "reserve_price" => 10.0
    ))
)
```

## Troubleshooting

### Common Issues

#### Package Installation Failures
```bash
# Clear package cache
rm -rf ~/.julia/packages
rm -rf ~/.julia/compiled

# Reinstall
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

#### Memory Issues
```bash
# Increase Julia heap size
export JULIA_HEAP_SIZE=8G
julia --project=. src/main.jl
```

#### Network Connectivity
```bash
# Use proxy if needed
export JULIA_PKG_SERVER="https://pkg.julialang.org"
export HTTP_PROXY="http://proxy.example.com:8080"
```

## Next Steps

- [Configuration Guide](configuration.md) - Configure the system
- [Quick Start Tutorial](guides/quickstart.md) - Run your first auction
- [API Reference](api_reference.md) - Explore the API