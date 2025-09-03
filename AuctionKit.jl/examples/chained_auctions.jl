# Chained auctions example demonstrating workflow orchestration
using AuctionKit
using UUIDs
println("=== Chained Auctions Example ===\n")
println("Scenario: Multi-stage procurement auction")
println("Stage 1: Suppliers bid to provide raw materials (Dutch auction)")
println("Stage 2: Winners from Stage 1 bid for manufacturing contract (English auction)")
println("Stage 3: Final assembly contract (Vickrey auction)\n")

# Create controller
controller = AuctionController{Float64}()

# Define auction chain configuration
auction_configs = [
    # Stage 1: Dutch auction for raw materials
    Dict{Symbol, Any}(
        :auction_type => :dutch,
        :reserve_price => 1000.0,
        :starting_price => 2000.0,
        :decrement => 100.0,
        :duration_seconds => 0,
        :initial_bids => [
            Dict(:bidder_id => uuid4(), :amount => 1800.0, :quantity => 1, 
                 :metadata => Dict(:supplier => "SupplierA")),
            Dict(:bidder_id => uuid4(), :amount => 1600.0, :quantity => 1,
                 :metadata => Dict(:supplier => "SupplierB")),
            Dict(:bidder_id => uuid4(), :amount => 1500.0, :quantity => 1,
                 :metadata => Dict(:supplier => "SupplierC"))
        ]
    ),
    
    # Stage 2: English auction for manufacturing
    Dict{Symbol, Any}(
        :auction_type => :english,
        :reserve_price => 2000.0,
        :increment => 200.0,
        :duration_seconds => 0,
        :propagate_winners => true,  # Winners from Stage 1 participate
        :transformation => function(config, inputs)
            # Custom transformation: adjust reserve based on Stage 1 results
            if !isempty(inputs)
                prev_result = first(values(inputs))
                config[:reserve_price] = prev_result.clearing_price * 2.0
            end
            return config
        end
    ),
    
    # Stage 3: Vickrey auction for final assembly
    Dict{Symbol, Any}(
        :auction_type => :vickrey,
        :reserve_price => 3000.0,
        :duration_seconds => 0,
        :propagate_winners => true,
        :aggregation => function(result, inputs)
            # Custom aggregation: calculate total supply chain cost
            total_cost = result.clearing_price
            for (_, prev_result) in inputs
                total_cost += prev_result.clearing_price
            end
            result.metadata[:total_supply_chain_cost] = total_cost
            return result
        end
    )
]

println("Executing chained auction workflow...")
workflow_result = chainAuctions(controller, auction_configs)

println("\n=== Workflow Results ===")
println("Workflow ID: $(workflow_result.workflow_id)")
println("Total duration: $((workflow_result.end_time - workflow_result.start_time).value / 1000.0) seconds")
println("Execution order: $(workflow_result.execution_order)")

# Display results for each stage
for (idx, node_id) in enumerate(workflow_result.execution_order)
    result = workflow_result.node_results[node_id]
    println("\n--- Stage $idx Results ---")
    println("Auction type: $(get(result.metadata, :auction_type, "unknown"))")
    println("Clearing price: \$$(result.clearing_price)")
    println("Number of winners: $(length(result.winners))")
    
    if haskey(result.metadata, :total_supply_chain_cost)
        println("Total supply chain cost: \$$(result.metadata[:total_supply_chain_cost])")
    end
end

# Create a more complex workflow with parallel branches
println("\n\n=== Complex Workflow Example ===")
println("Creating parallel auction branches that converge...\n")

# Create workflow graph manually for more control
graph = WorkflowGraph{Float64}()

# Create parallel auctions
node1 = WorkflowNode{Float64}(
    auction_config = Dict{Symbol, Any}(
        :auction_type => :first_price,
        :reserve_price => 100.0,
        :duration_seconds => 0,
        :initial_bids => [
            Dict(:bidder_id => uuid4(), :amount => 120.0, :quantity => 1),
            Dict(:bidder_id => uuid4(), :amount => 150.0, :quantity => 1)
        ]
    )
)

node2 = WorkflowNode{Float64}(
    auction_config = Dict{Symbol, Any}(
        :auction_type => :first_price,
        :reserve_price => 200.0,
        :duration_seconds => 0,
        :initial_bids => [
            Dict(:bidder_id => uuid4(), :amount => 220.0, :quantity => 1),
            Dict(:bidder_id => uuid4(), :amount => 250.0, :quantity => 1)
        ]
    )
)

# Convergence node that depends on both parallel auctions
node3 = WorkflowNode{Float64}(
    auction_config = Dict{Symbol, Any}(
        :auction_type => :vickrey,
        :reserve_price => 300.0,
        :duration_seconds => 0
    ),
    dependencies = [node1.id, node2.id],
    transformation = function(config, inputs)
        # Combine winners from both parallel auctions
        all_winners = UUID[]
        for (_, result) in inputs
            append!(all_winners, result.winners)
        end
        
        # Create bids from combined winners
        config[:initial_bids] = [
            Dict(:bidder_id => winner, :amount => 350.0 + rand() * 50, :quantity => 1)
            for winner in all_winners
        ]
        
        return config
    end
)

# Add nodes to graph
graph.nodes[node1.id] = node1
graph.nodes[node2.id] = node2
graph.nodes[node3.id] = node3

# Add edges
push!(graph.edges, (node1.id, node3.id))
push!(graph.edges, (node2.id, node3.id))

println("Executing complex workflow with parallel branches...")
complex_result = executeWorkflow(controller, graph)

println("\nComplex Workflow Results:")
println("- Parallel Auction 1: \$$(complex_result.node_results[node1.id].clearing_price)")
println("- Parallel Auction 2: \$$(complex_result.node_results[node2.id].clearing_price)")
println("- Convergence Auction: \$$(complex_result.node_results[node3.id].clearing_price)")
println("- Total auctions executed: $(length(complex_result.node_results))")

# Clean up
stopController(controller)

println("\n=== Example completed ===")