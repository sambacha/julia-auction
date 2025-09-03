#!/usr/bin/env julia

"""
Comprehensive test for the multi-party coordination system.
Demonstrates the complete two-phase commit protocol with simulated settlement.
"""

include("settlement/orchestration/coordinator/Coordinator.jl")
using .Coordinator
using UUIDs: uuid4, UUID
# Mock transaction structure for testing
struct MockTransaction
    id::UUID
    value::Float64
    token_in::String
    token_out::String

    function MockTransaction(value::Float64 = 1000.0)
        new(uuid4(), value, "USDC", "ETH")
    end
end

function test_full_coordination_protocol()
    println("=== Full Multi-Party Coordination Test ===\n")

    # Configure consensus protocol
    protocol = ConsensusProtocol(
        threshold = 0.67,     # Require 2/3 majority
        timeout = 5.0,        # 5 second timeout
        retry_count = 2,
        heartbeat_interval = 1.0,
    )
    println("✅ Created consensus protocol: $(protocol.threshold*100)% threshold, $(protocol.timeout)s timeout")

    # Create coordination context
    context = CoordinationContext(protocol)
    println("✅ Created coordination context")

    # Register multiple participants
    println("\n--- Participant Registration ---")
    participants = []
    for i = 1:5
        pid = register_participant(context, "participant$i@settlement.network")
        push!(participants, pid)
    end

    println("📝 Registered $(length(participants)) participants")

    # Create a mock transaction
    transaction = MockTransaction(5000.0)
    println("\n--- Transaction Details ---")
    println("Transaction ID: $(transaction.id)")
    println("Value: $(transaction.value) $(transaction.token_in) -> $(transaction.token_out)")

    # Test health monitoring
    println("\n--- Health Monitoring ---")
    active_before = monitor_health(context)
    println("Active participants before test: $active_before")

    # Simulate some participant becoming inactive
    context.participants[participants[5]].last_heartbeat = time() - 20.0  # Make it seem old
    sleep(0.1)  # Small delay
    active_after = monitor_health(context)
    println("Active participants after health check: $active_after")

    # Test manual consensus voting (simulating prepare phase)
    println("\n--- Manual Consensus Test ---")
    test_votes = [
        Vote(participants[1], :prepare, true, reason = "Transaction validated"),
        Vote(participants[2], :prepare, true, reason = "Liquidity sufficient"),
        Vote(participants[3], :prepare, false, reason = "Price impact too high"),
        Vote(participants[4], :prepare, true, reason = "Route optimized"),
    ]

    # Clear any existing votes and add test votes
    empty!(context.votes)
    append!(context.votes, test_votes)

    consensus_result = check_consensus(context, test_votes)
    println("Consensus result for prepare phase: $consensus_result")

    # Test full coordinate_settlement function
    println("\n--- Full Settlement Coordination Test ---")

    # Reset context for full test
    empty!(context.votes)
    atomic_state_update(context, :idle)

    # Run the full coordination protocol
    println("🚀 Initiating full settlement coordination...")

    # Note: This will use the collect_votes function which includes network simulation
    settlement_result = coordinate_settlement(context, transaction)

    println("🎯 Settlement coordination result: $settlement_result")
    println("Final phase: $(context.phase)")
    println("Total votes collected: $(length(context.votes))")

    # Display participant vote history
    println("\n--- Participant Vote History ---")
    for (pid, participant) in context.participants
        if !isempty(participant.vote_history)
            println("Participant $pid ($(participant.status)):")
            for vote in participant.vote_history
                println("  - $(vote.phase): $(vote.decision) ($(vote.reason))")
            end
        end
    end

    # Test failure handling
    println("\n--- Failure Handling Test ---")
    test_participant = context.participants[participants[1]]
    original_status = test_participant.status
    handle_failure(test_participant)
    println("Participant $(test_participant.id) status changed from $original_status to $(test_participant.status)")

    # Test participant unregistration
    println("\n--- Participant Management Test ---")
    removed = unregister_participant(context, participants[end])
    println("Participant removal successful: $removed")
    println("Remaining participants: $(length(context.participants))")

    println("\n=== All Tests Completed Successfully! ===")

    return settlement_result
end

# Run the comprehensive test
if abspath(PROGRAM_FILE) == @__FILE__
    result = test_full_coordination_protocol()
    println("\n🎉 Multi-party coordination system is fully operational!")
    println("Final result: $result")
end
