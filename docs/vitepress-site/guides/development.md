# Development Guide

## Setting Up Your Development Environment

### Prerequisites

- Julia 1.9+ installed
- Git for version control
- Your favorite code editor (VS Code with Julia extension recommended)
- Docker (optional, for containerized development)

### Initial Setup

```bash
# Clone the repository
git clone https://github.com/julia-auction/julia-auction.git
cd julia-auction

# Install Julia dependencies
julia --project=. -e 'using Pkg; Pkg.instantiate()'

# Run tests to verify setup
julia --project=. -e 'using Pkg; Pkg.test()'
```

### Development Workflow

1. Create a feature branch
2. Make your changes
3. Run tests and style checks
4. Submit a pull request

See our [Contributing Guidelines](contributing.md) for detailed instructions.

## Code Organization

```
julia-auction/
├── src/              # Source code
├── test/             # Test files  
├── docs/             # Documentation
├── config/           # Configuration files
└── scripts/          # Utility scripts
```

## Testing

Run all tests:
```bash
julia --project=. -e 'using Pkg; Pkg.test()'
```

Run specific tests:
```bash
julia --project=. test/auction_tests.jl
```

## Documentation

Build documentation locally:
```bash
julia --project=docs docs/make.jl
```

View at `docs/build/index.html`