# Basic auction example
using AuctionKit
using UUIDs
println("=== Basic First-Price Auction Example ===\n")

# Create controller and event log
event_log = CentralizedEventLog()
controller = AuctionController{Float64}(event_log=event_log)

# Create direct interface for bid submission
interface = DirectBidInterface(controller)

println("1. Creating first-price auction...")
auction_result = createAuctionDirect(
    interface,
    :first_price,
    Dict{Symbol, Any}(
        :reserve_price => 100.0,
        :tie_breaking => :first_come
    )
)

auction_id = auction_result[:auction_id]
println("   Auction created with ID: $auction_id")

# Submit bids from different bidders
println("\n2. Submitting bids...")

bidders = [
    (uuid4(), "Alice", 150.0),
    (uuid4(), "Bob", 175.0),
    (uuid4(), "Charlie", 160.0),
    (uuid4(), "David", 180.0)
]

for (bidder_id, name, amount) in bidders
    result = submitDirectBid(
        interface,
        auction_id,
        bidder_id,
        amount,
        1;
        metadata = Dict{Symbol, Any}(:bidder_name => name)
    )
    println("   $name bid \$$amount - $(result[:success] ? "accepted" : "rejected")")
end

# Finalize auction
println("\n3. Finalizing auction...")
final_result = finalizeAuctionDirect(interface, auction_id)

if final_result[:success]
    println("   Auction finalized successfully!")
    println("   Clearing price: \$$(final_result[:clearing_price])")
    println("   Winners: $(length(final_result[:winners]))")
    
    # Find winner name
    for (bidder_id, name, _) in bidders
        if bidder_id in final_result[:winners]
            payment = get(final_result[:payments], bidder_id, 0.0)
            println("   Winner: $name pays \$$payment")
        end
    end
end

# Query events from log
println("\n4. Audit trail from event log:")
events = queryEventsByAuction(event_log, auction_id)
println("   Total events recorded: $(length(events))")

for event in events[1:min(5, length(events))]
    event_type = typeof(event.wrapped_event)
    println("   - $event_type at $(event.timestamp)")
end

# Verify log integrity
if verifyLogIntegrity(event_log)
    println("   ✓ Event log integrity verified")
end

# Clean up
stopController(controller)

println("\n=== Example completed ===")