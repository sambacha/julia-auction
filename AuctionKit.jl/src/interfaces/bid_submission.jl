# Bid submission interfaces (RPC and direct)
# Following A/HC/LC naming pattern

using HTTP
using JSON3
# Import MetadataValue and MetadataDict from abstract.jl
using ..Actors: MetadataValue, MetadataDict
"""
    BidSubmissionInterface

Abstract type for bid submission interfaces.
"""
abstract type BidSubmissionInterface end

"""
    DirectBidInterface

Direct bid submission through function calls.
"""
struct DirectBidInterface <: BidSubmissionInterface
    controller::AuctionController
end

"""
    RPCBidInterface

RPC-based bid submission interface using HTTP.
"""
mutable struct RPCBidInterface <: BidSubmissionInterface
    controller::AuctionController
    server::Union{Nothing, HTTP.Server}
    port::Int
    host::String
    
    function RPCBidInterface(
        controller::AuctionController;
        port::Int = 8080,
        host::String = "127.0.0.1"
    )
        new(controller, nothing, port, host)
    end
end

# Direct Interface Implementation

# A/HC/LC: submit + Direct + Bid
function submitDirectBid(
    interface::DirectBidInterface,
    auction_id::UUID,
    bidder_id::UUID,
    amount::T,
    quantity::Int = 1;
    metadata::MetadataDict = MetadataDict()
) where T
    # Find the auction actor
    actor = nothing
    lock(interface.controller.state.mutex) do
        for (id, a) in interface.controller.state.active_actors
            if a.state.auction_id == auction_id
                actor = a
                break
            end
        end
    end
    
    if isnothing(actor)
        return Dict(
            :success => false,
            :message => "Auction not found",
            :auction_id => auction_id
        )
    end
    
    # Create bid message
    msg = BidMessage(
        bidder_id,
        auction_id,
        amount,
        quantity,
        metadata,
        now()
    )
    
    # Submit to actor
    send_message_to_actor(actor, msg)
    
    # Wait for response (simplified - in production would use futures)
    return Dict(
        :success => true,
        :message => "Bid submitted",
        :auction_id => auction_id,
        :bidder_id => bidder_id,
        :amount => amount,
        :quantity => quantity,
        :timestamp => now()
    )
end

# A/HC/LC: create + Auction + Direct
function createAuctionDirect(
    interface::DirectBidInterface,
    auction_type::Symbol,
    config::MetadataDict
)
    actor = create_auction_actor(
        auction_type,
        config;
        event_log = interface.controller.state.event_log
    )
    
    lock(interface.controller.state.mutex) do
        interface.controller.state.active_actors[actor.id] = actor
    end
    
    # Start auction
    actor.state.status = :active
    
    return Dict(
        :success => true,
        :auction_id => actor.state.auction_id,
        :auction_type => auction_type,
        :status => :active
    )
end

# A/HC/LC: finalize + Auction + Direct
function finalizeAuctionDirect(
    interface::DirectBidInterface,
    auction_id::UUID
)
    actor = nothing
    lock(interface.controller.state.mutex) do
        for (id, a) in interface.controller.state.active_actors
            if a.state.auction_id == auction_id
                actor = a
                break
            end
        end
    end
    
    if isnothing(actor)
        return Dict(
            :success => false,
            :message => "Auction not found"
        )
    end
    
    msg = FinalizeMessage(false, now())
    send_message_to_actor(actor, msg)
    
    # Wait for finalization
    max_wait = 10.0
    start_wait = now()
    while actor.state.status != :completed
        if (now() - start_wait).value / 1000.0 > max_wait
            return Dict(
                :success => false,
                :message => "Finalization timeout"
            )
        end
        sleep(0.1)
    end
    
    result = actor.state.result
    
    return Dict(
        :success => true,
        :auction_id => auction_id,
        :clearing_price => result.clearing_price,
        :winners => result.winners,
        :allocations => result.allocations,
        :payments => result.payments
    )
end

# RPC Interface Implementation

