module AuctionKit

using Base.Threads: @spawn, Atomic
using DataStructures
using Dates
using Graphs
using HTTP
using JSON3
using SHA
using UUIDs
using Combinatorics
using JuMP
using HiGHS
using Random
using Statistics
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
    CombinatorialAuction, SealedBidDoubleAuction, AllPayAuction,
    JapaneseAuction, CandleAuction, PennyAuction,
    
    # Interfaces
    DirectBidInterface, RPCBidInterface,
    
    # Actor messages
    ActorMessage, BidMessage, FinalizeMessage,
    QueryMessage, UpdateConfigMessage, StateSnapshotMessage,
    BidResponse,
    
    # Core functions
    create_auction_actor, send_message_to_actor, stop_actor_gracefully,
    createAuctionDirect, submitDirectBid, finalizeAuctionDirect,
    startRPCServer, stopRPCServer, submitRPCBid,
    
    # Event log functions
    append_event_to_log, queryEventsByAuction, queryEventsByType,
    verifyLogIntegrity, replayEventsFromLog,
    
    # Mechanism functions
    determineClearingPrice, allocateWinners, calculatePayments,
    finalizeFirstPriceAuction, finalizeVickreyAuction,
    finalizeDutchAuction, finalizeEnglishAuction,
    finalizeCombinatorialAuction, finalizeDoubleAuction,
    finalizeAllPayAuction, finalizeJapaneseAuction,
    finalizeCandleAuction, finalizePennyAuction,
    
    # Controller functions
    executeWorkflow, chainAuctions, propagateResults,
    createWorkflowGraph, validateDAGStructure, topologicalSortWorkflow,
    getWorkflowStatus, stopController,
    
    # Utility functions
    filterValidBids, sortBidsByPrice, sortBidsByTimestamp,
    resolveTiesWithRule, calculateTotalQuantity,
    
    # Unified interface
    UnifiedAuctionConfig, StandardizedResult, AuctionFactory,
    run_unified_auction, compare_auction_types,
    analyze_auction_performance, recommend_auction_type,
    
    # Additional types
    BundleBid, Order,
    
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
include("mechanisms/combinatorial.jl")
include("mechanisms/double.jl")
include("mechanisms/all_pay.jl")
include("mechanisms/japanese.jl")
include("mechanisms/candle.jl")
include("mechanisms/penny.jl")
include("mechanisms/unified_interface.jl")
include("actors/auction_actor.jl")
include("controller/abstract.jl")
include("controller/auction_controller.jl")
include("interfaces/bid_submission.jl")

end # module AuctionKit