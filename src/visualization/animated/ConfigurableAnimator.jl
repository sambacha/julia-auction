"""
ConfigurableAnimator.jl - Configuration-driven animation system

This module integrates the animation system with the auction configuration
framework, enabling zero-code-change animation support through configuration files.
"""
module ConfigurableAnimator

using TOML
using ..AuctionSimulator
using Makie, GLMakie
using Observables

# Import animation modules
include("AnimationHooks.jl")
include("AutoAnimator.jl")

using .AnimationHooks
using .AutoAnimator

export setup_animations, load_animation_config, AnimationSystem

# Animation system state
mutable struct AnimationSystem
    config::Dict{String,Any}
    enabled::Bool
    mode::AutoAnimator.AnimationMode
    hooks_installed::Bool
    dashboard_active::Bool
end

const ANIMATION_SYSTEM = AnimationSystem(Dict{String,Any}(), false, AutoAnimator.DISABLED, false, false)

"""
    setup_animations(config_path::String = "config/animation.toml")

Set up the animation system based on configuration file.
This function is automatically called when the module is loaded if
a configuration file exists.

# Arguments
- `config_path::String`: Path to the animation configuration file

# Examples
```julia
# Use default configuration
setup_animations()

# Use custom configuration
setup_animations("my_config.toml")

# After setup, run simulations normally - animations will be automatic
result = run_simulation(auction, bidders, config)
```
"""
function setup_animations(config_path::String = "config/animation.toml")
    if !isfile(config_path)
        @info "Animation config not found at $config_path, using defaults"
        config_path = joinpath(@__DIR__, "../../../config/animation.toml")
    end

    # Load configuration
    config = load_animation_config(config_path)
    ANIMATION_SYSTEM.config = config

    # Check if animations are enabled
    if !get(config["animation"], "enabled", false)
        @info "Animations disabled in configuration"
        return false
    end

    # Parse animation mode
    mode_str = get(config["animation"], "mode", "interactive")
    mode = parse_animation_mode(mode_str)
    ANIMATION_SYSTEM.mode = mode

    if mode == AutoAnimator.DISABLED
        return false
    end

    # Configure animation system
    configure_animation_system(config, mode)

    # Install hooks if needed
    if !ANIMATION_SYSTEM.hooks_installed
        install_animation_hooks(config)
        ANIMATION_SYSTEM.hooks_installed = true
    end

    ANIMATION_SYSTEM.enabled = true

    @info "Animation system configured" mode=mode_str

    return true
end

"""
    load_animation_config(path::String)

Load animation configuration from TOML file.
"""
function load_animation_config(path::String)::Dict{String,Any}
    if !isfile(path)
        # Return default configuration
        return default_animation_config()
    end

    try
        config = TOML.parsefile(path)
        # Merge with defaults to ensure all keys exist
        return merge_with_defaults(config)
    catch e
        @warn "Error loading animation config, using defaults" error=e
        return default_animation_config()
    end
end

"""
    default_animation_config()

Return default animation configuration.
"""
function default_animation_config()::Dict{String,Any}
    return Dict{String,Any}(
        "animation" => Dict{String,Any}(
            "enabled" => false,
            "mode" => "interactive",
            "auto_detect" => true,
            "output_dir" => "animations",
            "dashboard_layout" => "full",
            "performance_mode" => false,
            "frame_rate" => 30,
            "resolution" => [1400, 900],
        ),
        "theme" => Dict{String,Any}(
            "fontsize" => 14,
            "font" => "Helvetica",
            "backgroundcolor" => "white",
            "colormap" => "viridis",
        ),
        "panels" => Dict{String,Any}(
            "show_bids" => true,
            "show_prices" => true,
            "show_efficiency" => true,
            "show_winners" => true,
            "show_statistics" => true,
            "show_revenue" => true,
        ),
        "triggers" => Dict{String,Any}(
            "min_bidders" => 2,
            "min_rounds" => 1,
            "record_on_efficiency_drop" => false,
            "efficiency_threshold" => 0.8,
        ),
        "export" =>
            Dict{String,Any}("format" => "mp4", "quality" => "high", "compress" => true, "include_timestamp" => true),
        "realtime" => Dict{String,Any}(
            "update_interval_ms" => 100,
            "smooth_transitions" => true,
            "show_bid_trails" => true,
            "highlight_winners" => true,
            "animate_price_discovery" => true,
        ),
        "colors" => Dict{String,Any}(
            "bid_color" => "#3498db",
            "winning_bid_color" => "#2ecc71",
            "price_line_color" => "#e74c3c",
            "efficiency_color" => "#27ae60",
            "revenue_color" => "#f39c12",
            "grid_color" => "#95a5a6",
        ),
        "advanced" => Dict{String,Any}(
            "use_gpu" => true,
            "cache_frames" => true,
            "max_memory_gb" => 2.0,
            "parallel_rendering" => false,
            "interpolation_method" => "linear",
        ),
    )
