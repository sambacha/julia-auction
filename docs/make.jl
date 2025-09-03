using Documenter
using DocumenterVitepress

# Load the modules to document (if they exist)
push!(LOAD_PATH, "../src/")
push!(LOAD_PATH, "../src/settlement/")
push!(LOAD_PATH, "../AuctionKit.jl/src/")

# Configure DocumenterVitepress
makedocs(
    sitename = "Julia Auctions",
    authors = "Sam Bacha",
    
    # Use DocumenterVitepress format
    format = DocumenterVitepress.MarkdownVitepress(
        repo = "https://github.com/sambacha/julia-auction",
        devurl = "dev",
        devbranch = "master",
    ),
    
    # Module documentation - comment out for now since modules may not be loaded
    # modules = [AugmentedUniformPriceAuction, PostCFMMSettlement],
    
    # Disable doctesting for now since modules aren't loaded
    doctest = false,
    
    # Disable cross-reference checks to avoid errors with missing modules
    checkdocs = :none,
    linkcheck = false,
    
    # Page structure with rich content
    pages = [
        "Home" => "index.md",
        
        "Getting Started" => [
            "Installation" => "guides/installation.md",
            "Quick Start" => "guides/quickstart.md",
            "Core Concepts" => "guides/concepts.md",
        ],
        
        "Auction Mechanisms" => [
            "Overview" => "theory/overview.md",
            "Augmented Uniform Price" => "theory/augmented_uniform.md",
            "Bid Shading Analysis" => "theory/bid_shading.md",
            "Elastic Supply" => "theory/elastic_supply.md",
        ],
        
        "API Reference" => [
            "Augmented Auctions" => "api/augmented.md",
            "Post-CFMM Settlement" => "api/settlement.md",
            "Phantom Auctions" => "api/phantom.md",
        ],
        
        "Examples" => [
            "Basic Auction" => "examples/basic.md",
            "Advanced Features" => "examples/advanced.md",
            "Performance Analysis" => "examples/performance.md",
        ],
        
        "Theory & Research" => [
            "Academic Background" => "theory/academic.md",
            "MEV Protection" => "theory/mev.md",
            "References" => "theory/references.md",
        ],
    ],
    
    # Custom settings
    repo = "https://github.com/sambacha/julia-auction",
)

# Deploy documentation to GitHub Pages
# Only deploy when running in CI
if get(ENV, "CI", "false") == "true"
    deploydocs(
        repo = "github.com/sambacha/julia-auction.git",
        devbranch = "master",  # Changed to match your default branch
        push_preview = true,
        forcepush = true,
        target = "build",  # Specify the build directory
    )
end
