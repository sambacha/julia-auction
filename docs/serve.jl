#!/usr/bin/env julia

# Build and serve documentation locally

using Pkg
Pkg.activate(".")
Pkg.instantiate()

include("make.jl")

println("\n✅ Documentation built successfully!")
println("\n📚 View documentation at: http://localhost:8000")
println("\nPress Ctrl+C to stop the server\n")

# Start HTTP server
run(`python3 -m http.server 8000 --directory build`)