# A/HC/LC: start + RPC + Server
function startRPCServer(interface::RPCBidInterface)
    router = HTTP.Router()
    
    # POST /auction/create
    HTTP.register!(router, "POST", "/auction/create") do req
        try
            body = JSON3.read(String(req.body))
            auction_type = Symbol(get(body, :auction_type, "first_price"))
            config = MetadataDict(body.config)
            
            result = createAuctionDirect(
                DirectBidInterface(interface.controller),
                auction_type,
                config
            )
            
            return HTTP.Response(200, JSON3.write(result))
        catch e
            error_response = Dict(:success => false, :error => string(e))
            return HTTP.Response(400, JSON3.write(error_response))
        end
    end
    
    # POST /bid/submit
    HTTP.register!(router, "POST", "/bid/submit") do req
        try
            body = JSON3.read(String(req.body))
            
            auction_id = UUID(body.auction_id)
            bidder_id = UUID(get(body, :bidder_id, uuid4()))
            amount = Float64(body.amount)
            quantity = get(body, :quantity, 1)
            metadata = get(body, :metadata, Dict())
            
            result = submitDirectBid(
                DirectBidInterface(interface.controller),
                auction_id,
                bidder_id,
                amount,
                quantity;
                metadata = MetadataDict(metadata)
            )
            
            return HTTP.Response(200, JSON3.write(result))
        catch e
            error_response = Dict(:success => false, :error => string(e))
            return HTTP.Response(400, JSON3.write(error_response))
        end
    end
    
    # POST /auction/finalize
    HTTP.register!(router, "POST", "/auction/finalize") do req
        try
            body = JSON3.read(String(req.body))
            auction_id = UUID(body.auction_id)
            
            result = finalizeAuctionDirect(
                DirectBidInterface(interface.controller),
                auction_id
            )
            
            return HTTP.Response(200, JSON3.write(result))
        catch e
            error_response = Dict(:success => false, :error => string(e))
            return HTTP.Response(400, JSON3.write(error_response))
        end
    end
    
    # GET /auction/status/:id
    HTTP.register!(router, "GET", "/auction/status/*") do req
        try
            path_parts = split(req.target, '/')
            auction_id = UUID(path_parts[end])
            
            actor = nothing
            lock(interface.controller.state.mutex) do
                for (id, a) in interface.controller.state.active_actors
                    if a.state.auction_id == auction_id
                        actor = a
                        break
                    end
                end
            end
            
            if isnothing(actor)
                return HTTP.Response(404, JSON3.write(Dict(
                    :success => false,
                    :message => "Auction not found"
                )))
            end
            
            response = Dict(
                :success => true,
                :auction_id => auction_id,
                :status => actor.state.status,
                :bid_count => length(actor.state.current_bids),
                :start_time => actor.state.start_time,
                :end_time => actor.state.end_time
            )
            
            return HTTP.Response(200, JSON3.write(response))
        catch e
            error_response = Dict(:success => false, :error => string(e))
            return HTTP.Response(400, JSON3.write(error_response))
        end
    end
    
    # Start server
    interface.server = HTTP.serve!(router, interface.host, interface.port; verbose=false)
    
    @info "RPC server started" host=interface.host port=interface.port
    
    return interface
end

# A/HC/LC: stop + RPC + Server
function stopRPCServer(interface::RPCBidInterface)
    if !isnothing(interface.server)
        close(interface.server)
        interface.server = nothing
        @info "RPC server stopped"
    end
end

# A/HC/LC: submit + RPC + Bid
function submitRPCBid(
    host::String,
    port::Int,
    auction_id::UUID,
    amount::Number,
    quantity::Int = 1;
    bidder_id::UUID = uuid4(),
    metadata::Dict = Dict()
)
    url = "http://$host:$port/bid/submit"
    
    body = Dict(
        :auction_id => string(auction_id),
        :bidder_id => string(bidder_id),
        :amount => amount,
        :quantity => quantity,
        :metadata => metadata
    )
    
    response = HTTP.post(
        url,
        ["Content-Type" => "application/json"],
        JSON3.write(body)
    )
    
    return JSON3.read(String(response.body))
end