# Main auction controller implementation
# Following A/HC/LC naming pattern

using Graphs: SimpleDiGraph, add_edge!, is_cyclic
"""
    AuctionController{T}

Main controller for orchestrating auction workflows and chaining.
"""
mutable struct AuctionController{T} <: AbstractController{T}
    state::ControllerState{T}
    executor::Task
    running::Atomic{Bool}
    
    function AuctionController{T}(;
        event_log::Union{Nothing, CentralizedEventLog} = nothing
    ) where T
        state = ControllerState{T}(
            uuid4(),
            Dict{UUID, WorkflowGraph{T}}(),
            Dict{UUID, WorkflowResult{T}}(),
            Dict{UUID, AuctionActor{T}}(),
            event_log,
            ReentrantLock()
        )
        
        controller = new{T}(
            state,
            Task(() -> nothing),
            Atomic{Bool}(true)
        )
        
        # Start controller executor
        controller.executor = @spawn runControllerExecutor(controller)
        
        return controller
    end
end

# A/HC/LC: create + Workflow + Graph
function createWorkflowGraph(controller::AuctionController{T}, configs::Vector{Dict{Symbol, Any}}) where T
    graph = WorkflowGraph{T}()
    
    # Create nodes from configs
    node_ids = UUID[]
    for config in configs
        node = WorkflowNode{T}(
            auction_config = config,
            dependencies = get(config, :dependencies, UUID[]),
            transformation = get(config, :transformation, identity),
            aggregation = get(config, :aggregation, identity),
            metadata = get(config, :metadata, Dict{Symbol, Any}())
        )
        graph.nodes[node.id] = node
        push!(node_ids, node.id)
    end
    
    # Build edges based on dependencies
    for node in values(graph.nodes)
        for dep_id in node.dependencies
            push!(graph.edges, (dep_id, node.id))
        end
    end
    
    # Validate DAG structure
    if !validateDAGStructure(graph)
        throw(ArgumentError("Workflow graph contains cycles"))
    end
    
    return graph
end

# A/HC/LC: validate + DAG + Structure
function validateDAGStructure(graph::WorkflowGraph{T}) where T
    # Build adjacency list
    n_nodes = length(graph.nodes)
    if n_nodes == 0
        return true
    end
    
    # Create mapping from UUID to index
    id_to_idx = Dict{UUID, Int}()
    idx_to_id = UUID[]
    for (idx, id) in enumerate(keys(graph.nodes))
        id_to_idx[id] = idx
        push!(idx_to_id, id)
    end
    
    # Build directed graph
    g = SimpleDiGraph(n_nodes)
    for (from_id, to_id) in graph.edges
        if haskey(id_to_idx, from_id) && haskey(id_to_idx, to_id)
            add_edge!(g, id_to_idx[from_id], id_to_idx[to_id])
        end
    end
    
    # Check for cycles
    return !is_cyclic(g)
end

# A/HC/LC: topological + Sort + Workflow
function topologicalSortWorkflow(graph::WorkflowGraph{T}) where T
    # Build adjacency information
    in_degree = Dict{UUID, Int}()
    adjacency = Dict{UUID, Vector{UUID}}()
    
    for node_id in keys(graph.nodes)
        in_degree[node_id] = 0
        adjacency[node_id] = UUID[]
    end
    
    for (from_id, to_id) in graph.edges
        in_degree[to_id] = get(in_degree, to_id, 0) + 1
        push!(adjacency[from_id], to_id)
    end
    
    # Kahn's algorithm
    queue = UUID[]
    for (node_id, degree) in in_degree
        if degree == 0
            push!(queue, node_id)
        end
    end
    
    sorted_order = UUID[]
    while !isempty(queue)
        current = popfirst!(queue)
        push!(sorted_order, current)
        
        for neighbor in adjacency[current]
            in_degree[neighbor] -= 1
            if in_degree[neighbor] == 0
                push!(queue, neighbor)
            end
        end
    end
    
    if length(sorted_order) != length(graph.nodes)
        throw(ArgumentError("Workflow graph contains cycles"))
    end
    
    return sorted_order
end

# A/HC/LC: execute + Workflow
function executeWorkflow(controller::AuctionController{T}, workflow::WorkflowGraph{T}) where T
    workflow_id = uuid4()
    
    lock(controller.state.mutex) do
        controller.state.active_workflows[workflow_id] = workflow
    end
    
    # Get execution order
    execution_order = topologicalSortWorkflow(workflow)
    
    # Execute nodes in topological order
    node_results = Dict{UUID, AuctionResult{T}}()
    start_time = now()
    
    for node_id in execution_order
        node = workflow.nodes[node_id]
        
        # Gather inputs from dependencies
        inputs = Dict{UUID, AuctionResult{T}}()
        for dep_id in node.dependencies
            if haskey(node_results, dep_id)
                inputs[dep_id] = node_results[dep_id]
            end
        end
        
        # Transform inputs
        transformed_config = node.transformation(node.auction_config, inputs)
        
        # Execute auction
        result = executeAuctionNode(controller, node, transformed_config)
        
        # Aggregate results
        aggregated_result = node.aggregation(result, inputs)
        node_results[node_id] = aggregated_result
    end
    
    end_time = now()
    
    # Store workflow result
    workflow_result = WorkflowResult{T}(
        workflow_id,
        node_results,
        execution_order,
        start_time,
        end_time,
        Dict{Symbol, Any}(
            :total_nodes => length(execution_order),
            :total_duration => (end_time - start_time).value / 1000.0
        )
    )
    
    lock(controller.state.mutex) do
        controller.state.workflow_results[workflow_id] = workflow_result
        delete!(controller.state.active_workflows, workflow_id)
    end
    
    return workflow_result
