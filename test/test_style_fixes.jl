#!/usr/bin/env julia

println("Testing style fixes...")

# Test that the renamed functions are accessible
include("AuctionKit.jl/src/AuctionKit.jl")
using .AuctionKit
using Dates
using UUIDs

# Create a simple auction actor with the new function name
actor = create_auction_actor(
    :first_price,
    Dict{Symbol,Any}(:reserve_price => 100.0, :start_time => now(), :end_time => now() + Dates.Hour(1)),
)

println("✓ create_auction_actor works")

# Send a message with the new function name
bid_msg = BidMessage(uuid4(), actor.state.auction_id, 110.0, 1, Dict{Symbol,Any}(), now())
send_message_to_actor(actor, bid_msg)

println("✓ send_message_to_actor works")

# Stop actor with the new function name
stop_actor_gracefully(actor)

println("✓ stop_actor_gracefully works")

println("\n✅ All renamed functions work correctly!")
