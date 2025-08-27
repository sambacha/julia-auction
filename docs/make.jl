using Documenter
# Load the modules to document (if they exist)
push!(LOAD_PATH, "../src/")
push!(LOAD_PATH, "../src/settlement/")
push!(LOAD_PATH, "../AuctionKit.jl/src/")

# Configure Documenter
makedocs(
    sitename = "Julia Auction System",
    authors = "Julia Auction Team",
    
    # Use default Documenter styling
    format = Documenter.HTML(
        prettyurls = get(ENV, "CI", nothing) == "true",
        canonical = "https://julia-auction.github.io/julia-auction",
        collapselevel = 2,
        sidebar_sitename = true,
        # Use KaTeX for math rendering
        mathengine = Documenter.KaTeX()
    ),
    
    # Module documentation - comment out for now since modules may not be loaded
    # modules = [AugmentedUniformPriceAuction, PostCFMMSettlement],
    
    # Disable doctesting for now since modules aren't loaded
    doctest = false,
    
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
    repo = "https://github.com/julia-auction/julia-auction",
)

# Deploy documentation to GitHub Pages
deploydocs(
    repo = "github.com/julia-auction/julia-auction.git",
    devbranch = "main",
    push_preview = true,
    forcepush = true,
)