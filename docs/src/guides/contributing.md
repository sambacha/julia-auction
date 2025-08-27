# Contributing Guidelines

## How to Contribute

We welcome contributions to the Julia Auction System! This guide will help you get started.

## Code of Conduct

Please be respectful and constructive in all interactions. We're building something together!

## Getting Started

1. **Fork the repository** on GitHub
2. **Clone your fork** locally:
   ```bash
   git clone https://github.com/YOUR_USERNAME/julia-auction.git
   cd julia-auction
   ```
3. **Add upstream remote**:
   ```bash
   git remote add upstream https://github.com/julia-auction/julia-auction.git
   ```
4. **Create a feature branch**:
   ```bash
   git checkout -b feature/your-feature-name
   ```

## Making Changes

### Before You Start

- Check existing issues and pull requests
- For major changes, open an issue first to discuss
- Ensure your Julia version is 1.9+

### Development Process

1. **Write tests first** (TDD encouraged)
2. **Implement your feature**
3. **Run tests locally**:
   ```bash
   julia --project=. -e 'using Pkg; Pkg.test()'
   ```
4. **Check style compliance**:
   ```bash
   julia --project=. scripts/check_style.jl
   ```
5. **Update documentation** if needed

### Commit Guidelines

Format your commit messages as:
```
type(scope): brief description

Longer explanation if needed.

Fixes #123
```

Types:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation only
- `style`: Code style changes
- `refactor`: Code refactoring
- `test`: Test additions/changes
- `chore`: Build process or auxiliary tool changes

Example:
```
feat(auction): add support for Dutch auctions

Implements descending price auctions with configurable
price decrements and time intervals.

Fixes #456
```

## Submitting Changes

### Pull Request Process

1. **Update your branch**:
   ```bash
   git fetch upstream
   git rebase upstream/master
   ```

2. **Push to your fork**:
   ```bash
   git push origin feature/your-feature-name
   ```

3. **Create Pull Request** on GitHub

### PR Requirements

Your PR should:
- ✅ Have a clear title and description
- ✅ Reference any related issues
- ✅ Pass all CI checks
- ✅ Include tests for new functionality
- ✅ Update documentation as needed
- ✅ Follow our style guide

### PR Template

```markdown
## Description
Brief description of changes

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Breaking change
- [ ] Documentation update

## Testing
- [ ] Tests pass locally
- [ ] New tests added
- [ ] Existing tests updated

## Checklist
- [ ] Code follows style guide
- [ ] Self-reviewed code
- [ ] Documentation updated
- [ ] No new warnings
```

## Testing Guidelines

### Writing Tests

```julia
using Test

@testset "Feature Tests" begin
    @testset "Normal cases" begin
        # Test expected behavior
        @test function_under_test(input) == expected_output
    end
    
    @testset "Edge cases" begin
        # Test boundaries and special cases
        @test_throws ErrorType function_under_test(invalid_input)
    end
    
    @testset "Performance" begin
        # Test performance requirements
        @test @elapsed function_under_test(input) < 0.010  # 10ms
    end
end
```

### Test Coverage

Aim for >90% code coverage:
```bash
julia --project=. -e 'using Pkg; Pkg.test(coverage=true)'
```

## Documentation

### Documenting Functions

```julia
"""
    function_name(param1::Type1, param2::Type2) -> ReturnType

Brief description of what the function does.

# Arguments
- `param1::Type1`: Description of param1
- `param2::Type2`: Description of param2

# Returns
- `ReturnType`: Description of return value

# Throws
- `ErrorType`: When this error occurs

# Examples
```julia
result = function_name(value1, value2)
```

# See Also
- [`related_function`](@ref)
"""
function function_name(param1::Type1, param2::Type2)::ReturnType
    # Implementation
end
```

### Updating Documentation

1. Edit files in `docs/src/`
2. Build locally to test:
   ```bash
   julia --project=docs docs/make.jl
   ```
3. View at `docs/build/index.html`

## Review Process

### What We Look For

- **Correctness**: Does it work as intended?
- **Performance**: Does it meet performance requirements?
- **Style**: Does it follow our conventions?
- **Tests**: Are there adequate tests?
- **Documentation**: Is it well documented?

### Review Timeline

- Initial review: Within 3 business days
- Follow-up reviews: Within 1 business day
- Small fixes: Often same day

## Getting Help

### Resources

- [Development Guide](development.md)
- [Style Guide](style.md)
- [API Documentation](../api_reference.md)

### Communication Channels

- **GitHub Issues**: Bug reports and feature requests
- **GitHub Discussions**: Questions and discussions
- **Discord**: Real-time chat (link in README)

## Recognition

Contributors are recognized in:
- The CONTRIBUTORS file
- Release notes
- The project README

Thank you for contributing! 🎉