end

"""
    merge_with_defaults(config::Dict)

Merge loaded configuration with defaults.
"""
function merge_with_defaults(config::Dict{String,Any})::Dict{String,Any}
    defaults = default_animation_config()
    return merge_recursive(defaults, config)
end

"""
    merge_recursive(dict1::Dict, dict2::Dict)

Recursively merge two dictionaries.
"""
function merge_recursive(dict1::Dict, dict2::Dict)::Dict
    result = copy(dict1)
    for (key, value) in dict2
        if haskey(result, key) && isa(result[key], Dict) && isa(value, Dict)
            result[key] = merge_recursive(result[key], value)
        else
            result[key] = value
        end
    end
    return result
end

"""
    parse_animation_mode(mode_str::String)

Parse animation mode from string.
"""
function parse_animation_mode(mode_str::String)::AutoAnimator.AnimationMode
    mode_map = Dict(
        "disabled" => AutoAnimator.DISABLED,
        "passive" => AutoAnimator.PASSIVE,
        "interactive" => AutoAnimator.INTERACTIVE,
        "recording" => AutoAnimator.RECORDING,
    )

    return get(mode_map, lowercase(mode_str), AutoAnimator.INTERACTIVE)
end

"""
    configure_animation_system(config::Dict, mode::AnimationMode)

Configure the animation system with loaded settings.
"""
function configure_animation_system(config::Dict{String,Any}, mode::AutoAnimator.AnimationMode)
    anim_config = config["animation"]

    # Set up AutoAnimator with configuration
    AutoAnimator.auto_animate(
        mode,
        output_dir = get(anim_config, "output_dir", "animations"),
        theme = create_makie_theme(config),
        dashboard_layout = Symbol(get(anim_config, "dashboard_layout", "full")),
        performance_mode = get(anim_config, "performance_mode", false),
        auto_detect = get(anim_config, "auto_detect", true),
    )

    # Configure AnimationHooks if needed
    if mode != AutoAnimator.DISABLED
        context = AnimationHooks.AnimationContext(
            enabled = true,
            auto_record = mode == AutoAnimator.RECORDING,
            frame_rate = get(anim_config, "frame_rate", 30),
            resolution = tuple(get(anim_config, "resolution", [1400, 900])...),
            output_format = Symbol(get(config["export"], "format", "mp4")),
            theme = Symbol(get(config["theme"], "colormap", "viridis")),
        )

        AnimationHooks.enable_animations!(context)
    end
end

"""
    create_makie_theme(config::Dict)

Create Makie theme from configuration.
"""
function create_makie_theme(config::Dict{String,Any})
    theme_config = get(config, "theme", Dict())
    colors_config = get(config, "colors", Dict())

    return Attributes(
        fontsize = get(theme_config, "fontsize", 14),
        font = get(theme_config, "font", "Helvetica"),
        backgroundcolor = parse_color(get(theme_config, "backgroundcolor", "white")),
        colormap = get(theme_config, "colormap", :viridis),
        Axis = (
            xgridcolor = parse_color(get(colors_config, "grid_color", "#95a5a6")),
            ygridcolor = parse_color(get(colors_config, "grid_color", "#95a5a6")),
        ),
        Lines = (linewidth = 3,),
        Scatter = (markersize = 10,),
    )
end

"""
    parse_color(color_str::String)

Parse color from string (hex or named).
"""
function parse_color(color_str::String)
    if startswith(color_str, "#")
        # Parse hex color
        hex = color_str[2:end]
        r = parse(Int, hex[1:2], base = 16) / 255.0
        g = parse(Int, hex[3:4], base = 16) / 255.0
        b = parse(Int, hex[5:6], base = 16) / 255.0
        return RGBf(r, g, b)
    else
        # Use named color
        return Symbol(color_str)
    end
end

