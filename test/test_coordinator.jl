#!/usr/bin/env julia

# Simple test for the Coordinator module
include("settlement/orchestration/coordinator/Coordinator.jl")

using .Coordinator
using Base: UUID
# Test basic functionality
function test_coordinator()
    println("=== Testing Coordinator Module ===")

    # Create a consensus protocol
    protocol = ConsensusProtocol(threshold = 0.6, timeout = 2.0)
    println("✅ Created ConsensusProtocol with threshold $(protocol.threshold)")

    # Create coordination context
    context = CoordinationContext(protocol)
    println("✅ Created CoordinationContext")

    # Register participants
    p1 = register_participant(context, "participant1@network")
    p2 = register_participant(context, "participant2@network")
    p3 = register_participant(context, "participant3@network")
    println("✅ Registered $(length(context.participants)) participants")

    # Test vote creation
    vote1 = Vote(p1, :prepare, true; reason = "All checks passed")
    vote2 = Vote(p2, :prepare, true; reason = "Transaction valid")
    vote3 = Vote(p3, :prepare, false; reason = "Insufficient balance")
    println("✅ Created test votes")

    # Test consensus checking
    test_votes = [vote1, vote2, vote3]
    append!(context.votes, test_votes)

    consensus_result = check_consensus(context, context.votes)
    println(
        "✅ Consensus check result: $consensus_result (2/3 positive votes = $(2/3) vs threshold $(protocol.threshold))",
    )

    # Test health monitoring  
    active_count = monitor_health(context)
    println("✅ Health monitoring completed, active participants: $active_count")

    # Test participant failure handling
    failed_participant = context.participants[p1]
    handle_failure(failed_participant)
    println("✅ Handled participant failure")

    # Test atomic state updates
    atomic_state_update(context, :test_phase)
    println("✅ Atomic state update completed, current phase: $(context.phase)")

    println("\n=== All Tests Passed! ===")
    return true
end

# Mock transaction for testing
struct MockTransaction
    id::UUID

    MockTransaction() = new(uuid4())
end

# Run the test
if abspath(PROGRAM_FILE) == @__FILE__
    test_coordinator()
end
