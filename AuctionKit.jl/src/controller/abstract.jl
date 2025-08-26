# Abstract types for auction controllers and workflows
# Following A/HC/LC naming pattern

"""
    AbstractController{T}

Abstract type for auction controllers that orchestrate workflows.
"""
abstract type AbstractController{T} end

"""
    AbstractWorkflow{T}

Abstract type for auction workflow definitions.
"""
abstract type AbstractWorkflow{T} end

"""
    WorkflowNode{T}

Represents a single node in an auction workflow graph.
"""
struct WorkflowNode{T}
    id::UUID
    auction_config::Dict{Symbol, Any}
    dependencies::Vector{UUID}  # IDs of upstream nodes
    transformation::Function  # Function to transform inputs before auction
    aggregation::Function  # Function to aggregate results for downstream
    metadata::Dict{Symbol, Any}
    
    function WorkflowNode{T}(;
        auction_config::Dict{Symbol, Any},
        dependencies::Vector{UUID} = UUID[],
        transformation::Function = identity,
        aggregation::Function = identity,
        metadata::Dict{Symbol, Any} = Dict{Symbol, Any}()
    ) where T
        new{T}(
            uuid4(),
            auction_config,
            dependencies,
            transformation,
            aggregation,
            metadata
        )
    end
end

"""
    WorkflowGraph{T}

Directed acyclic graph of auction workflows.
"""
struct WorkflowGraph{T}
    nodes::Dict{UUID, WorkflowNode{T}}
    edges::Vector{Tuple{UUID, UUID}}  # (from, to) pairs
    
    function WorkflowGraph{T}() where T
        new{T}(Dict{UUID, WorkflowNode{T}}(), Vector{Tuple{UUID, UUID}}())
    end
end

"""
    WorkflowResult{T}

Result from executing a workflow.
"""
struct WorkflowResult{T}
    workflow_id::UUID
    node_results::Dict{UUID, AuctionResult{T}}
    execution_order::Vector{UUID}
    start_time::DateTime
    end_time::DateTime
    metadata::Dict{Symbol, Any}
end

"""
    ControllerState{T}

State maintained by the controller.
"""
mutable struct ControllerState{T}
    id::UUID
    active_workflows::Dict{UUID, WorkflowGraph{T}}
    workflow_results::Dict{UUID, WorkflowResult{T}}
    active_actors::Dict{UUID, AuctionActor{T}}
    event_log::Union{Nothing, CentralizedEventLog}
    mutex::ReentrantLock
end

# Required interface functions

"""
    executeWorkflow(controller, workflow)

Execute a complete workflow through the controller.
"""
function executeWorkflow end

"""
    chainAuctions(controller, configs)

Chain multiple auctions together with dependencies.
"""
function chainAuctions end

"""
    propagateResults(controller, from_node, to_node, result)

Propagate results from one auction to another.
"""
function propagateResults end