module AuctionKit

using UUIDs
using Dates
using SHA
using DataStructures
using Graphs
using HTTP
using JSON3
using Base.Threads: @spawn, Atomic

# Export main types and functions
export 
    # Abstract types
    AbstractActor, AbstractAuction, AuctionMechanism,
    SealedBidAuction, OpenOutcryAuction,
    AbstractController, AbstractWorkflow,
    
    # Core types
    Bid, Bidder, AuctionResult, AuctionState,
    AuctionActor, AuctionController,
    WorkflowNode, WorkflowGraph, WorkflowResult,
    
    # Event types
    AuctionEvent, ImmutableEvent, CentralizedEventLog,
    BidSubmittedEvent, BidRejectedEvent, AuctionStartedEvent,
    AuctionFinalizedEvent, AuctionCancelledEvent,
    
    # Auction mechanisms
    FirstPriceAuction, VickreyAuction, DutchAuction, EnglishAuction,
    
    # Interfaces
    DirectBidInterface, RPCBidInterface,
    
    # Actor messages
    ActorMessage, BidMessage, FinalizeMessage,
    QueryMessage, UpdateConfigMessage, StateSnapshotMessage,
    BidResponse,
    
    # Core functions
    createAuctionActor, sendMessageToActor, stopActorGracefully,
    createAuctionDirect, submitDirectBid, finalizeAuctionDirect,
    startRPCServer, stopRPCServer, submitRPCBid,
    
    # Event log functions
    appendEventToLog, queryEventsByAuction, queryEventsByType,
    verifyLogIntegrity, replayEventsFromLog,
    
    # Mechanism functions
    determineClearingPrice, allocateWinners, calculatePayments,
    finalizeFirstPriceAuction, finalizeVickreyAuction,
    finalizeDutchAuction, finalizeEnglishAuction,
    
    # Controller functions
    executeWorkflow, chainAuctions, propagateResults,
    createWorkflowGraph, validateDAGStructure, topologicalSortWorkflow,
    getWorkflowStatus, stopController,
    
    # Utility functions
    filterValidBids, sortBidsByPrice, sortBidsByTimestamp,
    resolveTiesWithRule, calculateTotalQuantity,
    
    # Internal auction functions (for testing)
    updateCurrentPrice, acceptEnglishBid

# Include all source files
# Order matters to avoid circular dependencies
include("actors/abstract.jl")
include("actors/state.jl")  # Define AuctionState before mechanisms
include("events/abstract.jl")
include("events/event_log.jl")
include("actors/messages.jl")
include("mechanisms/abstract.jl")
include("mechanisms/first_price.jl")
include("mechanisms/vickrey.jl")
include("mechanisms/dutch.jl")
include("mechanisms/english.jl")
include("actors/auction_actor.jl")
include("controller/abstract.jl")
include("controller/auction_controller.jl")
include("interfaces/bid_submission.jl")

end # module AuctionKit