"""
    install_animation_hooks(config::Dict)

Install animation hooks based on configuration.
"""
function install_animation_hooks(config::Dict{String,Any})
    triggers = get(config, "triggers", Dict())

    # Extended hook installation with trigger conditions
    @eval AuctionSimulator begin
        const _original_run_simulation_config = run_simulation

        function run_simulation(auction_type, bidders, sim_config::AuctionConfig)
            # Check trigger conditions
            triggers = ConfigurableAnimator.ANIMATION_SYSTEM.config["triggers"]

            should_animate = (
                length(bidders) >= get(triggers, "min_bidders", 2) &&
                sim_config.num_rounds >= get(triggers, "min_rounds", 1)
            )

            if should_animate && ConfigurableAnimator.ANIMATION_SYSTEM.enabled
                # Run with animation
                ConfigurableAnimator.before_simulation(auction_type, bidders, sim_config)
                result = _original_run_simulation_config(auction_type, bidders, sim_config)
                ConfigurableAnimator.after_simulation(result)
                return result
            else
                # Run without animation
                return _original_run_simulation_config(auction_type, bidders, sim_config)
            end
        end
    end
end

"""
    before_simulation(auction_type, bidders, config)

Hook called before simulation starts.
"""
function before_simulation(auction_type, bidders, config::AuctionConfig)
    if ANIMATION_SYSTEM.mode == AutoAnimator.INTERACTIVE
        @info "Starting animated simulation" type=typeof(auction_type) bidders=length(bidders) rounds=config.num_rounds
    end

    # Check for efficiency drop recording
    if get(ANIMATION_SYSTEM.config["triggers"], "record_on_efficiency_drop", false)
        # Switch to recording mode if needed
        if ANIMATION_SYSTEM.mode == AutoAnimator.INTERACTIVE
            ANIMATION_SYSTEM.mode = AutoAnimator.RECORDING
            @info "Switching to recording mode for efficiency monitoring"
        end
    end
end

"""
    after_simulation(result::SimulationResult)

Hook called after simulation completes.
"""
function after_simulation(result::SimulationResult)
    # Check efficiency threshold
    triggers = get(ANIMATION_SYSTEM.config, "triggers", Dict())
    threshold = get(triggers, "efficiency_threshold", 0.8)

    if mean(result.efficiencies) < threshold
        @warn "Efficiency below threshold" mean_efficiency=mean(result.efficiencies) threshold=threshold

        # Save animation if in recording mode
        if ANIMATION_SYSTEM.mode == AutoAnimator.RECORDING
            save_efficiency_report(result)
        end
    end

    # Generate export if configured
    if get(ANIMATION_SYSTEM.config["export"], "include_timestamp", true)
        export_animation(result)
    end
end

"""
    save_efficiency_report(result::SimulationResult)

Save special report for low-efficiency auctions.
"""
function save_efficiency_report(result::SimulationResult)
    timestamp = Dates.format(Dates.now(), "yyyymmdd_HHMMSS")
    output_dir = get(ANIMATION_SYSTEM.config["animation"], "output_dir", "animations")

    report_file = joinpath(output_dir, "efficiency_report_$(timestamp).txt")

    open(report_file, "w") do io
        println(io, "Low Efficiency Auction Report")
        println(io, "=" ^ 40)
        println(io, "Auction Type: $(result.auction_type)")
        println(io, "Mean Efficiency: $(mean(result.efficiencies))")
        println(io, "Min Efficiency: $(minimum(result.efficiencies))")
        println(io, "Max Efficiency: $(maximum(result.efficiencies))")
        println(io, "Total Revenue: $(sum(result.revenues))")
        println(io, "Winner Distribution:")
        for (bidder, wins) in result.bidder_wins
            println(io, "  Bidder $bidder: $wins wins")
        end
    end

    @info "Efficiency report saved" file=report_file
end

"""
    export_animation(result::SimulationResult)

Export animation based on configuration.
"""
function export_animation(result::SimulationResult)
    export_config = get(ANIMATION_SYSTEM.config, "export", Dict())

    if !get(export_config, "include_timestamp", true)
        return
    end

    format = get(export_config, "format", "mp4")
    quality = get(export_config, "quality", "high")
    compress = get(export_config, "compress", true)

    # Export logic handled by AutoAnimator
    animation_data = AutoAnimator.get_current_animation()

    if animation_data.figure !== nothing
        @info "Animation export complete" format=format quality=quality
    end
end

# Module initialization
function __init__()
    # Check for configuration file on module load
    default_config_path = joinpath(@__DIR__, "../../../config/animation.toml")

    # Check environment variable for custom config
    config_path = get(ENV, "JULIA_AUCTION_ANIMATION_CONFIG", default_config_path)

    if isfile(config_path)
        # Auto-setup if config exists
        setup_animations(config_path)
    elseif haskey(ENV, "JULIA_AUCTION_ANIMATE")
        # Fall back to environment variable control
        @info "Using environment variable for animation control"
    else
        @info "Animation system available. Call setup_animations() to enable."
    end
end

end # module ConfigurableAnimator