end

# A/HC/LC: execute + Auction + Node
function executeAuctionNode(
    controller::AuctionController{T},
    node::WorkflowNode{T},
    config::Dict{Symbol, Any}
) where T
    # Create auction actor
    auction_type = get(config, :auction_type, :first_price)
    actor = create_auction_actor(auction_type, config; event_log=controller.state.event_log)
    
    lock(controller.state.mutex) do
        controller.state.active_actors[actor.id] = actor
    end
    
    # Start auction
    actor.state.status = :active
    
    # Submit any initial bids from config
    initial_bids = get(config, :initial_bids, [])
    for bid_data in initial_bids
        msg = BidMessage(
            get(bid_data, :bidder_id, uuid4()),
            actor.state.auction_id,
            T(get(bid_data, :amount, 0)),
            get(bid_data, :quantity, 1),
            get(bid_data, :metadata, Dict{Symbol, Any}()),
            now()
        )
        send_message_to_actor(actor, msg)
    end
    
    # Wait for auction duration or immediate finalization
    auction_duration = get(config, :duration_seconds, 60)
    if auction_duration > 0
        sleep(auction_duration)
    end
    
    # Finalize auction
    finalize_msg = FinalizeMessage(false, now())
    send_message_to_actor(actor, finalize_msg)
    
    # Wait for result
    max_wait = 10.0  # seconds
    start_wait = now()
    while actor.state.status != :completed
        if (now() - start_wait).value / 1000.0 > max_wait
            throw(ErrorException("Auction finalization timeout"))
        end
        sleep(0.1)
    end
    
    result = actor.state.result
    
    # Clean up
    stop_actor_gracefully(actor)
    lock(controller.state.mutex) do
        delete!(controller.state.active_actors, actor.id)
    end
    
    return result
end

# A/HC/LC: chain + Auctions
function chainAuctions(
    controller::AuctionController{T},
    configs::Vector{Dict{Symbol, Any}}
) where T
    # Build workflow graph with sequential dependencies
    for i in 2:length(configs)
        if !haskey(configs[i], :dependencies)
            configs[i][:dependencies] = UUID[]
        end
        # Each auction depends on the previous one
        # This creates a chain structure
    end
    
    workflow = createWorkflowGraph(controller, configs)
    
    # Set up result propagation
    for i in 2:length(configs)
        node_ids = collect(keys(workflow.nodes))
        if i <= length(node_ids)
            prev_node = node_ids[i-1]
            curr_node = node_ids[i]
            
            # Update transformation function to use previous result
            workflow.nodes[curr_node].transformation = function(config, inputs)
                if !isempty(inputs)
                    prev_result = first(values(inputs))
                    # Propagate winners as new bidders
                    new_bidders = []
                    for winner_id in prev_result.winners
                        push!(new_bidders, Dict(
                            :bidder_id => winner_id,
                            :amount => prev_result.clearing_price * T(1.1),  # Bid 10% higher
                            :quantity => 1
                        ))
                    end
                    config[:initial_bids] = new_bidders
                end
                return config
            end
        end
    end
    
    return executeWorkflow(controller, workflow)
end

# A/HC/LC: propagate + Results
function propagateResults(
    controller::AuctionController{T},
    from_result::AuctionResult{T},
    to_config::Dict{Symbol, Any}
) where T
    # Extract relevant information from source result
    propagated_data = Dict{Symbol, Any}(
        :previous_clearing_price => from_result.clearing_price,
        :previous_winners => from_result.winners,
        :previous_allocations => from_result.allocations
    )
    
    # Merge with target config
    merged_config = merge(to_config, propagated_data)
    
    # Transform winners into new bidders if specified
    if get(to_config, :propagate_winners, false)
        new_bids = []
        for winner_id in from_result.winners
            allocation = get(from_result.allocations, winner_id, one(T))
            push!(new_bids, Dict(
                :bidder_id => winner_id,
                :amount => from_result.clearing_price,
                :quantity => allocation
            ))
        end
        merged_config[:initial_bids] = get(merged_config, :initial_bids, []) ∪ new_bids
    end
    
    return merged_config
end

# A/HC/LC: run + Controller + Executor
function runControllerExecutor(controller::AuctionController)
    while controller.running[]
        # Process any pending workflow executions
        sleep(0.1)  # Polling interval
        
        # Could add queue-based workflow scheduling here
    end
end

# A/HC/LC: stop + Controller
function stopController(controller::AuctionController)
    controller.running[] = false
    
    # Stop all active actors
    lock(controller.state.mutex) do
        for actor in values(controller.state.active_actors)
            stop_actor_gracefully(actor)
        end
    end
    
    wait(controller.executor)
end

# A/HC/LC: get + Workflow + Status
function getWorkflowStatus(controller::AuctionController, workflow_id::UUID)
    lock(controller.state.mutex) do
        if haskey(controller.state.active_workflows, workflow_id)
            return :active
        elseif haskey(controller.state.workflow_results, workflow_id)
            return :completed
        else
            return :not_found
        end
    end
end