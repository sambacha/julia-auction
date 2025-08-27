# Writing Guidelines

## Documentation Standards

### Clear and Concise Writing

1. **Use active voice**: "The system processes bids" not "Bids are processed by the system"
2. **Be specific**: "Returns the clearing price in USD" not "Returns a value"
3. **Keep sentences short**: Aim for 15-20 words per sentence
4. **Use examples**: Show, don't just tell

### Code Documentation

```julia
"""
    calculate_clearing_price(bids::Vector{Bid}, supply::Float64) -> Float64

Calculate the market clearing price for a uniform price auction.

# Arguments
- `bids::Vector{Bid}`: Sorted list of bids (highest price first)
- `supply::Float64`: Total quantity available

# Returns
- `Float64`: The clearing price where supply meets demand

# Example
```julia
bids = [Bid("alice", 100.0, 50.0), Bid("bob", 150.0, 45.0)]
price = calculate_clearing_price(bids, 200.0)
```
"""
function calculate_clearing_price(bids::Vector{Bid}, supply::Float64)
    # Implementation
end
```

### API Documentation

- Start with a brief overview
- List all parameters with types and descriptions
- Provide example requests and responses
- Document error conditions
- Include rate limits and authentication requirements

### Markdown Best Practices

- Use proper heading hierarchy (don't skip levels)
- Include a table of contents for long documents
- Use code blocks with language hints
- Add alt text to images
- Keep line length under 100 characters

## Style Guide

### Julia Code Style

Follow the official Julia style guide:
- Use `snake_case` for functions
- Use `UpperCamelCase` for types
- Keep lines under 92 characters
- Use 4 spaces for indentation

### Commit Messages

Format:
```
type(scope): brief description

Longer explanation if needed.
Multiple paragraphs are fine.

Fixes #123
```

Types: feat, fix, docs, style, refactor, test, chore